%%% @doc The PURE core of the robotaxi fleet brain.
%%%
%%% `tick/5' advances every vehicle one step and returns the new fleet state
%%% plus a list of command EFFECTS (the milestone commands to dispatch into
%%% the vehicle aggregate). It performs NO I/O — no store, no mesh, no clock,
%%% no routing HTTP. Routing is injected as a `RouteFun' so the gen_server
%%% can pass `route_leg:route/2' in production and a stub in tests.
%%%
%%% This is where the "physics" lives: vehicles move along their road
%%% polyline, drain battery by distance, and fire a milestone when a leg
%%% completes. Dispatch policy (take a fare / go charge) is decided here too.
%%%
%%% Effect = {Command :: atom(), Payload :: map()}  e.g.
%%%   {dispatch_vehicle, #{vehicle_id => ..., trip_id => ..., ...}}
-module(simulate_fleet_core).

-include_lib("parksim_simulator/include/fleet.hrl").

-export([new/3, tick/5, vehicles/1, snapshot/1]).
%% Milestone callbacks — exported so advance/3 can dispatch via ?MODULE:F.
-export([on_reach_pickup/2, on_reach_dropoff/2, on_reach_facility/2]).

-record(core, {
    operator   :: #operator{},
    params     :: map(),
    facilities :: [#facility{}],
    bays_free  :: #{binary() => non_neg_integer()},
    vehicles   :: #{binary() => #fveh{}},
    rng        :: rand:state()
}).

-opaque t() :: #core{}.
-export_type([t/0]).

%% Routing: {Polyline :: [{X,Y}], DistanceM :: number()}.
-type route_fun() :: fun(({number(), number()}, {number(), number()}) ->
                            {[{number(), number()}], number()}).

%%--------------------------------------------------------------------
%% Construction

%% @doc A fresh fleet for `Operator', all vehicles freshly commissioned at
%% the home depot with a full battery. Returns the core plus the commission
%% effects to dispatch.
-spec new(#operator{}, map(), rand:state()) -> {t(), [{atom(), map()}]}.
new(#operator{fleet_size = N, home = HomeId} = Op, Params, Rng) ->
    Facs = fleet_config:facilities(),
    Home = facility(HomeId, Facs),
    Bays = maps:from_list([{F#facility.id, F#facility.bays} || F <- Facs]),
    Vehs0 = [new_vehicle(Op, I, Home) || I <- lists:seq(1, N)],
    Vehicles = maps:from_list([{V#fveh.id, V} || V <- Vehs0]),
    Effects = [{commission_vehicle,
                #{vehicle_id  => V#fveh.id,
                  company_id  => Op#operator.id,
                  battery_pct => V#fveh.battery_pct,
                  x => V#fveh.x, y => V#fveh.y}}
               || V <- Vehs0],
    Core = #core{operator = Op, params = Params, facilities = Facs,
                 bays_free = Bays, vehicles = Vehicles, rng = Rng},
    {Core, Effects}.

new_vehicle(#operator{id = Op}, I, #facility{x = X, y = Y}) ->
    Id = iolist_to_binary([Op, "-taxi-", integer_to_list(I)]),
    #fveh{id = Id, phase = commissioned, x = X, y = Y,
          heading = 0.0, battery_pct = 100.0}.

%%--------------------------------------------------------------------
%% Tick

%% @doc Advance the fleet one tick. `TickSimSecs' is how much sim time
%% elapsed since the last tick; `NewRequests' are ride requests that arose
%% this tick; `RouteFun' computes a {polyline, distance} for a leg. Returns
%% the new core, the number of effects, and the command effects produced.
-spec tick(t(), integer(), number(), [#ride_request{}], route_fun()) ->
    {t(), number(), [{atom(), map()}]}.
tick(#core{} = Core0, SimUnix, TickSimSecs, NewRequests, RouteFun) ->
    Ctx0 = #{core => Core0, requests => NewRequests, sim => SimUnix,
             tick_sim_secs => TickSimSecs,
             route => RouteFun, effects => []},
    Ids = maps:keys(Core0#core.vehicles),
    Ctx1 = lists:foldl(fun(Id, Ctx) -> step(Id, Ctx) end, Ctx0, Ids),
    #{core := Core1, effects := Effects} = Ctx1,
    {Core1, length(Effects), lists:reverse(Effects)}.

%%--------------------------------------------------------------------
%% Per-vehicle step

step(Id, Ctx) ->
    Core = maps:get(core, Ctx),
    V = maps:get(Id, Core#core.vehicles),
    step_phase(V#fveh.phase, V, Ctx).

%% Idle (commissioned or cruising): decide between a fare and a charge run.
step_phase(P, V, Ctx) when P =:= commissioned; P =:= cruising ->
    #{core := Core} = Ctx,
    case service_needs(V, Core#core.params) of
        []  -> try_take_fare(V, Ctx);
        _   -> begin_return(V, Ctx)
    end;
step_phase(dispatched, V, Ctx) -> advance(V, Ctx, on_reach_pickup);
step_phase(on_trip,    V, Ctx) -> advance(V, Ctx, on_reach_dropoff);
step_phase(returning,  V, Ctx) -> advance(V, Ctx, on_reach_facility);
step_phase(servicing,  V, Ctx) -> maybe_finish_service(V, Ctx);
step_phase(depleted,   V, Ctx) -> maybe_tow(V, Ctx);
step_phase(docked,     V, Ctx) -> put_veh(V, Ctx).   %% transient; serviced next tick

%%--------------------------------------------------------------------
%% Idle decisions

try_take_fare(V, Ctx) ->
    #{requests := Reqs, core := Core} = Ctx,
    MinPct = maps:get(min_dispatch_pct, Core#core.params),
    case {Reqs, V#fveh.battery_pct >= MinPct} of
        {[Req | Rest], true} ->
            Route = maps:get(route, Ctx),
            {Path, _D} = Route({V#fveh.x, V#fveh.y}, Req#ride_request.pickup),
            V1 = V#fveh{phase = dispatched, leg = to_pickup, path = Path,
                        trip_id = trip_id(Req), pickup = Req#ride_request.pickup,
                        dropoff = Req#ride_request.dropoff, trip_m = 0.0},
            Ctx1 = Ctx#{requests => Rest},
            emit(V1, {dispatch_vehicle,
                      #{vehicle_id => V1#fveh.id, trip_id => V1#fveh.trip_id,
                        pickup_x => x_of(V1#fveh.pickup),
                        pickup_y => y_of(V1#fveh.pickup),
                        dropoff_x => x_of(V1#fveh.dropoff),
                        dropoff_y => y_of(V1#fveh.dropoff)}},
                 put_veh(V1, Ctx1));
        _ ->
            put_veh(V, Ctx)   %% no fare (or too flat) — idle this tick
    end.

begin_return(V, Ctx) ->
    #{core := Core} = Ctx,
    case nearest_free_facility(V, Core) of
        none ->
            put_veh(V, Ctx);   %% no free bay anywhere — wait, retry next tick
        #facility{id = FacId} = Fac ->
            Route = maps:get(route, Ctx),
            {Path, _D} = Route({V#fveh.x, V#fveh.y},
                               {Fac#facility.x, Fac#facility.y}),
            Core1 = take_bay(Core, FacId),   %% reserve the bay now
            V1 = V#fveh{phase = returning, leg = to_facility, path = Path,
                        dest_facility = FacId},
            emit(V1, {return_vehicle,
                      #{vehicle_id => V1#fveh.id, facility_id => FacId}},
                 put_veh(V1, Ctx#{core => Core1}))
    end.

%%--------------------------------------------------------------------
%% Movement

advance(V, Ctx, OnReach) ->
    #{core := Core} = Ctx,
    Params = Core#core.params,
    BudgetM = maps:get(cruise_speed_mps, Params) * tick_sim_secs(Ctx),
    {NewPath, NewPos, MovedM, Done} =
        walk(V#fveh.path, {V#fveh.x, V#fveh.y}, BudgetM),
    Drain = (MovedM / 1000.0) * maps:get(battery_drain_per_km, Params),
    Battery = V#fveh.battery_pct - Drain,
    NewX = x_of(NewPos), NewY = y_of(NewPos),
    Heading = heading_deg(V#fveh.x, V#fveh.y, NewX, NewY, V#fveh.heading),
    V1 = V#fveh{path = NewPath, x = NewX, y = NewY, heading = Heading,
                battery_pct = Battery, trip_m = V#fveh.trip_m + MovedM,
                km_since_maint = V#fveh.km_since_maint + MovedM / 1000.0},
    case Battery =< 0.0 of
        true  -> deplete(V1, Ctx);
        false ->
            case Done of
                true  -> ?MODULE:OnReach(V1, Ctx);
                false -> put_veh(V1, Ctx)
            end
    end.

%% Travel direction in degrees: 0 = +x (east), +90 = +y (south on the map,
%% whose y increases downward). Matches the SVG rotate() the realm map applies
%% to the car marker. Holds the previous heading on a zero-length step so a
%% parked car keeps facing where it last drove.
heading_deg(X0, Y0, X1, Y1, Prev) ->
    Dx = X1 - X0, Dy = Y1 - Y0,
    case (abs(Dx) < 1.0e-9) andalso (abs(Dy) < 1.0e-9) of
        true  -> Prev;
        false -> math:atan2(Dy, Dx) * 180.0 / math:pi()
    end.

%% Walk along the polyline consuming up to BudgetM metres.
walk([], Pos, _Budget) -> {[], Pos, 0.0, true};
walk(Path, Pos, Budget) -> walk(Path, Pos, Budget, 0.0).

walk([], Pos, _Budget, Moved) -> {[], Pos, Moved, true};
walk([Next | Rest] = Path, Pos, Budget, Moved) ->
    D = route_leg:dist(Pos, Next),
    case D =< Budget of
        true ->
            walk(Rest, Next, Budget - D, Moved + D);
        false ->
            F = case D < 1.0e-9 of true -> 1.0; false -> Budget / D end,
            NewPos = route_leg:interpolate(Pos, Next, F),
            {Path, NewPos, Moved + Budget, false}
    end.

%%--------------------------------------------------------------------
%% Leg-completion milestones

on_reach_pickup(V, Ctx) ->
    Route = maps:get(route, Ctx),
    {Path, _D} = Route(V#fveh.pickup, V#fveh.dropoff),
    V1 = V#fveh{phase = on_trip, leg = to_dropoff, path = Path, trip_m = 0.0},
    emit(V1, {pick_up_passenger,
              #{vehicle_id => V1#fveh.id,
                x => V1#fveh.x, y => V1#fveh.y}},
         put_veh(V1, Ctx)).

on_reach_dropoff(V, Ctx) ->
    #{core := Core} = Ctx,
    Fare = fare_cents(V#fveh.trip_m, Core#core.params),
    Dirt = maps:get(clean_per_trip, Core#core.params, 0),
    V1 = V#fveh{phase = cruising, leg = none, path = [],
                cleanliness_pct = max(0.0, V#fveh.cleanliness_pct - Dirt),
                trip_id = undefined, pickup = undefined, dropoff = undefined},
    emit(V1, {drop_off_passenger,
              #{vehicle_id => V1#fveh.id, fare_cents => Fare,
                x => V1#fveh.x, y => V1#fveh.y}},
         put_veh(V1, Ctx)).

on_reach_facility(V, Ctx) ->
    #{core := Core, sim := SimUnix} = Ctx,
    FacId = V#fveh.dest_facility,
    Fac = facility(FacId, Core#core.facilities),
    %% Service every overdue need this visit (the facility supports), in order.
    Needs = [K || K <- service_needs(V, Core#core.params),
                  lists:member(K, Fac#facility.kinds)],
    [Kind | Rest] = case Needs of [] -> [<<"charge">>]; _ -> Needs end,
    Dur = service_secs(Kind, Core#core.params),
    Bay = bay_id(FacId, V),
    V1 = V#fveh{phase = servicing, leg = none, path = [],
                dest_bay = Bay, service_kind = Kind, service_queue = Rest,
                service_until = SimUnix + Dur,
                x = Fac#facility.x, y = Fac#facility.y},
    %% Two milestones: dock, then begin service (on the first kind).
    Ctx2 = add_effect({dock_at_facility,
                       #{vehicle_id => V1#fveh.id, facility_id => FacId,
                         bay_id => Bay, x => Fac#facility.x,
                         y => Fac#facility.y}}, Ctx),
    emit(V1, {service_vehicle, #{vehicle_id => V1#fveh.id, kind => Kind}},
         put_veh(V1, Ctx2)).

%%--------------------------------------------------------------------
%% Service completion + tow

maybe_finish_service(V, Ctx) ->
    #{sim := SimUnix, core := Core} = Ctx,
    case SimUnix >= V#fveh.service_until of
        false -> put_veh(V, Ctx);
        true  ->
            V1 = apply_service(V#fveh.service_kind, V),
            case V1#fveh.service_queue of
                [Next | Rest] ->
                    %% Same visit, next overdue kind — stay in the bay.
                    Dur = service_secs(Next, Core#core.params),
                    V2 = V1#fveh{service_kind = Next, service_queue = Rest,
                                 service_until = SimUnix + Dur},
                    put_veh(V2, Ctx);
                [] ->
                    Core1 = free_bay(Core, V1#fveh.dest_facility),
                    V2 = V1#fveh{phase = cruising,
                                 dest_facility = undefined, dest_bay = undefined,
                                 service_kind = undefined, service_until = undefined},
                    emit(V2, {release_vehicle, #{vehicle_id => V2#fveh.id}},
                         put_veh(V2, Ctx#{core => Core1}))
            end
    end.

%% Reset the metric the just-finished service addressed.
apply_service(<<"charge">>, V)   -> V#fveh{battery_pct = 100.0};
apply_service(<<"clean">>, V)    -> V#fveh{cleanliness_pct = 100.0};
apply_service(<<"maintain">>, V) -> V#fveh{km_since_maint = 0.0};
apply_service(_, V)              -> V.

%% A stranded vehicle is towed after `tow_secs'; the tow routes it to the
%% nearest free facility (phase returning, so it docks+charges normally).
maybe_tow(V, Ctx) ->
    #{sim := SimUnix, core := Core} = Ctx,
    case is_integer(V#fveh.tow_until) andalso SimUnix >= V#fveh.tow_until of
        false -> put_veh(V, Ctx);
        true  ->
            case nearest_free_facility(V, Core) of
                none -> put_veh(V, Ctx);
                #facility{id = FacId} = Fac ->
                    Route = maps:get(route, Ctx),
                    {Path, _D} = Route({V#fveh.x, V#fveh.y},
                                       {Fac#facility.x, Fac#facility.y}),
                    Core1 = take_bay(Core, FacId),
                    V1 = V#fveh{phase = returning, leg = to_facility, path = Path,
                                dest_facility = FacId, tow_until = undefined,
                                battery_pct = 5.0},  %% tow gives a limp charge
                    emit(V1, {return_vehicle,
                              #{vehicle_id => V1#fveh.id, facility_id => FacId}},
                         put_veh(V1, Ctx#{core => Core1}))
            end
    end.

deplete(V, Ctx) ->
    #{sim := SimUnix, core := Core} = Ctx,
    TowAt = SimUnix + maps:get(tow_secs, Core#core.params),
    V1 = V#fveh{phase = depleted, battery_pct = 0.0, leg = none, path = [],
                tow_until = TowAt},
    emit(V1, {deplete_battery,
              #{vehicle_id => V1#fveh.id, x => V1#fveh.x, y => V1#fveh.y}},
         put_veh(V1, Ctx)).

%%--------------------------------------------------------------------
%% Bays + facility selection

nearest_free_facility(V, #core{facilities = Facs, bays_free = Free}) ->
    Avail = [F || F <- Facs, maps:get(F#facility.id, Free, 0) > 0],
    case Avail of
        [] -> none;
        _  ->
            Pos = {V#fveh.x, V#fveh.y},
            [Best | _] = lists:sort(
                fun(A, B) ->
                    route_leg:dist(Pos, {A#facility.x, A#facility.y})
                        =< route_leg:dist(Pos, {B#facility.x, B#facility.y})
                end, Avail),
            Best
    end.

take_bay(#core{bays_free = Free} = Core, FacId) ->
    Core#core{bays_free =
        maps:update_with(FacId, fun(N) -> max(0, N - 1) end, 0, Free)}.

free_bay(#core{} = Core, undefined) -> Core;
free_bay(#core{bays_free = Free} = Core, FacId) ->
    Core#core{bays_free = maps:update_with(FacId, fun(N) -> N + 1 end, 1, Free)}.

%% The service kinds this vehicle is due for, in service order: battery is
%% safety-critical, then mechanical maintenance, then cosmetic cleaning.
service_needs(V, P) ->
    need(V#fveh.battery_pct =< maps:get(return_threshold_pct, P), <<"charge">>)
        ++ need(V#fveh.km_since_maint >= maps:get(maint_interval_km, P, infinity), <<"maintain">>)
        ++ need(V#fveh.cleanliness_pct =< maps:get(clean_threshold_pct, P, 0), <<"clean">>).

need(true, K)  -> [K];
need(false, _) -> [].

%%--------------------------------------------------------------------
%% Accessors

-spec vehicles(t()) -> [#fveh{}].
vehicles(#core{vehicles = V}) -> maps:values(V).

%% @doc A light per-vehicle snapshot for telemetry / inspection.
-spec snapshot(t()) -> [map()].
snapshot(#core{vehicles = V}) ->
    [#{vehicle_id => F#fveh.id, phase => F#fveh.phase,
       x => F#fveh.x, y => F#fveh.y,
       heading => F#fveh.heading, battery_pct => round1(F#fveh.battery_pct),
       service_kind => F#fveh.service_kind,
       cleanliness_pct => round1(F#fveh.cleanliness_pct)}
     || F <- maps:values(V)].

%%--------------------------------------------------------------------
%% Effect + state plumbing

emit(V, Effect, Ctx) ->
    add_effect(Effect, put_veh(V, Ctx)).

add_effect(Effect, Ctx) ->
    Ctx#{effects => [Effect | maps:get(effects, Ctx)]}.

put_veh(V, Ctx) ->
    Core = maps:get(core, Ctx),
    Vehicles = maps:put(V#fveh.id, V, Core#core.vehicles),
    Ctx#{core => Core#core{vehicles = Vehicles}}.

%%--------------------------------------------------------------------
%% Small helpers

facility(Id, Facs) ->
    case lists:keyfind(Id, #facility.id, Facs) of
        #facility{} = F -> F;
        false           -> hd(Facs)
    end.

tick_sim_secs(Ctx) -> maps:get(tick_sim_secs, Ctx, 1.0).

trip_id(#ride_request{id = Id}) -> <<"trip-", Id/binary>>.

fare_cents(Metres, Params) ->
    Km = Metres / 1000.0,
    maps:get(fare_base_cents, Params) + round(Km * maps:get(fare_per_km_cents, Params)).

service_secs(Kind, Params) ->
    maps:get(Kind, maps:get(service_secs, Params), 600).

bay_id(FacId, #fveh{id = VId}) ->
    iolist_to_binary([FacId, "-bay-", VId]).

x_of({X, _}) -> X.
y_of({_, Y}) -> Y.

round1(N) -> erlang:round(N * 10) / 10.

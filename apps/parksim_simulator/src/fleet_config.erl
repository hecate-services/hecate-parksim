%%% @doc Static configuration for the robotaxi fleet: the city geometry,
%%% the service facilities (depots), the four operators, the demand
%%% hotspots, and the vehicle/economics parameters.
%%%
%%% The city is an imaginary 6x6 checkerboard (see `route_leg'): intersections
%%% at integer grid coordinates 0..6 on each axis. Depots and hotspots sit on
%%% intersections. All four operators run in ONE shared grid city. Each node is
%%% one operator, selected by TENANT_ID (kept as the operator id so the store /
%%% stream / mesh-topic wiring is unchanged); only the brand name + colour
%%% differ.
%%%
%%% Coordinates are grid units (`x'/`y' in 0..?GRID_N), not geography.
-module(fleet_config).

-include_lib("parksim_simulator/include/fleet.hrl").

-export([operator/0, operators/0, facilities/0, hotspots/0, params/0,
         city_centre/0]).

%%--------------------------------------------------------------------
%% Operators — 4 fictional brands, one per TENANT_ID. Names/colours are
%% display-only; the id stays = TENANT_ID. (Brands are placeholders — easy
%% to rename.)

-spec operators() -> [#operator{}].
operators() ->
    [#operator{id = <<"leuven">>,   name = <<"Stella">>, color = <<"#3b82f6">>,
               home = <<"depot-centrum">>,  fleet_size = 12},
     #operator{id = <<"brussels">>, name = <<"Lux">>,    color = <<"#10b981">>,
               home = <<"depot-heverlee">>, fleet_size = 12},
     #operator{id = <<"ghent">>,    name = <<"Volt">>,   color = <<"#f59e0b">>,
               home = <<"depot-kessel-lo">>, fleet_size = 12},
     #operator{id = <<"antwerp">>,  name = <<"Nova">>,   color = <<"#ec4899">>,
               home = <<"depot-centrum">>,  fleet_size = 12}].

%% @doc The operator this node runs (by TENANT_ID; defaults to leuven).
-spec operator() -> #operator{}.
operator() ->
    Id = tenant(),
    case lists:keyfind(Id, #operator.id, operators()) of
        #operator{} = Op -> Op;
        false            -> hd(operators())
    end.

%%--------------------------------------------------------------------
%% Facilities — three depots on grid intersections, each with charging +
%% cleaning; the central depot also does maintenance.

-spec facilities() -> [#facility{}].
facilities() ->
    [#facility{id = <<"depot-centrum">>,   name = <<"Central Depot">>,
               x = 3, y = 3, bays = 6,
               kinds = [<<"charge">>, <<"clean">>, <<"maintain">>]},
     #facility{id = <<"depot-heverlee">>,  name = <<"Westside Depot">>,
               x = 1, y = 5, bays = 5,
               kinds = [<<"charge">>, <<"clean">>]},
     #facility{id = <<"depot-kessel-lo">>, name = <<"Eastside Depot">>,
               x = 5, y = 1, bays = 5,
               kinds = [<<"charge">>, <<"clean">>]}].

%%--------------------------------------------------------------------
%% Demand hotspots — grid intersections where rides start/end. Weight biases
%% how often a hotspot is chosen as a pickup/dropoff.

-spec hotspots() -> [{binary(), number(), number(), number()}].
hotspots() ->
    %% {name, x, y, weight}
    [{<<"Plaza">>,       3, 3, 1.0},
     {<<"North Gate">>,  3, 6, 1.2},
     {<<"South Gate">>,  3, 0, 1.0},
     {<<"East Market">>, 6, 3, 1.0},
     {<<"West Market">>, 0, 3, 1.0},
     {<<"Grand Station">>, 5, 5, 1.5},
     {<<"Harbor">>,      1, 1, 0.8},
     {<<"Greenpark">>,   5, 2, 0.7}].

%% @doc City centre intersection (for default vehicle spawn / fallback).
-spec city_centre() -> {number(), number()}.
city_centre() -> {3, 3}.

%%--------------------------------------------------------------------
%% Parameters — vehicle physics + economics. One map, env-overridable later.

-spec params() -> map().
params() ->
    #{tick_ms              => 1000,    %% wall ms per tick
      cruise_speed_mps     => 11.0,    %% ~40 km/h
      battery_drain_per_km => 0.5,     %% %/km -> ~200 km full range
      return_threshold_pct => 20,      %% return to a depot below this
      min_dispatch_pct     => 15,      %% refuse a fare below this (matches aggregate)
      service_secs         => #{<<"charge">> => 1800,   %% sim seconds
                                <<"clean">>  => 600,
                                <<"maintain">> => 1200},
      tow_secs             => 900,     %% sim seconds stranded before tow lands
      fare_base_cents      => 250,
      fare_per_km_cents    => 120,
      fare_per_min_cents   => 25,
      %% demand: ride requests/min across the fleet at peak (per operator).
      peak_requests_per_min => 6.0,
      request_ttl_secs      => 300}.   %% unassigned requests expire

%%--------------------------------------------------------------------

%% The operator id for this node (TENANT_ID; lowercased binary).
tenant() ->
    case os:getenv("TENANT_ID") of
        false -> <<"leuven">>;
        ""    -> <<"leuven">>;
        S     -> list_to_binary(string:lowercase(S))
    end.

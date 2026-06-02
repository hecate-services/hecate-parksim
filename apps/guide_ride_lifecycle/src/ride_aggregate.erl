%%% @doc Ride aggregate — the customer transaction's lifecycle.
%%%
%%% Stream: `ride-<ride_id>`. Store derived from TENANT_ID (= operator) at
%%% boot (see hecate_parksim_service).
%%%
%%% Sibling to `vehicle_aggregate': the vehicle models what the CAR does, the
%%% ride models what the CUSTOMER experiences (requested -> assigned ->
%%% started -> completed | expired). The two are related by assignment
%%% (`ride_assigned' carries the vehicle_id) but are distinct aggregates.
-module(ride_aggregate).
-behaviour(evoq_aggregate).

-include("ride_state.hrl").

-export([state_module/0, init/1, execute/2, apply/2]).
-export([stream_id/1]).

-type state() :: #ride_state{}.
-export_type([state/0]).

-spec state_module() -> module().
state_module() -> ride_state.

%% @doc The reckon-db stream id for a ride. reckon-db requires
%% `^[a-z]{1,32}-[a-f0-9]{32}$', so the human ride id can't be used directly;
%% derive a stable compliant id as `ride-<md5(ride_id)>'. The human `ride_id'
%% stays in each event payload (what the read model + telemetry key on).
-spec stream_id(binary()) -> binary().
stream_id(RideId) when is_binary(RideId) ->
    Hex = binary:encode_hex(crypto:hash(md5, RideId), lowercase),
    <<"ride-", Hex/binary>>.

-spec init(binary()) -> {ok, state()}.
init(AggregateId) ->
    {ok, ride_state:new(AggregateId)}.

-spec execute(state(), map()) -> {ok, [map()]} | {error, term()}.
execute(State, #{command_type := <<"request_ride">>} = P) ->
    route(request_ride_v1, maybe_request_ride, State, P);
execute(State, #{command_type := <<"assign_ride">>} = P) ->
    route(assign_ride_v1, maybe_assign_ride, State, P);
execute(State, #{command_type := <<"start_ride">>} = P) ->
    route(start_ride_v1, maybe_start_ride, State, P);
execute(State, #{command_type := <<"complete_ride">>} = P) ->
    route(complete_ride_v1, maybe_complete_ride, State, P);
execute(State, #{command_type := <<"expire_ride">>} = P) ->
    route(expire_ride_v1, maybe_expire_ride, State, P);
execute(_State, #{command_type := Other}) ->
    {error, {unhandled_command, Other}};
execute(_State, _Payload) ->
    {error, missing_command_type}.

route(CmdMod, HandlerMod, State, Payload) ->
    case CmdMod:from_map(Payload) of
        {ok, Cmd}      -> HandlerMod:handle(Cmd, State);
        {error, _} = E -> E
    end.

-spec apply(state(), map()) -> state().
apply(State, Event) ->
    ride_state:apply_event(State, Event).

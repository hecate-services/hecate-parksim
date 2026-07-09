%%% @doc Projection: money-bearing domain events → the operator ledger.
%%%
%%% The financial spine of the operation. Every event that moves money becomes
%%% an append-only ledger entry (credit = revenue in, debit = cost out), from
%%% which per-operator settlement is a pure aggregation. This is the same shape
%%% a REAL operation needs: the sim is only the source of the events; point real
%%% ride/charger/parking/tow feeds at the same projection and the ledger is real.
%%%
%%% Revenue is taken from the authoritative completion events ONLY
%%% (`ride_completed`, `payment_captured`) so the fare — which also appears on
%%% `passenger_dropped_off` and `fare_collected` — is counted exactly once.
-module(settlement_event_to_ledger).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

interested_in() ->
    [<<"ride_completed">>,     %% ride fare + tip     (revenue)
     <<"payment_captured">>,   %% parking fee         (revenue)
     <<"ride_cancelled">>,     %% cancellation fee    (revenue)
     <<"energy_settled">>,     %% energy cost (charging process) (cost)
     <<"battery_charged">>,    %% energy cost (legacy flat charge) (cost)
     <<"vehicle_towed">>,      %% tow cost            (cost)
     <<"refund_issued">>].     %% refund (fare reversal) (cost)

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{}),
    {ok, #{}, RM}.

project(#{event_type := EventType, data := Data}, _Metadata, State, RM) ->
    ok = project_settlements_store:apply_event(Data#{event_type => EventType}),
    {ok, State, RM};
project(#{event_type := EventType} = Event, _Metadata, State, RM) ->
    ok = project_settlements_store:apply_event(Event#{event_type => EventType}),
    {ok, State, RM};
project(_Event, _Metadata, State, RM) ->
    {skip, State, RM}.

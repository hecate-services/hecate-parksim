%%% @doc Projection: charging-process domain events → the energy read model.
%%%
%%% Folds the session lifecycle into one row per session: `charging_started'
%%% opens it (tariff stamped), `charging_completed' records energy + final SoC,
%%% `energy_settled' books the cost + off-peak flag. Per-operator energy totals
%%% and the off-peak share are then pure aggregations over the table. Same shape
%%% a real fleet needs — point real charger feeds at the same projection.
-module(charging_event_to_energy).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

interested_in() ->
    [<<"charging_started">>,
     <<"charging_completed">>,
     <<"energy_settled">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{}),
    {ok, #{}, RM}.

project(#{event_type := EventType, data := Data}, _Metadata, State, RM) ->
    ok = project_energy_store:apply_event(Data#{event_type => EventType}),
    {ok, State, RM};
project(#{event_type := EventType} = Event, _Metadata, State, RM) ->
    ok = project_energy_store:apply_event(Event#{event_type => EventType}),
    {ok, State, RM};
project(_Event, _Metadata, State, RM) ->
    {skip, State, RM}.

%%% @doc Projection: ride-lifecycle events → SQLite rides read model.
%%%
%%% One projection for every ride event type, delegating the row writes to
%%% project_rides_store. The evoq read model handed back is only evoq's
%%% checkpoint holder; the durable read model is the SQLite store.
-module(ride_event_to_read_model).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

interested_in() ->
    [<<"ride_requested">>,
     <<"ride_assigned">>,
     <<"ride_started">>,
     <<"ride_completed">>,
     <<"ride_expired">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{}),
    {ok, #{}, RM}.

%% evoq delivers #{event_type := T, data := Data}; business fields live in
%% `data`. Flatten {data + type} into the shape the store reads.
project(#{event_type := EventType, data := Data}, _Metadata, State, RM) ->
    ok = project_rides_store:apply_event(Data#{event_type => EventType}),
    {ok, State, RM};
project(#{event_type := EventType} = Event, _Metadata, State, RM) ->
    ok = project_rides_store:apply_event(Event#{event_type => EventType}),
    {ok, State, RM};
project(_Event, _Metadata, State, RM) ->
    {skip, State, RM}.

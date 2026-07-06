%%% @doc Projection: vehicle events → the fleet ASSET register.
%%%
%%% Presents each robotaxi as a real capital asset: VIN (permanent identity),
%%% plate, model, battery State-of-Health + charge cycles (the value-driving
%%% metric for an EV asset), trips served, and current status. Fed by the same
%%% events a real telematics/charger feed would produce.
-module(asset_event_to_register).
-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

interested_in() ->
    [<<"vehicle_commissioned">>,   %% asset acquired: VIN, plate, model, SoH 100
     <<"battery_charged">>,        %% SoH + charge-cycle update (asset ageing)
     <<"passenger_dropped_off">>,  %% a completed trip (utilisation)
     <<"vehicle_towed">>].         %% breakdown/rescue (asset incident)

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{}),
    {ok, #{}, RM}.

project(#{event_type := EventType, data := Data}, _Metadata, State, RM) ->
    ok = project_assets_store:apply_event(Data#{event_type => EventType}),
    {ok, State, RM};
project(#{event_type := EventType} = Event, _Metadata, State, RM) ->
    ok = project_assets_store:apply_event(Event#{event_type => EventType}),
    {ok, State, RM};
project(_Event, _Metadata, State, RM) ->
    {skip, State, RM}.

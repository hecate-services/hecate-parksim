%%% @doc Event `vehicle_undocked_v1`. Vehicle released its bay.
-module(vehicle_undocked_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_session_id/1, get_plate/1, get_lot_id/1, get_bay_id/1, get_undocked_at/1]).

-record(vehicle_undocked_v1, {
    session_id  :: binary() | undefined,
    plate       :: binary() | undefined,
    lot_id      :: binary() | undefined,
    bay_id      :: binary() | undefined,
    undocked_at :: binary() | undefined
}).

-opaque t() :: #vehicle_undocked_v1{}.
-export_type([t/0]).

event_type() -> vehicle_undocked_v1.

-spec new(map()) -> {ok, t()}.
new(#{session_id := Id} = Params) ->
    {ok, #vehicle_undocked_v1{
        session_id  = Id,
        plate       = maps:get(plate,       Params, undefined),
        lot_id      = maps:get(lot_id,      Params, undefined),
        bay_id      = maps:get(bay_id,      Params, undefined),
        undocked_at = maps:get(undocked_at, Params, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"session_id">> := Id} = Map) ->
    {ok, #vehicle_undocked_v1{
        session_id  = Id,
        plate       = maps:get(<<"plate">>,       Map, undefined),
        lot_id      = maps:get(<<"lot_id">>,      Map, undefined),
        bay_id      = maps:get(<<"bay_id">>,      Map, undefined),
        undocked_at = maps:get(<<"undocked_at">>, Map, undefined)
    }};
from_map(#{session_id := Id} = Map) ->
    {ok, #vehicle_undocked_v1{
        session_id  = Id,
        plate       = maps:get(plate,       Map, undefined),
        lot_id      = maps:get(lot_id,      Map, undefined),
        bay_id      = maps:get(bay_id,      Map, undefined),
        undocked_at = maps:get(undocked_at, Map, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#vehicle_undocked_v1{} = Ev) ->
    #{
        event_type  => <<"vehicle_undocked">>,
        session_id  => Ev#vehicle_undocked_v1.session_id,
        plate       => Ev#vehicle_undocked_v1.plate,
        lot_id      => Ev#vehicle_undocked_v1.lot_id,
        bay_id      => Ev#vehicle_undocked_v1.bay_id,
        undocked_at => Ev#vehicle_undocked_v1.undocked_at
    }.

get_session_id(#vehicle_undocked_v1{session_id = V})   -> V.
get_plate(#vehicle_undocked_v1{plate = V})             -> V.
get_lot_id(#vehicle_undocked_v1{lot_id = V})           -> V.
get_bay_id(#vehicle_undocked_v1{bay_id = V})           -> V.
get_undocked_at(#vehicle_undocked_v1{undocked_at = V}) -> V.

%%% @doc Event `parking_session_initiated_v1`. Vehicle entered the lot;
%%% session dossier born.
-module(parking_session_initiated_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_session_id/1, get_lot_id/1, get_plate/1, get_card_id/1,
         get_permit_ref/1, get_entered_at/1]).

-record(parking_session_initiated_v1, {
    session_id :: binary() | undefined,
    lot_id     :: binary() | undefined,
    plate      :: binary() | undefined,
    card_id    :: binary() | undefined,
    permit_ref :: binary() | undefined,
    entered_at :: binary() | undefined
}).

-opaque t() :: #parking_session_initiated_v1{}.
-export_type([t/0]).

event_type() -> parking_session_initiated_v1.

-spec new(map()) -> {ok, t()}.
new(#{session_id := Id} = Params) ->
    {ok, #parking_session_initiated_v1{
        session_id = Id,
        lot_id     = maps:get(lot_id,     Params, undefined),
        plate      = maps:get(plate,      Params, undefined),
        card_id    = maps:get(card_id,    Params, undefined),
        permit_ref = maps:get(permit_ref, Params, undefined),
        entered_at = maps:get(entered_at, Params, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"session_id">> := Id} = Map) ->
    {ok, #parking_session_initiated_v1{
        session_id = Id,
        lot_id     = maps:get(<<"lot_id">>,     Map, undefined),
        plate      = maps:get(<<"plate">>,      Map, undefined),
        card_id    = maps:get(<<"card_id">>,    Map, undefined),
        permit_ref = maps:get(<<"permit_ref">>, Map, undefined),
        entered_at = maps:get(<<"entered_at">>, Map, undefined)
    }};
from_map(#{session_id := Id} = Map) ->
    {ok, #parking_session_initiated_v1{
        session_id = Id,
        lot_id     = maps:get(lot_id,     Map, undefined),
        plate      = maps:get(plate,      Map, undefined),
        card_id    = maps:get(card_id,    Map, undefined),
        permit_ref = maps:get(permit_ref, Map, undefined),
        entered_at = maps:get(entered_at, Map, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#parking_session_initiated_v1{} = Ev) ->
    #{
        event_type => <<"parking_session_initiated">>,
        session_id => Ev#parking_session_initiated_v1.session_id,
        lot_id     => Ev#parking_session_initiated_v1.lot_id,
        plate      => Ev#parking_session_initiated_v1.plate,
        card_id    => Ev#parking_session_initiated_v1.card_id,
        permit_ref => Ev#parking_session_initiated_v1.permit_ref,
        entered_at => Ev#parking_session_initiated_v1.entered_at
    }.

get_session_id(#parking_session_initiated_v1{session_id = V}) -> V.
get_lot_id(#parking_session_initiated_v1{lot_id = V})         -> V.
get_plate(#parking_session_initiated_v1{plate = V})           -> V.
get_card_id(#parking_session_initiated_v1{card_id = V})       -> V.
get_permit_ref(#parking_session_initiated_v1{permit_ref = V}) -> V.
get_entered_at(#parking_session_initiated_v1{entered_at = V}) -> V.

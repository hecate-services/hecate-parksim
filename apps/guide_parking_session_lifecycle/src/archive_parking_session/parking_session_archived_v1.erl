%%% @doc Event `parking_session_archived_v1`. Vehicle exited, books
%%% closed. `fee_cents` is the amount captured at payment time (echoed
%%% from state — DDD's "event payload is a subset of the dossier").
-module(parking_session_archived_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_session_id/1, get_fee_cents/1, get_plate/1, get_lot_id/1,
         get_duration_s/1, get_archived_at/1, get_reason/1]).

-record(parking_session_archived_v1, {
    session_id  :: binary() | undefined,
    fee_cents   :: non_neg_integer() | undefined,
    plate       :: binary() | undefined,
    lot_id      :: binary() | undefined,
    duration_s  :: non_neg_integer() | undefined,
    archived_at :: binary() | undefined,
    reason      :: binary() | undefined
}).

-opaque t() :: #parking_session_archived_v1{}.
-export_type([t/0]).

event_type() -> parking_session_archived_v1.

-spec new(map()) -> {ok, t()}.
new(#{session_id := Id} = Params) ->
    {ok, #parking_session_archived_v1{
        session_id  = Id,
        fee_cents   = maps:get(fee_cents,   Params, undefined),
        plate       = maps:get(plate,       Params, undefined),
        lot_id      = maps:get(lot_id,      Params, undefined),
        duration_s  = maps:get(duration_s,  Params, undefined),
        archived_at = maps:get(archived_at, Params, undefined),
        reason      = maps:get(reason,      Params, undefined)
    }}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"session_id">> := Id} = Map) ->
    {ok, #parking_session_archived_v1{
        session_id  = Id,
        fee_cents   = maps:get(<<"fee_cents">>,   Map, undefined),
        plate       = maps:get(<<"plate">>,       Map, undefined),
        lot_id      = maps:get(<<"lot_id">>,      Map, undefined),
        duration_s  = maps:get(<<"duration_s">>,  Map, undefined),
        archived_at = maps:get(<<"archived_at">>, Map, undefined),
        reason      = maps:get(<<"reason">>,      Map, undefined)
    }};
from_map(#{session_id := Id} = Map) ->
    {ok, #parking_session_archived_v1{
        session_id  = Id,
        fee_cents   = maps:get(fee_cents,   Map, undefined),
        plate       = maps:get(plate,       Map, undefined),
        lot_id      = maps:get(lot_id,      Map, undefined),
        duration_s  = maps:get(duration_s,  Map, undefined),
        archived_at = maps:get(archived_at, Map, undefined),
        reason      = maps:get(reason,      Map, undefined)
    }}.

-spec to_map(t()) -> map().
to_map(#parking_session_archived_v1{} = Ev) ->
    #{
        event_type  => <<"parking_session_archived">>,
        session_id  => Ev#parking_session_archived_v1.session_id,
        fee_cents   => Ev#parking_session_archived_v1.fee_cents,
        plate       => Ev#parking_session_archived_v1.plate,
        lot_id      => Ev#parking_session_archived_v1.lot_id,
        duration_s  => Ev#parking_session_archived_v1.duration_s,
        archived_at => Ev#parking_session_archived_v1.archived_at,
        reason      => Ev#parking_session_archived_v1.reason
    }.

get_session_id(#parking_session_archived_v1{session_id = V})   -> V.
get_fee_cents(#parking_session_archived_v1{fee_cents = V})     -> V.
get_plate(#parking_session_archived_v1{plate = V})             -> V.
get_lot_id(#parking_session_archived_v1{lot_id = V})           -> V.
get_duration_s(#parking_session_archived_v1{duration_s = V})   -> V.
get_archived_at(#parking_session_archived_v1{archived_at = V}) -> V.
get_reason(#parking_session_archived_v1{reason = V})           -> V.

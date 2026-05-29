%%% @doc Command `initiate_parking_session_v1`. Birth slip — the
%%% vehicle entered the lot.
-module(initiate_parking_session_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_session_id/1, get_lot_id/1, get_plate/1, get_card_id/1,
         get_permit_ref/1, get_entered_at/1]).

-record(initiate_parking_session_v1, {
    session_id :: binary() | undefined,
    lot_id     :: binary() | undefined,
    plate      :: binary() | undefined,
    card_id    :: binary() | undefined,
    permit_ref :: binary() | undefined,
    entered_at :: binary() | undefined
}).

-opaque t() :: #initiate_parking_session_v1{}.
-export_type([t/0]).

command_type() -> initiate_parking_session_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{session_id := Id} = Params) ->
    {ok, #initiate_parking_session_v1{
        session_id = Id,
        lot_id     = maps:get(lot_id,     Params, undefined),
        plate      = maps:get(plate,      Params, undefined),
        card_id    = maps:get(card_id,    Params, undefined),
        permit_ref = maps:get(permit_ref, Params, undefined),
        entered_at = maps:get(entered_at, Params, undefined)
    }};
new(_) ->
    {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"session_id">> := Id} = Map) ->
    {ok, #initiate_parking_session_v1{
        session_id = Id,
        lot_id     = maps:get(<<"lot_id">>,     Map, undefined),
        plate      = maps:get(<<"plate">>,      Map, undefined),
        card_id    = maps:get(<<"card_id">>,    Map, undefined),
        permit_ref = maps:get(<<"permit_ref">>, Map, undefined),
        entered_at = maps:get(<<"entered_at">>, Map, undefined)
    }};
from_map(#{session_id := Id} = Map) ->
    {ok, #initiate_parking_session_v1{
        session_id = Id,
        lot_id     = maps:get(lot_id,     Map, undefined),
        plate      = maps:get(plate,      Map, undefined),
        card_id    = maps:get(card_id,    Map, undefined),
        permit_ref = maps:get(permit_ref, Map, undefined),
        entered_at = maps:get(entered_at, Map, undefined)
    }};
from_map(_) ->
    {error, missing_aggregate_id}.

-spec validate(t()) -> ok | {error, term()}.
validate(#initiate_parking_session_v1{session_id = undefined}) -> {error, missing_aggregate_id};
validate(#initiate_parking_session_v1{lot_id     = undefined}) -> {error, missing_lot_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#initiate_parking_session_v1{} = Cmd) ->
    #{
        command_type => <<"initiate_parking_session">>,
        session_id   => Cmd#initiate_parking_session_v1.session_id,
        lot_id       => Cmd#initiate_parking_session_v1.lot_id,
        plate        => Cmd#initiate_parking_session_v1.plate,
        card_id      => Cmd#initiate_parking_session_v1.card_id,
        permit_ref   => Cmd#initiate_parking_session_v1.permit_ref,
        entered_at   => Cmd#initiate_parking_session_v1.entered_at
    }.

-spec stream_id(t()) -> binary().
stream_id(#initiate_parking_session_v1{session_id = Id}) ->
    <<"parking-session-", Id/binary>>.

get_session_id(#initiate_parking_session_v1{session_id = V}) -> V.
get_lot_id(#initiate_parking_session_v1{lot_id = V})         -> V.
get_plate(#initiate_parking_session_v1{plate = V})           -> V.
get_card_id(#initiate_parking_session_v1{card_id = V})       -> V.
get_permit_ref(#initiate_parking_session_v1{permit_ref = V}) -> V.
get_entered_at(#initiate_parking_session_v1{entered_at = V}) -> V.

%%% @doc Command `tow_vehicle_v1`. Rescue a stranded (battery-depleted)
%%% vehicle: a tow truck relocates it to a facility. `tow_cents` is the
%%% operator's cost for the rescue.
-module(tow_vehicle_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_vehicle_id/1, get_company_id/1, get_from_x/1, get_from_y/1,
         get_destination_facility_id/1, get_tow_distance_m/1, get_tow_cents/1,
         get_towed_at/1]).

-record(tow_vehicle_v1, {
    vehicle_id              :: binary() | undefined,
    company_id              :: binary() | undefined,
    from_x                  :: number() | undefined,
    from_y                  :: number() | undefined,
    destination_facility_id :: binary() | undefined,
    tow_distance_m          :: number() | undefined,
    tow_cents               :: non_neg_integer() | undefined,
    towed_at                :: binary() | undefined
}).

-opaque t() :: #tow_vehicle_v1{}.
-export_type([t/0]).

command_type() -> tow_vehicle_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{vehicle_id := Id} = P) ->
    {ok, from(Id, P)};
new(_) -> {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"vehicle_id">> := Id} = M) -> {ok, from_bin(Id, M)};
from_map(#{vehicle_id := Id} = M)       -> {ok, from(Id, M)};
from_map(_) -> {error, missing_aggregate_id}.

from(Id, M) ->
    #tow_vehicle_v1{
        vehicle_id = Id,
        company_id = maps:get(company_id, M, undefined),
        from_x = maps:get(from_x, M, undefined),
        from_y = maps:get(from_y, M, undefined),
        destination_facility_id = maps:get(destination_facility_id, M, undefined),
        tow_distance_m = maps:get(tow_distance_m, M, undefined),
        tow_cents = maps:get(tow_cents, M, undefined),
        towed_at = maps:get(towed_at, M, undefined)}.

from_bin(Id, M) ->
    #tow_vehicle_v1{
        vehicle_id = Id,
        company_id = maps:get(<<"company_id">>, M, undefined),
        from_x = maps:get(<<"from_x">>, M, undefined),
        from_y = maps:get(<<"from_y">>, M, undefined),
        destination_facility_id = maps:get(<<"destination_facility_id">>, M, undefined),
        tow_distance_m = maps:get(<<"tow_distance_m">>, M, undefined),
        tow_cents = maps:get(<<"tow_cents">>, M, undefined),
        towed_at = maps:get(<<"towed_at">>, M, undefined)}.

-spec validate(t()) -> ok | {error, term()}.
validate(#tow_vehicle_v1{vehicle_id = undefined}) -> {error, missing_aggregate_id};
validate(#tow_vehicle_v1{}) -> ok.

-spec to_map(t()) -> map().
to_map(#tow_vehicle_v1{} = C) ->
    #{command_type            => <<"tow_vehicle">>,
      vehicle_id              => C#tow_vehicle_v1.vehicle_id,
      company_id              => C#tow_vehicle_v1.company_id,
      from_x                  => C#tow_vehicle_v1.from_x,
      from_y                  => C#tow_vehicle_v1.from_y,
      destination_facility_id => C#tow_vehicle_v1.destination_facility_id,
      tow_distance_m          => C#tow_vehicle_v1.tow_distance_m,
      tow_cents               => C#tow_vehicle_v1.tow_cents,
      towed_at                => C#tow_vehicle_v1.towed_at}.

-spec stream_id(t()) -> binary().
stream_id(#tow_vehicle_v1{vehicle_id = Id}) -> <<"vehicle-", Id/binary>>.

get_vehicle_id(#tow_vehicle_v1{vehicle_id = V}) -> V.
get_company_id(#tow_vehicle_v1{company_id = V}) -> V.
get_from_x(#tow_vehicle_v1{from_x = V}) -> V.
get_from_y(#tow_vehicle_v1{from_y = V}) -> V.
get_destination_facility_id(#tow_vehicle_v1{destination_facility_id = V}) -> V.
get_tow_distance_m(#tow_vehicle_v1{tow_distance_m = V}) -> V.
get_tow_cents(#tow_vehicle_v1{tow_cents = V}) -> V.
get_towed_at(#tow_vehicle_v1{towed_at = V}) -> V.

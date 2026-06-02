%%% @doc Command `request_ride_v1`. Birth slip — a rider requests a trip
%%% (pickup, dropoff, party size, fare estimate). The ride dossier is born.
-module(request_ride_v1).
-behaviour(evoq_command).

-export([command_type/0]).
-export([new/1, from_map/1, validate/1, to_map/1]).
-export([stream_id/1]).
-export([get_ride_id/1, get_company_id/1, get_pickup_x/1, get_pickup_y/1,
         get_dropoff_x/1, get_dropoff_y/1, get_party_size/1,
         get_fare_estimate_cents/1, get_requested_at/1]).

-record(request_ride_v1, {
    ride_id             :: binary() | undefined,
    company_id          :: binary() | undefined,
    pickup_x            :: number() | undefined,
    pickup_y            :: number() | undefined,
    dropoff_x           :: number() | undefined,
    dropoff_y           :: number() | undefined,
    party_size          :: pos_integer() | undefined,
    fare_estimate_cents :: non_neg_integer() | undefined,
    requested_at        :: binary() | undefined
}).

-opaque t() :: #request_ride_v1{}.
-export_type([t/0]).

command_type() -> request_ride_v1.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{ride_id := Id} = P) ->
    {ok, from(fun(K, D) -> maps:get(K, P, D) end, Id)};
new(_) ->
    {error, missing_aggregate_id}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{<<"ride_id">> := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(atom_to_binary(K, utf8), M, D) end, Id)};
from_map(#{ride_id := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(K, M, D) end, Id)};
from_map(_) ->
    {error, missing_aggregate_id}.

from(G, Id) ->
    #request_ride_v1{
        ride_id             = Id,
        company_id          = G(company_id, undefined),
        pickup_x            = G(pickup_x, undefined),
        pickup_y            = G(pickup_y, undefined),
        dropoff_x           = G(dropoff_x, undefined),
        dropoff_y           = G(dropoff_y, undefined),
        party_size          = G(party_size, 1),
        fare_estimate_cents = G(fare_estimate_cents, 0),
        requested_at        = G(requested_at, undefined)
    }.

-spec validate(t()) -> ok | {error, term()}.
validate(#request_ride_v1{ride_id = undefined})    -> {error, missing_aggregate_id};
validate(#request_ride_v1{company_id = undefined}) -> {error, missing_company_id};
validate(_) -> ok.

-spec to_map(t()) -> map().
to_map(#request_ride_v1{} = C) ->
    #{command_type        => <<"request_ride">>,
      ride_id             => C#request_ride_v1.ride_id,
      company_id          => C#request_ride_v1.company_id,
      pickup_x            => C#request_ride_v1.pickup_x,
      pickup_y            => C#request_ride_v1.pickup_y,
      dropoff_x           => C#request_ride_v1.dropoff_x,
      dropoff_y           => C#request_ride_v1.dropoff_y,
      party_size          => C#request_ride_v1.party_size,
      fare_estimate_cents => C#request_ride_v1.fare_estimate_cents,
      requested_at        => C#request_ride_v1.requested_at}.

-spec stream_id(t()) -> binary().
stream_id(#request_ride_v1{ride_id = Id}) -> <<"ride-", Id/binary>>.

get_ride_id(#request_ride_v1{ride_id = V})                         -> V.
get_company_id(#request_ride_v1{company_id = V})                   -> V.
get_pickup_x(#request_ride_v1{pickup_x = V})                       -> V.
get_pickup_y(#request_ride_v1{pickup_y = V})                       -> V.
get_dropoff_x(#request_ride_v1{dropoff_x = V})                     -> V.
get_dropoff_y(#request_ride_v1{dropoff_y = V})                     -> V.
get_party_size(#request_ride_v1{party_size = V})                   -> V.
get_fare_estimate_cents(#request_ride_v1{fare_estimate_cents = V}) -> V.
get_requested_at(#request_ride_v1{requested_at = V})               -> V.

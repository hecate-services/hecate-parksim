%%% @doc Event `ride_requested_v1`. A rider requested a trip; ride dossier born.
-module(ride_requested_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_ride_id/1, get_company_id/1, get_pickup_x/1, get_pickup_y/1,
         get_dropoff_x/1, get_dropoff_y/1, get_party_size/1,
         get_fare_estimate_cents/1, get_requested_at/1]).

-record(ride_requested_v1, {
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

-opaque t() :: #ride_requested_v1{}.
-export_type([t/0]).

event_type() -> ride_requested_v1.

-spec new(map()) -> {ok, t()}.
new(#{ride_id := Id} = P) ->
    {ok, from(fun(K, D) -> maps:get(K, P, D) end, Id)}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"ride_id">> := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(atom_to_binary(K, utf8), M, D) end, Id)};
from_map(#{ride_id := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(K, M, D) end, Id)}.

from(G, Id) ->
    #ride_requested_v1{
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

-spec to_map(t()) -> map().
to_map(#ride_requested_v1{} = E) ->
    #{event_type          => <<"ride_requested">>,
      ride_id             => E#ride_requested_v1.ride_id,
      company_id          => E#ride_requested_v1.company_id,
      pickup_x            => E#ride_requested_v1.pickup_x,
      pickup_y            => E#ride_requested_v1.pickup_y,
      dropoff_x           => E#ride_requested_v1.dropoff_x,
      dropoff_y           => E#ride_requested_v1.dropoff_y,
      party_size          => E#ride_requested_v1.party_size,
      fare_estimate_cents => E#ride_requested_v1.fare_estimate_cents,
      requested_at        => E#ride_requested_v1.requested_at}.

get_ride_id(#ride_requested_v1{ride_id = V})                         -> V.
get_company_id(#ride_requested_v1{company_id = V})                   -> V.
get_pickup_x(#ride_requested_v1{pickup_x = V})                       -> V.
get_pickup_y(#ride_requested_v1{pickup_y = V})                       -> V.
get_dropoff_x(#ride_requested_v1{dropoff_x = V})                     -> V.
get_dropoff_y(#ride_requested_v1{dropoff_y = V})                     -> V.
get_party_size(#ride_requested_v1{party_size = V})                   -> V.
get_fare_estimate_cents(#ride_requested_v1{fare_estimate_cents = V}) -> V.
get_requested_at(#ride_requested_v1{requested_at = V})               -> V.

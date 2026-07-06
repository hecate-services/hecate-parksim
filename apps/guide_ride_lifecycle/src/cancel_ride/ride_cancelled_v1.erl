%%% @doc Event `ride_cancelled_v1`. The ride was cancelled after assignment.
%%% Terminal. Carries the reason and any cancellation fee (charged to the rider,
%%% so it is REVENUE despite the ride not completing).
-module(ride_cancelled_v1).
-behaviour(evoq_event).

-export([event_type/0, new/1, from_map/1, to_map/1]).
-export([get_ride_id/1, get_company_id/1, get_vehicle_id/1, get_plate/1,
         get_reason/1, get_cancellation_fee_cents/1, get_cancelled_at/1]).

-record(ride_cancelled_v1, {ride_id, company_id, vehicle_id, plate, reason,
                            cancellation_fee_cents, cancelled_at}).
-opaque t() :: #ride_cancelled_v1{}.
-export_type([t/0]).

event_type() -> ride_cancelled_v1.

new(#{ride_id := Id} = P) -> {ok, f(Id, P, fun(K, D) -> maps:get(K, P, D) end)};
new(P) -> {ok, f(maps:get(ride_id, P, undefined), P, fun(K, D) -> maps:get(K, P, D) end)}.

from_map(#{<<"ride_id">> := Id} = M) ->
    {ok, f(Id, M, fun(K, D) -> maps:get(atom_to_binary(K, utf8), M, D) end)};
from_map(#{ride_id := Id} = M) ->
    {ok, f(Id, M, fun(K, D) -> maps:get(K, M, D) end)}.

f(Id, _M, G) ->
    #ride_cancelled_v1{ride_id = Id,
        company_id = G(company_id, undefined),
        vehicle_id = G(vehicle_id, undefined),
        plate = G(plate, undefined),
        reason = G(reason, <<"rider_cancelled">>),
        cancellation_fee_cents = G(cancellation_fee_cents, 0),
        cancelled_at = G(cancelled_at, undefined)}.

to_map(#ride_cancelled_v1{} = E) ->
    #{event_type => <<"ride_cancelled">>,
      ride_id => E#ride_cancelled_v1.ride_id,
      company_id => E#ride_cancelled_v1.company_id,
      vehicle_id => E#ride_cancelled_v1.vehicle_id,
      plate => E#ride_cancelled_v1.plate,
      reason => E#ride_cancelled_v1.reason,
      cancellation_fee_cents => E#ride_cancelled_v1.cancellation_fee_cents,
      cancelled_at => E#ride_cancelled_v1.cancelled_at}.

get_ride_id(#ride_cancelled_v1{ride_id = V}) -> V.
get_company_id(#ride_cancelled_v1{company_id = V}) -> V.
get_vehicle_id(#ride_cancelled_v1{vehicle_id = V}) -> V.
get_plate(#ride_cancelled_v1{plate = V}) -> V.
get_reason(#ride_cancelled_v1{reason = V}) -> V.
get_cancellation_fee_cents(#ride_cancelled_v1{cancellation_fee_cents = V}) -> V.
get_cancelled_at(#ride_cancelled_v1{cancelled_at = V}) -> V.

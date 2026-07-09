%%% @doc Event `energy_settled_v1`. The session's energy cost (kWh x tariff) is
%%% booked. `off_peak' records whether the charge landed in a cheap window — the
%%% observable payoff of price-aware scheduling.
-module(energy_settled_v1).
-behaviour(evoq_event).

-export([event_type/0]).
-export([new/1, from_map/1, to_map/1]).
-export([get_session_id/1, get_vehicle_id/1, get_company_id/1, get_energy_kwh/1,
         get_tariff_cents_per_kwh/1, get_cost_cents/1, get_off_peak/1,
         get_settled_at/1]).

-record(energy_settled_v1, {
    session_id           :: binary() | undefined,
    vehicle_id           :: binary() | undefined,
    company_id           :: binary() | undefined,
    energy_kwh           :: number() | undefined,
    tariff_cents_per_kwh :: number() | undefined,
    cost_cents           :: non_neg_integer() | undefined,
    off_peak             :: boolean() | undefined,
    settled_at           :: binary() | undefined
}).

-opaque t() :: #energy_settled_v1{}.
-export_type([t/0]).

event_type() -> energy_settled_v1.

-spec new(map()) -> {ok, t()}.
new(#{session_id := Id} = P) ->
    {ok, from(fun(K, D) -> maps:get(K, P, D) end, Id)}.

-spec from_map(map()) -> {ok, t()}.
from_map(#{<<"session_id">> := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(atom_to_binary(K, utf8), M, D) end, Id)};
from_map(#{session_id := Id} = M) ->
    {ok, from(fun(K, D) -> maps:get(K, M, D) end, Id)}.

from(G, Id) ->
    #energy_settled_v1{
        session_id           = Id,
        vehicle_id           = G(vehicle_id, undefined),
        company_id           = G(company_id, undefined),
        energy_kwh           = G(energy_kwh, undefined),
        tariff_cents_per_kwh = G(tariff_cents_per_kwh, undefined),
        cost_cents           = G(cost_cents, undefined),
        off_peak             = G(off_peak, undefined),
        settled_at           = G(settled_at, undefined)
    }.

-spec to_map(t()) -> map().
to_map(#energy_settled_v1{} = E) ->
    #{event_type           => <<"energy_settled">>,
      session_id           => E#energy_settled_v1.session_id,
      vehicle_id           => E#energy_settled_v1.vehicle_id,
      company_id           => E#energy_settled_v1.company_id,
      energy_kwh           => E#energy_settled_v1.energy_kwh,
      tariff_cents_per_kwh => E#energy_settled_v1.tariff_cents_per_kwh,
      cost_cents           => E#energy_settled_v1.cost_cents,
      off_peak             => E#energy_settled_v1.off_peak,
      settled_at           => E#energy_settled_v1.settled_at}.

get_session_id(#energy_settled_v1{session_id = V})                     -> V.
get_vehicle_id(#energy_settled_v1{vehicle_id = V})                     -> V.
get_company_id(#energy_settled_v1{company_id = V})                     -> V.
get_energy_kwh(#energy_settled_v1{energy_kwh = V})                     -> V.
get_tariff_cents_per_kwh(#energy_settled_v1{tariff_cents_per_kwh = V}) -> V.
get_cost_cents(#energy_settled_v1{cost_cents = V})                     -> V.
get_off_peak(#energy_settled_v1{off_peak = V})                         -> V.
get_settled_at(#energy_settled_v1{settled_at = V})                     -> V.

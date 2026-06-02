%%% @doc Static configuration for the robotaxi fleet: the city geometry,
%%% the service facilities (depots), the four operators, the demand
%%% hotspots, and the vehicle/economics parameters.
%%%
%%% The city is an imaginary 6x6 checkerboard (see `route_leg'): intersections
%%% at integer grid coordinates 0..6 on each axis. Depots and hotspots sit on
%%% intersections. All four operators run in ONE shared grid city. Each node is
%%% one operator, selected by TENANT_ID (kept as the operator id so the store /
%%% stream / mesh-topic wiring is unchanged); only the brand name + colour
%%% differ.
%%%
%%% Coordinates are grid units (`x'/`y' in 0..?GRID_N), not geography.
-module(fleet_config).

-include_lib("parksim_simulator/include/fleet.hrl").

-export([operator/0, operators/0, facilities/0, hotspots/0, params/0,
         city_centre/0]).

%%--------------------------------------------------------------------
%% Operators — 4 fictional brands, one per TENANT_ID. Names/colours are
%% display-only; the id stays = TENANT_ID. (Brands are placeholders — easy
%% to rename.)

-spec operators() -> [#operator{}].
operators() ->
    [#operator{id = <<"leuven">>,   name = <<"Stella">>, color = <<"#3b82f6">>,
               home = <<"facility-leuven">>,   fleet_size = 12},
     #operator{id = <<"brussels">>, name = <<"Lux">>,    color = <<"#10b981">>,
               home = <<"facility-brussels">>, fleet_size = 12},
     #operator{id = <<"ghent">>,    name = <<"Volt">>,   color = <<"#f59e0b">>,
               home = <<"facility-ghent">>,    fleet_size = 12},
     #operator{id = <<"antwerp">>,  name = <<"Nova">>,   color = <<"#ec4899">>,
               home = <<"facility-antwerp">>,  fleet_size = 12}].

%% @doc The operator this node runs (by TENANT_ID; defaults to leuven).
-spec operator() -> #operator{}.
operator() ->
    Id = tenant(),
    case lists:keyfind(Id, #operator.id, operators()) of
        #operator{} = Op -> Op;
        false            -> hd(operators())
    end.

%%--------------------------------------------------------------------
%% Facilities — one per-operator hub, each sitting INSIDE a city block (at the
%% block centre, off the street lattice) with 4 service bays and the full
%% charge/clean/maintain kit. Blocks are the cells between intersections, so a
%% hub centre is a half-integer point: the block with lower corner (bx,by) is
%% centred at (bx+0.5, by+0.5). Layout — leuven (1,1), brussels (4,1), ghent
%% (1,4), antwerp (4,4) — a square inset in the 6x6 city. Cabs route on the
%% lattice and pull into the block to dock; the realm map mirrors these centres
%% in ClankerCabLive @facilities.

-spec facilities() -> [#facility{}].
facilities() ->
    [#facility{id = <<"facility-leuven">>,   name = <<"Stella Hub">>,
               x = 1.5, y = 1.5, bays = 4,
               kinds = [<<"charge">>, <<"clean">>, <<"maintain">>]},
     #facility{id = <<"facility-brussels">>, name = <<"Lux Hub">>,
               x = 4.5, y = 1.5, bays = 4,
               kinds = [<<"charge">>, <<"clean">>, <<"maintain">>]},
     #facility{id = <<"facility-ghent">>,    name = <<"Volt Hub">>,
               x = 1.5, y = 4.5, bays = 4,
               kinds = [<<"charge">>, <<"clean">>, <<"maintain">>]},
     #facility{id = <<"facility-antwerp">>,  name = <<"Nova Hub">>,
               x = 4.5, y = 4.5, bays = 4,
               kinds = [<<"charge">>, <<"clean">>, <<"maintain">>]}].

%%--------------------------------------------------------------------
%% Demand hotspots — grid intersections where rides start/end. Weight biases
%% how often a hotspot is chosen as a pickup/dropoff.

-spec hotspots() -> [{binary(), number(), number(), number()}].
hotspots() ->
    %% {name, x, y, weight}
    [{<<"Plaza">>,       3, 3, 1.0},
     {<<"North Gate">>,  3, 6, 1.2},
     {<<"South Gate">>,  3, 0, 1.0},
     {<<"East Market">>, 6, 3, 1.0},
     {<<"West Market">>, 0, 3, 1.0},
     {<<"Grand Station">>, 5, 5, 1.5},
     {<<"Harbor">>,      1, 1, 0.8},
     {<<"Greenpark">>,   5, 2, 0.7}].

%% @doc City centre intersection (for default vehicle spawn / fallback).
-spec city_centre() -> {number(), number()}.
city_centre() -> {3, 3}.

%%--------------------------------------------------------------------
%% Parameters — vehicle physics + economics. One map, env-overridable later.

-spec params() -> map().
params() ->
    #{tick_ms              => 1000,    %% wall ms per tick
      cruise_speed_mps     => 11.0,    %% ~40 km/h
      battery_drain_per_km => 1.0,     %% %/km -> ~100 km full range
      return_threshold_pct => 22,      %% return to charge below this %
      clean_threshold_pct  => 35,      %% return to clean below this %
      clean_per_trip       => 9,       %% cleanliness % lost per completed trip
      maint_interval_km    => 18,      %% return for maintenance every N km
      min_dispatch_pct     => 15,      %% refuse a fare below this (matches aggregate)
      service_secs         => #{<<"charge">> => 1800,   %% sim seconds
                                <<"clean">>  => 600,
                                <<"maintain">> => 1200},
      tow_secs             => 900,     %% sim seconds stranded before tow lands
      fare_base_cents      => 250,
      fare_per_km_cents    => 120,
      fare_per_min_cents   => 25,
      %% demand: ride requests/min across the fleet at peak (per operator).
      peak_requests_per_min => 6.0,
      request_ttl_secs      => 300}.   %% unassigned requests expire

%%--------------------------------------------------------------------

%% The operator id for this node (TENANT_ID; lowercased binary).
tenant() ->
    case os:getenv("TENANT_ID") of
        false -> <<"leuven">>;
        ""    -> <<"leuven">>;
        S     -> list_to_binary(string:lowercase(S))
    end.

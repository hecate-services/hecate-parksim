%%% @doc Command `dispatch_tow_truck_v1'. A tow truck is assigned to a
%%% stranded vehicle and heads out. `tow_truck_id' is the assigned truck.
-module(dispatch_tow_truck_v1).
-behaviour(evoq_command).
-export([command_type/0, new/1, from_map/1, validate/1, to_map/1, stream_id/1]).
-export([get_vehicle_id/1, get_company_id/1, get_tow_truck_id/1, get_dispatched_at/1]).
-record(dispatch_tow_truck_v1, {vehicle_id, company_id, tow_truck_id, dispatched_at}).
-opaque t() :: #dispatch_tow_truck_v1{}.
-export_type([t/0]).
command_type() -> dispatch_tow_truck_v1.
new(#{vehicle_id := Id} = P) -> {ok, f(Id, P)};
new(_) -> {error, missing_aggregate_id}.
from_map(#{<<"vehicle_id">> := Id} = M) -> {ok, fb(Id, M)};
from_map(#{vehicle_id := Id} = M) -> {ok, f(Id, M)};
from_map(_) -> {error, missing_aggregate_id}.
f(Id, M) -> #dispatch_tow_truck_v1{vehicle_id=Id, company_id=maps:get(company_id,M,undefined), tow_truck_id=maps:get(tow_truck_id,M,undefined), dispatched_at=maps:get(dispatched_at,M,undefined)}.
fb(Id, M) -> #dispatch_tow_truck_v1{vehicle_id=Id, company_id=maps:get(<<"company_id">>,M,undefined), tow_truck_id=maps:get(<<"tow_truck_id">>,M,undefined), dispatched_at=maps:get(<<"dispatched_at">>,M,undefined)}.
validate(#dispatch_tow_truck_v1{vehicle_id=undefined}) -> {error, missing_aggregate_id};
validate(#dispatch_tow_truck_v1{}) -> ok.
to_map(#dispatch_tow_truck_v1{}=C) -> #{command_type=><<"dispatch_tow_truck">>, vehicle_id=>C#dispatch_tow_truck_v1.vehicle_id, company_id=>C#dispatch_tow_truck_v1.company_id, tow_truck_id=>C#dispatch_tow_truck_v1.tow_truck_id, dispatched_at=>C#dispatch_tow_truck_v1.dispatched_at}.
stream_id(#dispatch_tow_truck_v1{vehicle_id=Id}) -> <<"vehicle-", Id/binary>>.
get_vehicle_id(#dispatch_tow_truck_v1{vehicle_id=V}) -> V.
get_company_id(#dispatch_tow_truck_v1{company_id=V}) -> V.
get_tow_truck_id(#dispatch_tow_truck_v1{tow_truck_id=V}) -> V.
get_dispatched_at(#dispatch_tow_truck_v1{dispatched_at=V}) -> V.

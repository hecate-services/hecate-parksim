%%% @doc Command `request_tow_v1`. A stranded (depleted) vehicle calls for a
%%% tow. First step of the rescue process (request -> dispatch -> towed).
-module(request_tow_v1).
-behaviour(evoq_command).
-export([command_type/0, new/1, from_map/1, validate/1, to_map/1, stream_id/1]).
-export([get_vehicle_id/1, get_company_id/1, get_x/1, get_y/1, get_requested_at/1]).
-record(request_tow_v1, {vehicle_id, company_id, x, y, requested_at}).
-opaque t() :: #request_tow_v1{}.
-export_type([t/0]).
command_type() -> request_tow_v1.
new(#{vehicle_id := Id} = P) -> {ok, f(Id, P)};
new(_) -> {error, missing_aggregate_id}.
from_map(#{<<"vehicle_id">> := Id} = M) -> {ok, fb(Id, M)};
from_map(#{vehicle_id := Id} = M) -> {ok, f(Id, M)};
from_map(_) -> {error, missing_aggregate_id}.
f(Id, M) -> #request_tow_v1{vehicle_id=Id, company_id=maps:get(company_id,M,undefined), x=maps:get(x,M,undefined), y=maps:get(y,M,undefined), requested_at=maps:get(requested_at,M,undefined)}.
fb(Id, M) -> #request_tow_v1{vehicle_id=Id, company_id=maps:get(<<"company_id">>,M,undefined), x=maps:get(<<"x">>,M,undefined), y=maps:get(<<"y">>,M,undefined), requested_at=maps:get(<<"requested_at">>,M,undefined)}.
validate(#request_tow_v1{vehicle_id=undefined}) -> {error, missing_aggregate_id};
validate(#request_tow_v1{}) -> ok.
to_map(#request_tow_v1{}=C) -> #{command_type=><<"request_tow">>, vehicle_id=>C#request_tow_v1.vehicle_id, company_id=>C#request_tow_v1.company_id, x=>C#request_tow_v1.x, y=>C#request_tow_v1.y, requested_at=>C#request_tow_v1.requested_at}.
stream_id(#request_tow_v1{vehicle_id=Id}) -> <<"vehicle-", Id/binary>>.
get_vehicle_id(#request_tow_v1{vehicle_id=V}) -> V.
get_company_id(#request_tow_v1{company_id=V}) -> V.
get_x(#request_tow_v1{x=V}) -> V.
get_y(#request_tow_v1{y=V}) -> V.
get_requested_at(#request_tow_v1{requested_at=V}) -> V.

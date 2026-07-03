%%% @doc Event `tow_requested_v1`. A stranded vehicle called for a tow.
-module(tow_requested_v1).
-behaviour(evoq_event).
-export([event_type/0, new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_x/1, get_y/1, get_requested_at/1]).
-record(tow_requested_v1, {vehicle_id, company_id, x, y, requested_at}).
-opaque t() :: #tow_requested_v1{}.
-export_type([t/0]).
event_type() -> tow_requested_v1.
new(#{vehicle_id := Id} = P) -> {ok, f(Id, P)}.
from_map(#{<<"vehicle_id">> := Id} = M) -> {ok, fb(Id, M)};
from_map(#{vehicle_id := Id} = M) -> {ok, f(Id, M)}.
f(Id, M) -> #tow_requested_v1{vehicle_id=Id, company_id=maps:get(company_id,M,undefined), x=maps:get(x,M,undefined), y=maps:get(y,M,undefined), requested_at=maps:get(requested_at,M,undefined)}.
fb(Id, M) -> #tow_requested_v1{vehicle_id=Id, company_id=maps:get(<<"company_id">>,M,undefined), x=maps:get(<<"x">>,M,undefined), y=maps:get(<<"y">>,M,undefined), requested_at=maps:get(<<"requested_at">>,M,undefined)}.
to_map(#tow_requested_v1{}=E) -> #{event_type=><<"tow_requested">>, vehicle_id=>E#tow_requested_v1.vehicle_id, company_id=>E#tow_requested_v1.company_id, x=>E#tow_requested_v1.x, y=>E#tow_requested_v1.y, requested_at=>E#tow_requested_v1.requested_at}.
get_vehicle_id(#tow_requested_v1{vehicle_id=V}) -> V.
get_company_id(#tow_requested_v1{company_id=V}) -> V.
get_x(#tow_requested_v1{x=V}) -> V.
get_y(#tow_requested_v1{y=V}) -> V.
get_requested_at(#tow_requested_v1{requested_at=V}) -> V.

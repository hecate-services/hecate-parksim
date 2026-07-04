%%% @doc Event `tow_truck_dispatched_v1'. A tow truck was assigned and is en
%%% route to the stranded vehicle.
-module(tow_truck_dispatched_v1).
-behaviour(evoq_event).
-export([event_type/0, new/1, from_map/1, to_map/1]).
-export([get_vehicle_id/1, get_company_id/1, get_tow_truck_id/1, get_dispatched_at/1]).
-record(tow_truck_dispatched_v1, {vehicle_id, plate, company_id, tow_truck_id, dispatched_at}).
-opaque t() :: #tow_truck_dispatched_v1{}.
-export_type([t/0]).
event_type() -> tow_truck_dispatched_v1.
new(#{vehicle_id := Id} = P) -> {ok, f(Id, P)}.
from_map(#{<<"vehicle_id">> := Id} = M) -> {ok, fb(Id, M)};
from_map(#{vehicle_id := Id} = M) -> {ok, f(Id, M)}.
f(Id, M) -> #tow_truck_dispatched_v1{vehicle_id=Id, plate=maps:get(plate,M,undefined), company_id=maps:get(company_id,M,undefined), tow_truck_id=maps:get(tow_truck_id,M,undefined), dispatched_at=maps:get(dispatched_at,M,undefined)}.
fb(Id, M) -> #tow_truck_dispatched_v1{vehicle_id=Id, plate=maps:get(<<"plate">>,M,undefined), company_id=maps:get(<<"company_id">>,M,undefined), tow_truck_id=maps:get(<<"tow_truck_id">>,M,undefined), dispatched_at=maps:get(<<"dispatched_at">>,M,undefined)}.
to_map(#tow_truck_dispatched_v1{}=E) -> #{event_type=><<"tow_truck_dispatched">>, vehicle_id=>E#tow_truck_dispatched_v1.vehicle_id, plate=>E#tow_truck_dispatched_v1.plate, company_id=>E#tow_truck_dispatched_v1.company_id, tow_truck_id=>E#tow_truck_dispatched_v1.tow_truck_id, dispatched_at=>E#tow_truck_dispatched_v1.dispatched_at}.
get_vehicle_id(#tow_truck_dispatched_v1{vehicle_id=V}) -> V.
get_company_id(#tow_truck_dispatched_v1{company_id=V}) -> V.
get_tow_truck_id(#tow_truck_dispatched_v1{tow_truck_id=V}) -> V.
get_dispatched_at(#tow_truck_dispatched_v1{dispatched_at=V}) -> V.

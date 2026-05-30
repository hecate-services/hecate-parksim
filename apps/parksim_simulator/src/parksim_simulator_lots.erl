%%% @doc Lot catalogue for the parking simulator.
%%%
%%% A "shape" is a named topology of parking lots. The simulator picks a
%%% shape at boot (PARKSIM_SHAPE) and runs one arrivals process per lot.
%%% Lots carry a display name, capacity, and a baseline arrival rate that
%%% the arrivals process modulates by time-of-day.
%%%
%%% The `city' shape is per-tenant: each city gets its own landmark-named
%%% lots (resolved from TENANT_ID), so the federation shows distinct
%%% facilities per city rather than one shared set.
-module(parksim_simulator_lots).

-export([for_shape/1, all_shapes/0]).

-type lot() :: #{id := binary(),
                 name := binary(),
                 capacity := pos_integer(),
                 base_rate_per_min := float()}.
-export_type([lot/0]).

%% @doc Lots for a named shape. The `city' shape is resolved per tenant
%% (real landmark facilities); unknown shapes fall back to Leuven.
-spec for_shape(binary()) -> [lot()].
for_shape(<<"city">>) ->
    city_lots(tenant());
for_shape(<<"compact">>) ->
    [lot(<<"lot-central">>, <<"Central">>, 200, 2.0)];
for_shape(_Other) ->
    for_shape(<<"city">>).

all_shapes() -> [<<"city">>, <<"compact">>].

%%--------------------------------------------------------------------
%% Per-city landmark facilities. Real parking landmarks per Belgian city;
%% capacities/rates are plausible and deliberately distinct per city.

city_lots(<<"brussels">>) ->
    [lot(<<"lot-brussels-grand-place">>, <<"Grand-Place">>,     350, 4.0),
     lot(<<"lot-brussels-sablon">>,      <<"Sablon">>,          300, 3.0),
     lot(<<"lot-brussels-louise">>,      <<"Louise">>,          550, 3.5),
     lot(<<"lot-brussels-midi">>,        <<"Brussel-Zuid">>,    700, 4.5),
     lot(<<"lot-brussels-atomium">>,     <<"Atomium">>,         450, 2.5)];
city_lots(<<"ghent">>) ->
    [lot(<<"lot-ghent-korenmarkt">>,     <<"Korenmarkt">>,      300, 3.5),
     lot(<<"lot-ghent-vrijdagmarkt">>,   <<"Vrijdagmarkt">>,    350, 3.0),
     lot(<<"lot-ghent-gravensteen">>,    <<"Gravensteen">>,     250, 2.5),
     lot(<<"lot-ghent-sint-pieters">>,   <<"Gent-Sint-Pieters">>, 600, 4.0),
     lot(<<"lot-ghent-dampoort">>,       <<"Dampoort">>,        400, 3.0)];
city_lots(<<"antwerp">>) ->
    [lot(<<"lot-antwerp-groenplaats">>,  <<"Groenplaats">>,     450, 3.5),
     lot(<<"lot-antwerp-meir">>,         <<"Meir">>,            500, 4.0),
     lot(<<"lot-antwerp-centraal">>,     <<"Antwerpen-Centraal">>, 650, 4.5),
     lot(<<"lot-antwerp-het-steen">>,    <<"Het Steen">>,       250, 2.5),
     lot(<<"lot-antwerp-eilandje">>,     <<"Eilandje (MAS)">>,  400, 3.0)];
city_lots(_Leuven) ->
    [lot(<<"lot-leuven-grote-markt">>,   <<"Grote Markt">>,     250, 3.0),
     lot(<<"lot-leuven-ladeuze">>,       <<"Ladeuzeplein">>,    500, 3.5),
     lot(<<"lot-leuven-bruul">>,         <<"Bruul">>,           350, 2.5),
     lot(<<"lot-leuven-sint-jacob">>,    <<"Sint-Jacob">>,      300, 2.0),
     lot(<<"lot-leuven-station">>,       <<"Station">>,         450, 4.0)].

lot(Id, Name, Cap, Rate) ->
    #{id => Id, name => Name, capacity => Cap, base_rate_per_min => Rate}.

%% The tenant/city this instance simulates (TENANT_ID, same env the store
%% name + mesh topic use). Lowercased; defaults to leuven.
tenant() ->
    case os:getenv("TENANT_ID") of
        false -> <<"leuven">>;
        ""    -> <<"leuven">>;
        S     -> list_to_binary(string:lowercase(S))
    end.

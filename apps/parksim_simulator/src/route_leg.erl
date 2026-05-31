%%% @doc Grid-city leg router for the robotaxi fleet.
%%%
%%% The demo city is an imaginary `?GRID_N x ?GRID_N` checkerboard: a lattice
%%% of intersections at integer coordinates `0..?GRID_N` on each axis, with
%%% streets running along every lattice line. There is NO real-world map and
%%% NO external router (this replaced an OSRM sidecar): a leg is just the
%%% Manhattan staircase between two intersections, computed with pure
%%% arithmetic.
%%%
%%% Coordinate convention: points are `{X, Y}` in grid units (a cab at
%%% `{2.4, 3.0}` is 40% along the street from intersection `{2,3}` toward
%%% `{3,3}`). The fleet brain still calls these tuple slots `lat`/`lng` for
%%% now; they carry grid coordinates, not geography.
%%%
%%% Distances are returned in METRES (grid units scaled by `?UNIT_M` metres
%%% per block) so the brain's metre-based physics — battery drain per km,
%%% fare per km, cruise speed — is unchanged.
%%%
%%% Lives in parksim_simulator (shared infra) so both the fleet brain and
%%% any tooling can route.
-module(route_leg).

-export([route/2, dist/2, interpolate/3, grid_n/0, snap/1]).

-type point() :: {number(), number()}.   %% {X, Y} in grid units
-type leg() :: #{distance_m := float(),
                 duration_s := float(),
                 polyline   := [point()],
                 source     := grid}.
-export_type([point/0, leg/0]).

%% Imaginary city: ?GRID_N x ?GRID_N blocks => intersections 0..?GRID_N.
-define(GRID_N, 6).
%% Metres per city block — keeps the brain's km-based physics sensible.
-define(UNIT_M, 150.0).
%% Assumed city speed, used only to fill in a leg's duration estimate.
-define(SPEED_MPS, 7.8).

%% @doc The grid dimension (blocks per side); intersections span 0..grid_n().
-spec grid_n() -> pos_integer().
grid_n() -> ?GRID_N.

%% @doc Route From -> To across the grid as a Manhattan staircase. Returns
%% the waypoints AHEAD of the vehicle (the brain walks from its current
%% position through them) plus the leg distance in metres. Pure; never errors.
-spec route(point(), point()) -> leg().
route(From, To) ->
    Waypoints = staircase(snap(From), snap(To)),
    DistM = manhattan_m(From, To),
    #{distance_m => DistM,
      duration_s => DistM / ?SPEED_MPS,
      polyline   => Waypoints,
      source     => grid}.

%%--------------------------------------------------------------------
%% Grid routing

%% Snap an arbitrary point to its nearest intersection, clamped to the city.
-spec snap(point()) -> {integer(), integer()}.
snap({X, Y}) -> {clamp(round(X)), clamp(round(Y))}.

clamp(N) when N < 0 -> 0;
clamp(N) when N > ?GRID_N -> ?GRID_N;
clamp(N) -> N.

%% Manhattan staircase of intersections from A (exclusive) to B (inclusive),
%% one block per step, alternating axis so cabs spread across interior
%% streets instead of hugging two edges.
staircase({Ax, Ay}, {Bx, By}) -> step(Ax, Ay, Bx, By, true, []).

step(X, Y, X, Y, _Prefer, Acc) -> lists:reverse(Acc);
step(X, Y, Bx, By, PreferX, Acc) ->
    MoveX = case {X =/= Bx, Y =/= By} of
                {true, true}  -> PreferX;
                {true, false} -> true;
                {false, _}    -> false
            end,
    {NX, NY} = case MoveX of
                   true  -> {X + sign(Bx - X), Y};
                   false -> {X, Y + sign(By - Y)}
               end,
    step(NX, NY, Bx, By, not PreferX, [{NX, NY} | Acc]).

sign(D) when D > 0 -> 1;
sign(D) when D < 0 -> -1;
sign(_)            -> 0.

%%--------------------------------------------------------------------
%% Geometry helpers reused by the fleet brain (simulate_fleet_core)

%% @doc Distance in METRES between two grid points (euclidean grid distance
%% scaled by the block size). Replaces the old great-circle `haversine_m/2`.
-spec dist(point(), point()) -> float().
dist({X1, Y1}, {X2, Y2}) ->
    DX = X2 - X1,
    DY = Y2 - Y1,
    math:sqrt(DX * DX + DY * DY) * ?UNIT_M.

%% Manhattan (street-following) distance in metres — the real driven length.
manhattan_m({X1, Y1}, {X2, Y2}) ->
    (abs(X2 - X1) + abs(Y2 - Y1)) * ?UNIT_M.

%% @doc The point a fraction `F` (0..1) of the way from A to B (linear lerp).
-spec interpolate(point(), point(), float()) -> point().
interpolate({X1, Y1}, {X2, Y2}, F) ->
    {X1 + (X2 - X1) * F, Y1 + (Y2 - Y1) * F}.

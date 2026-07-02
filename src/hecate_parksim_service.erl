%%% @doc hecate-parksim — implements the hecate_om_service behaviour.
%%%
%%% A self-contained parking simulator that writes parking_session
%%% events into its own reckon-db store. Tenant identity is read from
%%% the TENANT_ID environment variable; the store name derives as
%%% `parksim_<tenant>_store` so reckon-gateway's catalogue mode sees
%%% one store per tenant across the cluster.
%%%
%%% The service exports the optional `store_id/0` + `data_dir/0`
%%% callbacks so hecate_om:boot/1 auto-starts the store and wires
%%% evoq's subscription bus.
-module(hecate_parksim_service).
-behaviour(hecate_om_service).

-include_lib("reckon_db/include/reckon_db.hrl").

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).
-export([store_id/0, data_dir/0, store_indexes/0]).
-export([tenant_id/0]).
-export([is_leader/0]).

info() ->
    #{
        name        => <<"hecate-parksim">>,
        version     => <<"0.1.0">>,
        description => <<"Multi-tenant parking simulator emitting parking_session events">>
    }.

start(_Opts) ->
    %% hecate_om 0.2.0 doesn't yet auto-wire store_id/0 callbacks; do
    %% it explicitly here. When hecate_om >= 0.3.0 lands with the
    %% hecate_om_store helper, this block goes away.
    {ok, SupPid} = hecate_parksim_sup:start_link(),
    ok = ensure_store(),
    ok = ensure_subscription(),
    {ok, SupPid}.

%% Bridge the event store to evoq projections/handlers (catch-up +
%% live $all). Started after the store is up; the PRJ app's projection
%% has already registered its event types (it boots first — see the
%% project_parking_sessions dep in hecate_parksim.app.src).
ensure_subscription() ->
    case evoq_store_subscription:start_link(store_id()) of
        {ok, _Pid}                    -> ok;
        {error, {already_started, _}} -> ok;
        {error, Reason}               -> error({store_subscription_failed, Reason})
    end.

ensure_store() ->
    Config = #store_config{
        store_id = store_id(),
        data_dir = data_dir(),
        mode     = cluster,
        indexes  = store_indexes()
    },
    case reckon_db_sup:start_store(Config) of
        {ok, _Pid}                    -> ok;
        {error, {already_started, _}} -> ok;
        {error, Reason}               -> error({store_start_failed, Reason})
    end.

stop(_State) ->
    ok.

health() ->
    ok.

capabilities() ->
    %% Pure event source. Advertises nothing on the mesh; events live
    %% in the local reckon-db store, served externally via reckon-gateway.
    [].

identity_spec() ->
    #{
        scope     => <<"hecate-parksim">>,
        actions   => [],
        resources => [],
        ttl_days  => 30
    }.

%%--------------------------------------------------------------------
%% Store wiring (consumed by hecate_om:boot/1)

%% @doc Atom store id, derived from the TENANT_ID env var. Defaults to
%% `parksim_demo_store` for unconfigured containers.
-spec store_id() -> atom().
store_id() ->
    list_to_atom("parksim_" ++ tenant_id() ++ "_store").

%% @doc Filesystem root for the store's on-disk state. reckon_db
%% namespaces by store_id under this root.
-spec data_dir() -> string().
data_dir() ->
    case os:getenv("HECATE_DATA_DIR") of
        false -> "/var/lib/hecate-parksim";
        Dir   -> Dir
    end.

%% @doc The store's declared secondary indexes. hecate_om:boot/1 reads
%% this (the optional store_indexes/0 callback) and installs them on the
%% auto-started store, so CCC payload queries work. Single source of
%% truth — ensure_store/0 references it too.
-spec store_indexes() -> [term()].
store_indexes() ->
    [tags, event_type,
     {payload, <<"plate">>},
     {payload, <<"lot_id">>},
     {payload, <<"ride_id">>},
     {payload, <<"vehicle_id">>},
     {payload, <<"company_id">>},
     {payload, <<"bay_id">>},
     {payload_hash, [<<"lot_id">>, <<"plate">>]},
     {payload_hash, [<<"facility_id">>, <<"bay_id">>]}].

%%--------------------------------------------------------------------
%% Tenant identity

%% @doc Tenant id as a string. Reads TENANT_ID from OS env; defaults to
%% "demo" if unset.
-spec tenant_id() -> string().
tenant_id() ->
    case os:getenv("TENANT_ID") of
        false -> "demo";
        ""    -> "demo";
        Id    -> Id
    end.

%%--------------------------------------------------------------------
%% Leadership (follow-the-leader)

%% @doc Is this container the Ra leader of its tenant store?
%%
%% Every replica runs the full app, but the self-driven write/emit
%% workers (arrivals, fleet, scavenge, mesh summaries) gate their tick
%% on this so exactly one node — the leader — generates writes and
%% publishes facts. On failover the new leader's already-running
%% workers simply start acting; nothing migrates. Guarded: before the
%% store's Ra cluster has a leader (early boot) this is false.
-spec is_leader() -> boolean().
is_leader() ->
    try reckon_db_store_coordinator:is_leader(store_id())
    catch _:_ -> false end.

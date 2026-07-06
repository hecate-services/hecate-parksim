%%% @doc hecate-parksim OTP application entry.
-module(hecate_parksim_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    %% Auto-tag every domain event with its business identities (plate:, vehicle:,
    %% ride:, ...) so an entity's full cross-stream history is queryable via the
    %% base `tags' index. Additive; prepended so desk-specific middleware can
    %% still run after it. See parksim_auto_tag.
    Existing = application:get_env(evoq, middleware, []),
    application:set_env(evoq, middleware,
                        lists:usort([parksim_auto_tag | Existing])),
    hecate_om:boot(hecate_parksim_service).

stop(_State) ->
    ok.

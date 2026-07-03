%%% @doc One simulated parking visit. Dispatches the session events
%%% directly via evoq_command_router to the tenant store.
%%%
%%% Physical lifecycle: enter -> dock (park in a bay) -> dwell -> then
%%% either
%%%   kiosk: pay -> undock -> exit      (pay on foot before walking back)
%%%   exit:  undock -> pay  -> exit      (pay at the exit island)
%%% Permit holders are pre-paid: undock -> exit, no payment event.
%%%
%%% Dwell is log-normal in seconds, clipped to [60, 24h]. ~0.7% of
%%% visits abandon after docking (never undock/pay/exit — a realistic
%%% orphan: a car left parked).
-module(simulate_visit).

-export([start_visit/1]).

-include_lib("parksim_simulator/include/parksim_simulator_scenario.hrl").

%% @doc Spawn one visit process. Params: #{lot, plate, credential}.
-spec start_visit(map()) -> {ok, pid()}.
start_visit(Params) ->
    {ok, proc_lib:spawn(fun() -> run(Params) end)}.

run(#{lot := Lot, plate := Plate, credential := Credential}) ->
    Rng = rand:seed_s(exsss, {erlang:phash2(self()),
                              erlang:phash2(make_ref()),
                              erlang:system_time(microsecond)}),
    LotId     = Lot#parksim_lot.id,
    SessionId = reckon_gater_stream_id:new(<<"sess">>),
    CardId    = card_id(Credential),
    PermitRef = permit_ref(Credential),
    StoreId   = hecate_parksim_service:store_id(),
    case parking_session_dcb:claim_entry(StoreId, Plate, LotId, SessionId) of
        ok ->
            %% Claimed the slot — run the full paired lifecycle (the eventual
            %% exit is the matching release for THIS entry).
            enter(SessionId, LotId, Plate, CardId, PermitRef),
            {BayId, Rng1} = pick_bay(Rng, Lot),
            dock(SessionId, BayId),
            {DwellSec, Rng2} = sample_dwell(Rng1, Lot),
            simulate_clock:sleep_simulated(DwellSec * 1000),
            case roll_abandon(Rng2) of
                {true,  _Rng3} ->
                    %% Abandoned vehicle stays parked — DCB slot remains claimed,
                    %% mirroring the real-world state (car is still there).
                    ok;
                {false, Rng3}  ->
                    settle(SessionId, DwellSec, Credential, Rng3, StoreId, Plate, LotId)
            end;
        {error, already_parked} ->
            %% Vehicle is currently in another lot — turn away silently.
            ok;
        {error, _} ->
            %% DCB contention/transient error — skip this visit entirely rather
            %% than run a half-lifecycle (an exit with no matching entry). No
            %% claim means no entry event, so we must not emit a release.
            ok
    end.

%%--------------------------------------------------------------------
%% Lifecycle dispatch

enter(SessionId, LotId, Plate, CardId, PermitRef) ->
    _ = maybe_initiate_parking_session:dispatch(#{
        session_id => SessionId,
        lot_id     => LotId,
        plate      => Plate,
        card_id    => CardId,
        permit_ref => PermitRef,
        entered_at => simulate_clock:now_iso8601()
    }),
    ok.

dock(SessionId, BayId) ->
    _ = maybe_dock_vehicle:dispatch(#{
        session_id => SessionId,
        bay_id     => BayId,
        docked_at  => simulate_clock:now_iso8601()
    }),
    ok.

undock(SessionId) ->
    _ = maybe_undock_vehicle:dispatch(#{
        session_id  => SessionId,
        undocked_at => simulate_clock:now_iso8601()
    }),
    ok.

pay(SessionId, AmountCents) ->
    _ = maybe_capture_payment:dispatch(#{
        session_id   => SessionId,
        amount_cents => AmountCents,
        paid_at      => simulate_clock:now_iso8601()
    }),
    ok.

archive(SessionId, Reason) ->
    _ = maybe_archive_parking_session:dispatch(#{
        session_id  => SessionId,
        reason      => Reason,
        archived_at => simulate_clock:now_iso8601()
    }),
    ok.

%% Ticket visits pay at the kiosk (before undocking) or at the exit
%% island (after undocking) — 50/50. Permit holders skip payment.
settle(SessionId, DwellSec, ticket, Rng, StoreId, Plate, LotId) ->
    Amount = compute_fee_cents(DwellSec),
    {PayPoint, Rng1} = roll_pay_point(Rng),
    {Pause, _Rng2}   = uniform_int_s(Rng1, 2, 90),
    settle_ticket(SessionId, Amount, Pause, PayPoint, StoreId, Plate, LotId);
settle(SessionId, _DwellSec, {permit, _Ref}, _Rng, StoreId, Plate, LotId) ->
    undock(SessionId),
    archive(SessionId, <<"permit">>),
    _ = parking_session_dcb:release_entry(StoreId, Plate, LotId, SessionId),
    ok.

settle_ticket(SessionId, Amount, Pause, kiosk, StoreId, Plate, LotId) ->
    simulate_clock:sleep_simulated(Pause * 1000),
    pay(SessionId, Amount),
    undock(SessionId),
    archive(SessionId, undefined),
    _ = parking_session_dcb:release_entry(StoreId, Plate, LotId, SessionId),
    ok;
settle_ticket(SessionId, Amount, Pause, exit, StoreId, Plate, LotId) ->
    undock(SessionId),
    simulate_clock:sleep_simulated(Pause * 1000),
    pay(SessionId, Amount),
    archive(SessionId, undefined),
    _ = parking_session_dcb:release_entry(StoreId, Plate, LotId, SessionId),
    ok.

%%--------------------------------------------------------------------
%% Fee model — flat EUR 2.50 / started hour, min EUR 0.50. Crude but
%% gives the events realistic amount_cents values for the demo.

compute_fee_cents(DwellSec) ->
    HoursStarted = max(1, (DwellSec + 3599) div 3600),
    max(50, HoursStarted * 250).

%%--------------------------------------------------------------------
%% Identity / payload helpers

card_id(ticket)      -> <<"card-", (hex(crypto:strong_rand_bytes(8)))/binary>>;
card_id({permit, _}) -> undefined.

permit_ref(ticket)        -> undefined;
permit_ref({permit, Ref}) -> Ref.

%% A session-level bay id within the lot — lot-X-bay-N, N in 1..capacity.
%% No occupancy tracking (bays can collide); see DESIGN notes.
pick_bay(Rng, #parksim_lot{id = LotId, capacity = Cap}) ->
    {N, Rng1} = uniform_int_s(Rng, 1, max(1, Cap)),
    BayId = <<LotId/binary, "-bay-", (integer_to_binary(N))/binary>>,
    {BayId, Rng1}.

%%--------------------------------------------------------------------
%% Distributions

%% LogNormal(mu, sigma) clipped to [60, 24h] seconds.
sample_dwell(Rng, #parksim_lot{dwell_mu = Mu, dwell_sigma = Sigma}) ->
    {Z, Rng1} = rand:normal_s(Rng),
    X = math:exp(Mu + Sigma * Z),
    {max(60, min(round(X), 24 * 3600)), Rng1}.

roll_abandon(Rng) ->
    {U, Rng1} = rand:uniform_s(Rng),
    {U =< 0.007, Rng1}.

roll_pay_point(Rng) ->
    {U, Rng1} = rand:uniform_s(Rng),
    case U =< 0.5 of
        true  -> {kiosk, Rng1};
        false -> {exit,  Rng1}
    end.

uniform_int_s(Rng, Lo, Hi) when Hi >= Lo ->
    {U, Rng1} = rand:uniform_s(Hi - Lo + 1, Rng),
    {Lo + U - 1, Rng1}.

hex(Bin) -> << <<(nibble(N))>> || <<N:4>> <= Bin >>.
nibble(N) when N < 10 -> $0 + N;
nibble(N)             -> $a + (N - 10).

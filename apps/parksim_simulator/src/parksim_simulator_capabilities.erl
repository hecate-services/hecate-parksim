%%% @doc Capability-name constants for every parksim mesh RPC the
%%% simulator invokes. Mirrors the binary command_type strings on
%%% the Erlang aggregates' side.
-module(parksim_simulator_capabilities).

%% entry2exit (session correlation saga — entry/payment/exit are now
%% PM-driven from lane-equipment facts; the simulator drives the
%% hardware, not these directly)
-export([enter_vehicle/0,
         mark_payment_captured/0, mark_payment_failed/0,
         record_exit/0, settle/0, force_settle/0, abandon/0,
         reprice/0, mark_overstayed/0]).

%% lot
-export([open_lot/0, close_lot/0, set_capacity/0,
         assign_zone_purpose/0, record_sensor_calibration/0,
         start_maintenance_window/0, end_maintenance_window/0,
         record_sweep/0, evacuate_lot/0, restore_lot/0]).

%% pricing
-export([draft_rate/0, publish_rate/0, amend_rate_draft/0,
         retire_rate/0, open_surge_window/0, close_surge_window/0,
         introduce_discount/0, revoke_discount/0, issue_quote/0]).

%% permits
-export([request_permit/0, approve_permit/0, deny_permit/0,
         issue_permit/0, activate_permit/0, renew_permit/0,
         suspend_permit/0, reinstate_permit/0,
         transfer_permit/0, revoke_permit/0, mark_permit_expired/0]).

%% lane equipment (physical-device-first): the simulator drives the
%% hardware stimuli; the device sagas do the rest.
-export([entry_island_detect_vehicle/0, entry_island_present_permit/0,
         exit_island_detect_vehicle/0, exit_island_read_card/0,
         exit_island_present_permit/0,
         terminal_accept_card/0, terminal_tender_payment/0]).

%% --- entry2exit ---
enter_vehicle()         -> <<"hecate-parksim-entry2exit.enter_vehicle">>.
mark_payment_captured() -> <<"hecate-parksim-entry2exit.mark_payment_captured">>.
mark_payment_failed()   -> <<"hecate-parksim-entry2exit.mark_payment_failed">>.
record_exit()           -> <<"hecate-parksim-entry2exit.record_exit">>.
settle()                -> <<"hecate-parksim-entry2exit.settle_parking_session">>.
force_settle()          -> <<"hecate-parksim-entry2exit.force_settle_parking_session">>.
abandon()               -> <<"hecate-parksim-entry2exit.abandon_parking_session">>.
reprice()               -> <<"hecate-parksim-entry2exit.reprice_parking_session">>.
mark_overstayed()       -> <<"hecate-parksim-entry2exit.mark_overstayed">>.

%% --- lot ---
open_lot()                  -> <<"hecate-parksim-lot.open_parking_lot">>.
close_lot()                 -> <<"hecate-parksim-lot.close_parking_lot">>.
set_capacity()              -> <<"hecate-parksim-lot.set_capacity">>.
assign_zone_purpose()       -> <<"hecate-parksim-lot.assign_zone_purpose">>.
record_sensor_calibration() -> <<"hecate-parksim-lot.record_sensor_calibration">>.
start_maintenance_window()  -> <<"hecate-parksim-lot.start_maintenance_window">>.
end_maintenance_window()    -> <<"hecate-parksim-lot.end_maintenance_window">>.
record_sweep()              -> <<"hecate-parksim-lot.record_sweep">>.
evacuate_lot()              -> <<"hecate-parksim-lot.evacuate_parking_lot">>.
restore_lot()               -> <<"hecate-parksim-lot.restore_parking_lot">>.

%% --- pricing rates ---
draft_rate()         -> <<"hecate-parksim-pricing.draft_parking_rate">>.
publish_rate()       -> <<"hecate-parksim-pricing.publish_parking_rate">>.
amend_rate_draft()   -> <<"hecate-parksim-pricing.amend_parking_rate_draft">>.
retire_rate()        -> <<"hecate-parksim-pricing.retire_parking_rate">>.
open_surge_window()  -> <<"hecate-parksim-pricing.open_surge_window">>.
close_surge_window() -> <<"hecate-parksim-pricing.close_surge_window">>.
introduce_discount() -> <<"hecate-parksim-pricing.introduce_discount">>.
revoke_discount()    -> <<"hecate-parksim-pricing.revoke_discount">>.
issue_quote()        -> <<"hecate-parksim-pricing.issue_quote">>.

%% --- pricing permits ---
request_permit()      -> <<"hecate-parksim-pricing.request_parking_permit">>.
approve_permit()      -> <<"hecate-parksim-pricing.approve_parking_permit">>.
deny_permit()         -> <<"hecate-parksim-pricing.deny_parking_permit">>.
issue_permit()        -> <<"hecate-parksim-pricing.issue_parking_permit">>.
activate_permit()     -> <<"hecate-parksim-pricing.activate_parking_permit">>.
renew_permit()        -> <<"hecate-parksim-pricing.renew_parking_permit">>.
suspend_permit()      -> <<"hecate-parksim-pricing.suspend_parking_permit">>.
reinstate_permit()    -> <<"hecate-parksim-pricing.reinstate_parking_permit">>.
transfer_permit()     -> <<"hecate-parksim-pricing.transfer_parking_permit">>.
revoke_permit()       -> <<"hecate-parksim-pricing.revoke_parking_permit">>.
mark_permit_expired() -> <<"hecate-parksim-pricing.mark_parking_permit_expired">>.

%% --- entry island ---
entry_island_detect_vehicle() -> <<"hecate-parksim-entry-island.detect_vehicle">>.
entry_island_present_permit() -> <<"hecate-parksim-entry-island.present_parking_permit">>.

%% --- exit island ---
exit_island_detect_vehicle()  -> <<"hecate-parksim-exit-island.detect_vehicle">>.
exit_island_read_card()       -> <<"hecate-parksim-exit-island.read_parking_card">>.
exit_island_present_permit()  -> <<"hecate-parksim-exit-island.present_parking_permit">>.

%% --- payment terminal ---
terminal_accept_card()    -> <<"hecate-parksim-payment-terminal.accept_parking_card">>.
terminal_tender_payment() -> <<"hecate-parksim-payment-terminal.tender_payment">>.

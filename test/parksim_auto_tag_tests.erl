%%% @doc Tests for the auto-tag dispatch middleware.
-module(parksim_auto_tag_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("evoq/include/evoq.hrl").

-define(M, parksim_auto_tag).

%% A vehicle command payload -> plate/vehicle/company tags.
derive_vehicle_tags_test() ->
    Tags = ?M:derive_tags(#{vehicle_id => <<"leuven-taxi-4">>,
                            plate => <<"1-ZZZ-829">>,
                            company_id => <<"leuven">>,
                            battery_pct => 100}),
    ?assertEqual([<<"company:leuven">>, <<"plate:1-ZZZ-829">>,
                  <<"vehicle:leuven-taxi-4">>], lists:sort(Tags)).

%% A ride command payload -> ride/vehicle/plate tags.
derive_ride_tags_test() ->
    Tags = ?M:derive_tags(#{ride_id => <<"req-1">>, vehicle_id => <<"v-1">>,
                            plate => <<"1-AAA-001">>}),
    ?assertEqual([<<"plate:1-AAA-001">>, <<"ride:req-1">>, <<"vehicle:v-1">>],
                 lists:sort(Tags)).

%% Non-string values (numbers, maps) are ignored; only identity strings tag.
ignores_non_string_fields_test() ->
    ?assertEqual([<<"vehicle:v-9">>],
                 ?M:derive_tags(#{vehicle_id => <<"v-9">>, battery_pct => 42,
                                  x => 1.5, meta => #{a => 1}})).

%% Payload with no taggable identity -> no tags.
no_identity_no_tags_test() ->
    ?assertEqual([], ?M:derive_tags(#{some_flag => true, count => 3})).

%% before_dispatch injects the tags into command metadata.
before_dispatch_adds_tags_test() ->
    Cmd = #evoq_command{payload = #{vehicle_id => <<"v-1">>,
                                    plate => <<"1-BBB-002">>},
                        metadata = #{timestamp => 123}},
    #evoq_pipeline{command = Out} = ?M:before_dispatch(#evoq_pipeline{command = Cmd}),
    #{tags := Tags, timestamp := 123} = Out#evoq_command.metadata,
    ?assertEqual([<<"plate:1-BBB-002">>, <<"vehicle:v-1">>], lists:sort(Tags)).

%% Existing metadata tags are preserved, not clobbered.
before_dispatch_preserves_existing_tags_test() ->
    Cmd = #evoq_command{payload = #{vehicle_id => <<"v-1">>},
                        metadata = #{tags => [<<"custom:x">>]}},
    #evoq_pipeline{command = Out} = ?M:before_dispatch(#evoq_pipeline{command = Cmd}),
    #{tags := Tags} = Out#evoq_command.metadata,
    ?assert(lists:member(<<"custom:x">>, Tags)),
    ?assert(lists:member(<<"vehicle:v-1">>, Tags)).

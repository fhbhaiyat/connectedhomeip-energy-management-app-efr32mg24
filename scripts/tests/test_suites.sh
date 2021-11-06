#!/usr/bin/env bash

#
# Copyright (c) 2020 Project CHIP Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -e

declare -i iterations=2
declare -i delay=0
declare -i node_id=0x12344321
declare -i background_pid=0
declare test_case_wrapper=()

usage() {
    echo "test_suites.sh [-a APPLICATION] [-i ITERATIONS] [-h] [-s CASE_NAME] [-w COMMAND] [-d DELAY]"
    echo "  -a APPLICATION: runs chip-tool against 'chip-<APPLICATION>-app' (default: all-clusters)"
    echo "  -d DELAY: milliseconds to wait before running an individual test step (default: $delay)"
    echo "  -h: this help message"
    echo "  -i ITERATIONS: number of iterations to run (default: $iterations)"
    echo "  -s CASE_NAME: runs single test case name (e.g. Test_TC_OO_2_2"
    echo "                for Test_TC_OO_2_2.yaml) (by default, all are run)"
    echo "  -w COMMAND: prefix all instantiations with a command (e.g. valgrind) (default: '')"
    echo ""
    exit 0
}

# read shell arguments
while getopts a:d:i:hs:w: flag; do
    case "$flag" in
        a) application=$OPTARG ;;
        d) delay=$OPTARG ;;
        h) usage ;;
        i) iterations=$OPTARG ;;
        s) single_case=$OPTARG ;;
        w) test_case_wrapper=("$OPTARG") ;;
    esac
done

if [[ $application == "tv" ]]; then
    declare test_filenames="${single_case-TV_*}.yaml"
    cp examples/tv-app/linux/include/endpoint-configuration/chip_tv_config.ini /tmp/chip_tv_config.ini
# in case there's no application argument
# always default to all-cluters app
else
    application="all-clusters"
    declare test_filenames="${single_case-Test*}.yaml"
fi
declare -a test_array="($(find src/app/tests/suites -type f -name "$test_filenames" -exec basename {} .yaml \;))"

if [[ $iterations == 0 ]]; then
    echo "Invalid iteration count: '$1'"
    exit 1
fi

echo "Running tests for application: $application, with iterations set to: $iterations and delay set to $delay"

cleanup() {
    if [[ $background_pid != 0 ]]; then
        # In case we died on a failure before we cleaned up our background task.
        kill -9 "$background_pid" || true
    fi
}
trap cleanup EXIT

echo "Found tests:"
for i in "${test_array[@]}"; do
    echo "   $i"
done
echo ""
echo ""

ulimit -c unlimited || true

rm -rf /tmp/test_suites_app_logs
mkdir -p /tmp/test_suites_app_logs

declare -a iter_array="($(seq "$iterations"))"
for j in "${iter_array[@]}"; do
    echo " ===== Iteration $j starting"
    for i in "${test_array[@]}"; do
        echo "  ===== Running test: $i"
        echo "          * Starting cluster server"
        rm -rf /tmp/chip_tool_config.ini
        # This part is a little complicated.  We want to
        # 1) Start chip-app in the background
        # 2) Pipe its output through tee so we can wait until it's ready for a
        #    PASE handshake.
        # 3) Save its pid off so we can kill it.
        #
        # The subshell with echoing of $! to a file descriptor and
        # then reading things out of there accomplishes item 3;
        # otherwise $! would be the last-started command which would
        # be the tee.  This part comes from https://stackoverflow.com/a/3786955
        # and better ideas are welcome.
        #
        # The stdbuf -o0 is to make sure our output is flushed through
        # tee expeditiously; otherwise it will buffer things up and we
        # will never see the string we want.

        application_log_file=/tmp/test_suites_app_logs/"$application-$i-$j"-log
        pairing_log_file=/tmp/test_suites_app_logs/pairing-"$application-$i-$j"-log
        chip_tool_log_file=/tmp/test_suites_app_logs/chip-tool-"$application-$i-$j"-log
        touch "$application_log_file"
        touch "$pairing_log_file"
        touch "$chip_tool_log_file"
        rm -rf /tmp/pid
        (
            stdbuf -o0 "${test_case_wrapper[@]}" out/debug/standalone/chip-"$application"-app &
            echo $! >&3
        ) 3>/tmp/pid | tee "$application_log_file" &
        while ! grep -q "Server Listening" "$application_log_file"; do
            :
        done
        # Now read $background_pid from /tmp/pid; presumably it's
        # landed there by now.  If we try to read it immediately after
        # kicking off the subshell, sometimes we try to do it before
        # the data is there yet.
        background_pid="$(</tmp/pid)"
        echo "          * Pairing to device"
        "${test_case_wrapper[@]}" out/debug/standalone/chip-tool pairing qrcode "$node_id" MT:D8XA0CQM00KA0648G00 | tee "$pairing_log_file"
        echo "          * Starting test run: $i"
        "${test_case_wrapper[@]}" out/debug/standalone/chip-tool tests "$i" "$node_id" "$delay" | tee "$chip_tool_log_file"
        # Prevent cleanup trying to kill a process we already killed.
        temp_background_pid=$background_pid
        background_pid=0
        kill -9 "$temp_background_pid"
        echo "  ===== Test complete: $i"
    done
    echo " ===== Iteration $j completed"
done

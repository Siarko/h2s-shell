# The lock screen's screen-off waits while somebody is at it (Lockscreen.attended → Idle): the
# prompt kept awake for 15 s (its sleep time stretched, H2S_LOCK_TEST_TIMINGS) holds the
# bed's output on past the lock screen's 5 s; when the prompt sleeps, the output goes off.

stack_start --timings '{"prompt": 15000}' --settings '{"lockscreen.lockedScreenOffTimeout": 5}'

dpms_is() {
    hyprctl -j monitors | python3 -I -c '
import json, sys
monitors = json.load(sys.stdin)
sys.exit(0 if monitors and all(str(monitor.get("dpmsStatus")).lower() == sys.argv[1] for monitor in monitors) else 1)' "$1"
}
# dpms_stays <seconds> <true|false>: says so all along, polled for that long
dpms_stays() {
    local deadline=$((${EPOCHREALTIME/[.,]/} + $1 * 1000000))
    while [ "${EPOCHREALTIME/[.,]/}" -lt "$deadline" ]; do
        dpms_is "$2" || return 1
        sleep 0.2 # fixed sleep: the poll's pause, not a wait for anything
    done
    return 0
}

lock_by_ipc
check_within "$GUARD" "locked" compositor_locked
wake_prompt || fail "the prompt did not wake"
check "the prompt is awake" state_is prompt_awake true
check "the output stays on past the lock screen's 5 s while the prompt is awake" dpms_stays 8 true
check "… the prompt still awake" state_is prompt_awake true
check_within 15 "the prompt sleeps" state_is prompt_awake false
check_within "$GUARD" "… and the output goes off (its time long past)" dpms_is false

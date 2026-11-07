# Isolated checks

- F1 checks missing or unreadable temperature input before and after hold starts; failure must report an error, write `level auto`, exit nonzero, and restart installed thinkfan. The protection-off setting must keep holding.
- F2 checks that 90000 m°C keeps the level and 90500 m°C restores automatic control.
- F3 checks write and systemd-run errors, automatic recovery after hold launch failure, verification that a new hold becomes active, pkexec codes 126/127 through `fanstate.switchError`, and these set-helper cases: no hold/no thinkfan, auto with no hold, replacing an active hold, and systemd-run refusal. Switch errors are translated from a literal QML message.
- F3 also rejects helper code that probes the fixture filesystem (`stat -f` or proc filesystem type).
- F4 checks the status helper's fifth field: active, inactive (also for an unloaded transient hold unit — the normal state after a stop), unknown only when systemctl gives no answer; plus mode mapping for a numeric level.
- F5 checks `sudo thinkpad-fan-set auto` precedes the first `sudo rm`, that uninstall makes no direct privileged calls, and that a failed restore or missing/non-executable set helper reports recovery instructions and removes nothing.
- F6 uses one numeric contract: `throttle(previous, current)` returns the event delta, `0` for no new events, and `null` without a baseline; samples are 10, 11, 11.
- F7 checks unavailable sensors and the `unavailable` counter marker differ from real zeros, including resetting the counter baseline after failed or incomplete status polls.
- F8 checks auto-write failure, failure to start installed thinkfan, valid firmware automation when `list-unit-files` reports thinkfan absent, and visible errors when querying unit files fails; a start call is not required when thinkfan is absent.

The systemd stub models loaded unit state in `$WORK/units`: successful `systemd-run` loads an active transient unit; stopping an unloaded unit returns 5, resetting an unloaded unit returns 1, and `is-active` returns the systemd word and status for active, inactive, failed, or unloaded state. Per-operation environment overrides can inject command failures.

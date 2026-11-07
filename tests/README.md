# Isolated checks

- F1 checks missing or unreadable temperature input before and after hold starts; failure must report an error, write `level auto`, exit nonzero, and restart installed thinkfan.
- F2 checks that 90000 m°C keeps the level and 90500 m°C restores automatic control.
- F3 checks `Fan level switch failed` for pkexec exit codes 126 and 127, silence on success, and helper write/launch outcomes.
- F4 checks active, inactive, and unknown hold states through the status helper's appended fifth field, plus mode mapping for the same numeric level.
- F5 checks automatic control is restored before component removal and a failed service start is reported.
- F6 uses one numeric contract: `throttle(previous, current)` returns the event delta, `0` for no new events, and `null` without a baseline; samples are 10, 11, 11.
- F7 checks unavailable sensors and the `unavailable` counter marker differ from real zeros, including resetting the counter baseline.
- F8 checks auto-write failure, failure to start installed thinkfan, and valid firmware automation when `list-unit-files` reports thinkfan absent; start need not be called.

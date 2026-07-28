# ThinkPad Fan Control

A Plasma 6 panel widget for ThinkPad laptops: shows fan speed, temperature, CPU
frequency and thermal throttling — and lets you pin the fan to a fixed level
straight from the panel.

Plasma ships widgets that *display* sensors, but nothing that *controls* the fan.
This one does both.

```
  52°        <- temperature
 1.3G        <- CPU frequency, turns red while throttling
```

## Features

- fan RPM, temperature, CPU frequency in the panel (second line is configurable)
- **throttling indicator** — the frequency turns red the moment the CPU is
  thermally throttled
- one-click fan levels: `automatic`, `0`–`7`, `full speed`
- honest mode reporting: automatic via thinkfan, automatic via firmware, or
  manually pinned — these are three different states and the widget says which
- levels are *held*: the firmware and thinkfan both overwrite a manually set
  level within seconds, so a helper rewrites it continuously
- safety net: a pinned level is released if the CPU exceeds 90 °C

## Requirements

- Plasma 6
- a ThinkPad with the `thinkpad_acpi` module (`/proc/acpi/ibm/fan` must exist)
- fan control enabled in the module:

  ```sh
  echo 'options thinkpad_acpi fan_control=1' | sudo tee /etc/modprobe.d/thinkpad_acpi.conf
  sudo modprobe -r thinkpad_acpi && sudo modprobe thinkpad_acpi
  ```

## Install

```sh
git clone https://github.com/aiseeq/plasma-thinkpad-fan
cd plasma-thinkpad-fan
./install.sh
systemctl --user restart plasma-plasmashell
```

Then right-click the panel → *Add Widgets* → **ThinkPad Fan Control**.

Uninstall with `./install.sh --uninstall`.

## Configuration

If the fan reading stays at 0, the sensor id differs on your model. Open the
widget settings and pick the right one; list what is available with:

```sh
busctl --user call org.kde.ksystemstats1 /org/kde/ksystemstats1 \
       org.kde.ksystemstats1 allSensors | tr ' ' '\n' | grep -oE '"lmsensors/[^"]*"'
```

## How it works

| Component | Role |
| --- | --- |
| `thinkpad-fan-status` | unprivileged; reports level, thinkfan state, frequency, throttle counter |
| `thinkpad-fan-set` | privileged; validates the argument and switches mode |
| `thinkpad-fan-hold` | systemd unit; keeps the chosen level from being overwritten |

### Privileges

The widget calls `thinkpad-fan-set` through `pkexec`. The shipped polkit rule
allows the *locally logged-in* user to do this without a password — otherwise
every click would raise a prompt. The privilege is narrow: the helper accepts
nothing but `auto|0-7|full` and rejects everything else.

If you would rather be asked for a password, edit
`/usr/share/polkit-1/actions/com.github.aiseeq.thinkpadfan.policy` and change
`<allow_active>yes</allow_active>` to `auth_admin_keep`.

### Why levels have to be held

Writing a level once is not enough. `thinkfan`, if running, reapplies its own
curve within seconds; the embedded controller also revises the level on its own.
So `thinkpad-fan-hold` rewrites the requested level every 100 ms — a foreign
change survives at most one interval.

Tune it with environment variables in the unit:
`THINKPAD_FAN_INTERVAL` (seconds, default `0.1`) and `THINKPAD_FAN_TCRIT`
(°C, default `90`, `0` disables the safety net).

## Known limitations

- **The throttling indicator sees thermal throttling only.** It is derived from
  `package_throttle_count`; a power (RAPL/TDP) limit does not raise that counter
  even though it holds the frequency down. If the indicator says *no* while the
  frequency sits well below the maximum, you are power-limited, not overheating.
- `package_throttle_total_time_ms` is always 0 on some Intel generations
  (confirmed on Meteor Lake / Core Ultra 155H), which is why the event counter is
  used instead.
- `full speed` (`disengaged`) behaves differently across models — on some it does
  not spin the fan up at all.
- Fan levels are a ThinkPad/`thinkpad_acpi` feature. On other laptops the widget
  will show sensors but the level buttons will not work.

## Caution

Pinning `level 0` disables the fan entirely. The 90 °C safety net helps, but do
not leave a laptop pinned at a low level under sustained load.

## License

MIT — see [LICENSE](LICENSE).

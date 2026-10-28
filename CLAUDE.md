# plasma-thinkpad-fan

Plasma 6 panel widget (QML, `package/`) plus bash helpers in `/usr/local/bin` (`helpers/`) and a polkit rule (`polkit/`); layout and roles — `README.md`. Public, MIT: nothing personal in the repo.

- Install on this laptop — `./install.sh` as the user (it asks for sudo itself), then `systemctl --user restart plasma-plasmashell`; remove — `./install.sh --uninstall`. KDE Store file — `./make-plasmoid.sh` → `dist/`, upload texts — `docs/STORE.md`.
- No `.graft.yaml`, no gate: commit with plain git on `main`. Before it — `bash -n` and `shellcheck` on changed scripts, and a live check on the laptop for a QML or helper change (the widget shows the level, the fan follows).
- `Plasmoid.configuration.*` is empty on the first binding pass: read it through properties with a fallback, or the sensors bind to `undefined` for good (0 °C).
- Throttling — by the growth of `package_throttle_count`; `*_total_time_ms` is always 0 on Meteor Lake.
- `thinkpad-fan-hold` writes the level only when it differs: a blind rewrite every 100 ms made the fan spin up again and stick at ~2000 RPM (5805ca4).
- The tachometer in `/proc/acpi/ibm/fan` lies (300/600/2300 while spinning): measure RPM at `/sys/class/hwmon/hwmon*/fan1_input` of the hwmon named `thinkpad`.
- Sensor ids — `busctl --user call org.kde.ksystemstats1 /org/kde/ksystemstats1 org.kde.ksystemstats1 allSensors` (qdbus cannot).
- Machine config around it (`thinkpad_acpi fan_control=1`, thinkfan) lives in `~/git/machine`, not here.

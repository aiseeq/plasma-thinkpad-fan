<!-- lex: собран из ~/.claude/codex/manifest/git-plasma%2Dthinkpad%2Dfan-CLAUDE.md.yaml. Правь фрагменты в ~/.claude/codex/frag и запусти `lex build --codex ~/.claude/codex`; правку прямо в этом файле перенеси во фрагменты: `lex absorb --codex ~/.claude/codex <этот файл>` -->
# plasma-thinkpad-fan

Plasma 6 panel widget (QML, `package/`) plus bash helpers in `/usr/local/bin` (`helpers/`) and a polkit rule (`polkit/`); layout and roles — `README.md`. Public, MIT: nothing personal in the repo.

- Install on this laptop — `./install.sh` as the user (it asks for sudo itself), then `systemctl --user restart plasma-plasmashell`; remove — `./install.sh --uninstall`. KDE Store file — `./make-plasmoid.sh` → `dist/`, upload texts — `docs/STORE.md`.
- Commit — `graft commit` (it also pushes); for a QML or helper change, a live check on the laptop before it (the widget shows the level, the fan follows).
  Зачем: the gate checks every script and runs the isolated stand on each commit; only the laptop shows whether the real widget and fan follow
- `Plasmoid.configuration.*` is empty on the first binding pass: read it through properties with a fallback, or the sensors bind to `undefined` for good (0 °C).
  Зачем: the widget's sensors do not bind to undefined for good and show 0 °C
- Throttling — by the growth of `package_throttle_count`; `*_total_time_ms` is always 0 on Meteor Lake.
  Зачем: throttling is not reported as absent because the time counters stay at 0 on Meteor Lake
- The tachometer in `/proc/acpi/ibm/fan` lies (300/600/2300 while spinning): measure RPM at `/sys/class/hwmon/hwmon*/fan1_input` of the hwmon named `thinkpad`.
  Зачем: fan speed is not judged by the /proc tachometer, which reports false RPM
- Sensor ids — `busctl --user call org.kde.ksystemstats1 /org/kde/ksystemstats1 org.kde.ksystemstats1 allSensors` (qdbus cannot).
- Machine config around it (`thinkpad_acpi fan_control=1`, thinkfan) lives in `~/git/machine`, not here.

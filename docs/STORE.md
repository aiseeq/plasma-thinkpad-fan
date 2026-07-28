# Publishing to the KDE Store

Ready-to-paste texts for the store.kde.org upload form.

## Build the file first

```sh
./make-plasmoid.sh
# -> dist/thinkpad-fan-control-1.0.plasmoid
```

## Form fields

**Title**

```
ThinkPad Fan Control
```

**Category**

`Plasma 6 Extensions` — then the applet/widget subcategory.

Make sure you are on **store.kde.org** and not on pling.com: the upload form is
shared across the OpenDesktop platform, but the category list comes from the site
you are logged into. On pling.com the only Plasma entries are the Plasma Mobile
ones, and no desktop Plasma category is offered at all.

Do **not** post under Plasma 5 categories — the applet requires the Plasma 6 API.

**Summary / short description**

```
Fan speed, temperature, CPU frequency and a throttling indicator in the panel — plus one-click fan level control for ThinkPad laptops.
```

**Description**

```
Plasma ships plenty of widgets that display sensors, but none that control the fan. This one does both.

In the panel it shows temperature and CPU frequency; the frequency turns red the moment the CPU is thermally throttled, so you can spot throttling without opening anything. Clicking it opens fan RPM, temperature, frequency, throttling state and buttons to set the fan level: automatic, 0-7, or full speed.

The widget reports the fan mode honestly, distinguishing three states that are usually conflated: driven by thinkfan, left to the firmware, or pinned manually.

Setting a level actually keeps it. Both thinkfan and the embedded controller overwrite a manually set level within seconds, so a small helper rewrites the requested level continuously. A pinned level is released above 90 °C, so a forgotten "level 0" cannot cook the machine.

IMPORTANT — this widget needs helper scripts that the Store cannot install for you.
Installing from "Get New Widgets" gives you the UI only; the fan buttons will not
work until you run the installer from the project page:

    git clone https://github.com/aiseeq/plasma-thinkpad-fan
    cd plasma-thinkpad-fan
    ./install.sh

The installer places three helpers in /usr/local/bin and a polkit rule that lets
your local session change the fan level without a password prompt.

Requirements: Plasma 6, a ThinkPad exposing /proc/acpi/ibm/fan, and fan control
enabled in thinkpad_acpi (fan_control=1).

Known limitation: the throttling indicator reflects thermal throttling only. A
power (RAPL/TDP) limit holds the frequency down without raising the kernel's
throttle counter — if the indicator says "no" while the frequency sits well below
maximum, you are power-limited rather than overheating.

Source, documentation and issue tracker: https://github.com/aiseeq/plasma-thinkpad-fan
```

**Version**

```
1.0
```

**Changelog**

```
1.0 — first release.
Panel readout (temperature, CPU frequency, fan RPM), thermal throttling
indicator, fan level control (automatic / 0-7 / full speed), configurable
sensor ids, polkit-based privilege handling.
```

**License**

`MIT`

**Tags**

```
thinkpad, fan, fan-control, sensors, temperature, throttling, cpu, laptop, plasma6, widget
```

**Link / homepage**

```
https://github.com/aiseeq/plasma-thinkpad-fan
```

**Product Logo**

Upload `docs/logo.png` (256×256).

**Gallery pictures** (mandatory)

Upload both from `docs/`:

- `screenshot-popup.png` — the popup with readings and level buttons (make this the first one, it is used as the thumbnail)
- `screenshot-panel.png` — how it looks in the panel

**File**

Upload `dist/thinkpad-fan-control-1.0.plasmoid`.

## After publishing

Add the Store link to the README, and bump `Version` in `package/metadata.json`
before every new upload — Plasma uses it to offer updates to users.

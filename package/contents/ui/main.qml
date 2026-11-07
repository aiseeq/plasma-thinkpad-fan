/*
 * ThinkPad Fan Control — Plasma 6 applet
 * SPDX-License-Identifier: MIT
 */
import QtQuick
import "../code/fanstate.js" as FanState
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors

PlasmoidItem {
    id: root

    readonly property string statusHelper: "/usr/local/bin/thinkpad-fan-status"
    readonly property string setHelper: "/usr/local/bin/thinkpad-fan-set"

    // Configuration is not populated yet on the first binding pass, so every read
    // needs a fallback — otherwise the sensors bind to undefined and stay empty.
    readonly property string fanSensorId: Plasmoid.configuration.fanSensorId
                                          || "lmsensors/thinkpad-isa-0000/fan1"
    readonly property string tempSensorId: Plasmoid.configuration.tempSensorId
                                           || "cpu/all/maximumTemperature"
    readonly property string compactSecondLine: Plasmoid.configuration.compactSecondLine
                                                || "frequency"

    property string fanLevel: "—"
    property bool thinkfanRunning: false
    property var freqMhz: null
    property bool helperMissing: false

    // Throttling is derived from the growth of the kernel event counter between
    // polls: package_throttle_total_time_ms stays 0 on several Intel generations,
    // while the counter records thermal events between polls. This reflects thermal throttling only —
    // a power (RAPL) limit does not raise it, but does hold the frequency down.
    property var throttleCount: null
    property var throttleDelta: null
    property bool throttling: false

    // Three distinct states: thinkfan drives its curve, the level is handed to the
    // firmware, or a level is pinned manually.
    readonly property bool autoMode: thinkfanRunning || fanLevel === "auto"
    property string switchFailure: ""
    property string holdState: "unknown"
    readonly property string modeText: {
        var mode = FanState.mode(fanLevel, thinkfanRunning, holdState)
        if (mode === "automatic")
            return thinkfanRunning ? i18n("Mode: automatic (thinkfan)") : i18n("Mode: automatic (firmware)")
        if (mode === "manual" && fanLevel === "auto") return i18n("Mode: manual (hold is restoring the chosen level)")
        if (mode === "manual") return i18n("Mode: manual, level %1", fanLevel)
        if (mode === "level-unheld") return i18n("Level %1 set, hold is not running", fanLevel)
        return i18n("Fan mode unknown")
    }

    readonly property var rpm: FanState.sensorValue(fanSensor.value)
    readonly property var temp: FanState.sensorValue(tempSensor.value)
    readonly property string rpmText: rpm === null ? i18n("n/a") : rpm
    readonly property string tempText: temp === null ? "—" : temp

    Plasmoid.icon: "sensors"
    toolTipMainText: rpm === null ? i18n("Fan: n/a") : i18n("Fan: %1 RPM", rpm)
    toolTipSubText: modeText

    preferredRepresentation: compactRepresentation

    Sensors.Sensor {
        id: fanSensor
        sensorId: root.fanSensorId
        updateRateLimit: 2000
        enabled: true
    }

    Sensors.Sensor {
        id: tempSensor
        sensorId: root.tempSensorId
        updateRateLimit: 2000
        enabled: true
    }

    // Reading state and switching levels go through helper scripts, which keeps
    // shell quoting out of QML and confines privileged work to one audited place.
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            if (source !== root.statusHelper) {
                if (data["exit code"] === 0)
                    root.switchFailure = ""
                else if (FanState.switchError(data["exit code"], data.stderr) === "switch-failed")
                    root.switchFailure = i18n("Fan level switch failed")
            }
            if (source === root.statusHelper) {
                var state = FanState.applyStatus(root.throttleCount, data.stdout || "", data["exit code"])
                root.helperMissing = state.helperMissing
                root.fanLevel = state.level === null ? "—" : state.level
                root.thinkfanRunning = state.thinkfanRunning
                root.holdState = state.holdState
                root.freqMhz = state.freqMhz
                root.throttleDelta = state.throttleDelta
                root.throttling = state.throttling
                root.throttleCount = state.throttleBaseline
            }
            exec.disconnectSource(source)
        }

        function poll() {
            exec.connectSource(root.statusHelper)
        }

        function setLevel(value) {
            // pkexec + a polkit rule with allow_active=yes: no password prompt for
            // the local session, and no sudoers editing by the user.
            exec.connectSource("pkexec " + root.setHelper + " " + value)
            refreshTimer.restart()
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.poll()
    }

    // Quick re-read right after a level change, so the UI does not lag behind.
    Timer {
        id: refreshTimer
        interval: 700
        repeat: false
        onTriggered: exec.poll()
    }

    compactRepresentation: MouseArea {
        Layout.minimumWidth: column.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: column.implicitHeight

        onClicked: root.expanded = !root.expanded

        ColumnLayout {
            id: column
            anchors.centerIn: parent
            spacing: 0

            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignHCenter
                text: root.temp === null ? "—" : root.temp + "°"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                lineHeight: 0.9
            }

            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignHCenter
                visible: root.compactSecondLine !== "temperature"
                text: {
                    if (root.compactSecondLine === "rpm")
                        return root.rpm === null ? "n/a" : root.rpm
                    if (root.freqMhz === null) return "n/a"
                    return root.freqMhz >= 1000 ? (root.freqMhz / 1000).toFixed(1) + "G"
                                                : root.freqMhz + "M"
                }
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.bold: root.throttling
                // Red means throttle events occurred during the last poll interval.
                color: root.throttling ? Kirigami.Theme.negativeTextColor
                                       : Kirigami.Theme.textColor
                lineHeight: 0.9
            }
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 14
        spacing: Kirigami.Units.smallSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.helperMissing
            type: Kirigami.MessageType.Error
            text: i18n("Helper scripts are missing. Run install.sh from the project.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: root.switchFailure !== ""
            type: Kirigami.MessageType.Error
            text: root.switchFailure
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: FanState.holdFailed(root.holdState)
            type: Kirigami.MessageType.Warning
            text: i18n("The fan hold stopped with an error (temperature protection or a fan write failed), so the chosen level was dropped. Details: journalctl -u thinkpad-fan-hold")
        }

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 2
            text: root.rpm === null ? i18n("Fan: n/a") : i18n("%1 RPM", root.rpm)
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: root.temp === null ? i18n("Temperature: —") : i18n("Temperature: %1 °C", root.temp)
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: Plasmoid.configuration.showFrequency
            text: root.freqMhz === null ? i18n("Frequency: n/a") : i18n("Frequency: %1 MHz", root.freqMhz)
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: Plasmoid.configuration.showThrottling
            text: root.throttleDelta === null ? i18n("Throttling events since last poll: unknown")
                : i18n("Throttling events since last poll: %1", root.throttleDelta)
            color: root.throttling ? Kirigami.Theme.negativeTextColor
                                   : Kirigami.Theme.positiveTextColor
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: root.modeText
        }

        Kirigami.Separator { Layout.fillWidth: true }

        PlasmaComponents.Button {
            Layout.fillWidth: true
            text: i18n("Automatic")
            icon.name: "system-run"
            highlighted: root.autoMode
            onClicked: exec.setLevel("auto")
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 4
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.smallSpacing

            Repeater {
                model: ["0", "1", "2", "3", "4", "5", "6", "7"]

                PlasmaComponents.Button {
                    required property string modelData
                    Layout.fillWidth: true
                    text: modelData
                    highlighted: !root.autoMode && root.fanLevel === modelData
                    onClicked: exec.setLevel(modelData)
                }
            }
        }

        PlasmaComponents.Button {
            Layout.fillWidth: true
            text: i18n("Full speed")
            highlighted: !root.autoMode && root.fanLevel === "disengaged"
            onClicked: exec.setLevel("full")
        }

        Item { Layout.fillHeight: true }
    }
}

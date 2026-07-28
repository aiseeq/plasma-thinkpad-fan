/*
 * ThinkPad Fan Control — Plasma 6 applet
 * SPDX-License-Identifier: MIT
 */
import QtQuick
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

    property string fanLevel: "—"
    property bool thinkfanRunning: false
    property int freqMhz: 0
    property bool helperMissing: false

    // Throttling is derived from the growth of the kernel event counter between
    // polls: package_throttle_total_time_ms stays 0 on several Intel generations,
    // while the counter is reliable. Note this reflects *thermal* throttling only —
    // a power (RAPL) limit does not raise it, but does hold the frequency down.
    property int throttleCount: -1
    property bool throttling: false

    // Three distinct states: thinkfan drives its curve, the level is handed to the
    // firmware, or a level is pinned manually.
    readonly property bool autoMode: thinkfanRunning || fanLevel === "auto"
    readonly property string modeText: thinkfanRunning ? i18n("Mode: automatic (thinkfan)")
                                     : fanLevel === "auto" ? i18n("Mode: automatic (firmware)")
                                     : i18n("Mode: manual, level %1", fanLevel)

    readonly property int rpm: fanSensor.value !== undefined ? Math.round(fanSensor.value) : 0
    readonly property int temp: tempSensor.value !== undefined ? Math.round(tempSensor.value) : 0

    Plasmoid.icon: "sensors"
    toolTipMainText: i18n("Fan: %1 RPM", rpm)
    toolTipSubText: modeText

    preferredRepresentation: compactRepresentation

    Sensors.Sensor {
        id: fanSensor
        sensorId: Plasmoid.configuration.fanSensorId
        updateRateLimit: 2000
        enabled: true
    }

    Sensors.Sensor {
        id: tempSensor
        sensorId: Plasmoid.configuration.tempSensorId
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
            if (source === root.statusHelper) {
                root.helperMissing = (data["exit code"] !== 0)

                var parts = (data.stdout || "").trim().split("|")
                if (parts.length >= 2) {
                    root.fanLevel = parts[0]
                    root.thinkfanRunning = (parts[1] === "active")
                }
                if (parts.length >= 4) {
                    root.freqMhz = parseInt(parts[2]) || 0

                    var c = parseInt(parts[3]) || 0
                    // First sample is only remembered: nothing to compare against yet.
                    root.throttling = (root.throttleCount >= 0 && c > root.throttleCount)
                    root.throttleCount = c
                }
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
                text: root.temp + "°"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                lineHeight: 0.9
            }

            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignHCenter
                visible: Plasmoid.configuration.compactSecondLine !== "temperature"
                text: {
                    if (Plasmoid.configuration.compactSecondLine === "rpm")
                        return root.rpm
                    return root.freqMhz >= 1000 ? (root.freqMhz / 1000).toFixed(1) + "G"
                                                : root.freqMhz + "M"
                }
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.bold: root.throttling
                // Red means the CPU is being throttled right now.
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

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 2
            text: i18n("%1 RPM", root.rpm)
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: i18n("Temperature: %1 °C", root.temp)
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: Plasmoid.configuration.showFrequency
            text: i18n("Frequency: %1 MHz", root.freqMhz)
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            visible: Plasmoid.configuration.showThrottling
            text: root.throttling ? i18n("Throttling: YES (%1 events)", root.throttleCount)
                                  : i18n("Throttling: no")
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

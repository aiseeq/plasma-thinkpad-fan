import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_fanSensorId: fanSensor.text
    property alias cfg_tempSensorId: tempSensor.text
    property alias cfg_showFrequency: showFrequency.checked
    property alias cfg_showThrottling: showThrottling.checked
    property string cfg_compactSecondLine

    QQC2.TextField {
        id: fanSensor
        Kirigami.FormData.label: i18n("Fan sensor:")
        Layout.fillWidth: true
    }

    QQC2.TextField {
        id: tempSensor
        Kirigami.FormData.label: i18n("Temperature sensor:")
        Layout.fillWidth: true
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: i18n("Sensor ids differ between models. List the available ones with:\nbusctl --user call org.kde.ksystemstats1 /org/kde/ksystemstats1 org.kde.ksystemstats1 allSensors")
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.ComboBox {
        Kirigami.FormData.label: i18n("Second line in panel:")
        model: [
            { value: "frequency",   label: i18n("CPU frequency") },
            { value: "rpm",         label: i18n("Fan RPM") },
            { value: "temperature", label: i18n("Temperature only") }
        ]
        textRole: "label"
        valueRole: "value"
        onActivated: page.cfg_compactSecondLine = currentValue
        Component.onCompleted: currentIndex = indexOfValue(page.cfg_compactSecondLine)
    }

    QQC2.CheckBox {
        id: showFrequency
        Kirigami.FormData.label: i18n("Show in popup:")
        text: i18n("CPU frequency")
    }

    QQC2.CheckBox {
        id: showThrottling
        text: i18n("Thermal throttling")
    }
}

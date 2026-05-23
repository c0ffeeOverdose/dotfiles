import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar as Bar
import qs.modules.custom.resources
import qs.services
import QtQuick
import QtQuick.Layouts

Bar.StyledPopup {
    id: root

    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB"
    }

    Row {
        anchors.centerIn: parent
        spacing: 12

        Column {
            anchors.top: parent.top
            spacing: 8

            Bar.StyledPopupHeaderRow {
                icon: "memory"
                label: "RAM"
            }
            Column {
                spacing: 4
                Bar.StyledPopupValueRow {
                    icon: "clock_loader_60"
                    label: Translation.tr("Used:")
                    value: root.formatKB(CustomResourceUsage.memoryUsed)
                }
                Bar.StyledPopupValueRow {
                    icon: "check_circle"
                    label: Translation.tr("Free:")
                    value: root.formatKB(CustomResourceUsage.memoryFree)
                }
                Bar.StyledPopupValueRow {
                    icon: "empty_dashboard"
                    label: Translation.tr("Total:")
                    value: root.formatKB(CustomResourceUsage.memoryTotal)
                }
            }
        }

        Column {
            visible: CustomResourceUsage.swapTotal > 0
            anchors.top: parent.top
            spacing: 8

            Bar.StyledPopupHeaderRow {
                icon: "swap_horiz"
                label: "Swap"
            }
            Column {
                spacing: 4
                Bar.StyledPopupValueRow {
                    icon: "clock_loader_60"
                    label: Translation.tr("Used:")
                    value: root.formatKB(CustomResourceUsage.swapUsed)
                }
                Bar.StyledPopupValueRow {
                    icon: "check_circle"
                    label: Translation.tr("Free:")
                    value: root.formatKB(CustomResourceUsage.swapFree)
                }
                Bar.StyledPopupValueRow {
                    icon: "empty_dashboard"
                    label: Translation.tr("Total:")
                    value: root.formatKB(CustomResourceUsage.swapTotal)
                }
            }
        }

        Column {
            anchors.top: parent.top
            spacing: 8

            Bar.StyledPopupHeaderRow {
                icon: "planner_review"
                label: "CPU"
            }
            Column {
                spacing: 4
                Bar.StyledPopupValueRow {
                    icon: "bolt"
                    label: Translation.tr("Load:")
                    value: `${Math.round(CustomResourceUsage.cpuUsage * 100)}%`
                }
                Bar.StyledPopupValueRow {
                    visible: CustomResourceUsage.cpuTempAvailable
                    icon: "device_thermostat"
                    label: Translation.tr("Temp:")
                    value: `${Math.round(CustomResourceUsage.cpuTempC)}°C`
                }
                Bar.StyledPopupValueRow {
                    visible: CustomResourceUsage.cpuClockAvailable
                    icon: "speed"
                    label: Translation.tr("Clock:")
                    value: CustomResourceUsage.cpuClockString
                }
            }
        }
    }
}

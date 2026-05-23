pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property real memoryTotal: 1
    property real memoryFree: 0
    property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal

    property real swapTotal: 1
    property real swapFree: 0
    property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0

    property real cpuUsage: 0
    property var previousCpuStats

    property real cpuTempC: 0
    property real cpuClockMHz: 0
    property string cpuClockString: "--"

    property string cpuTempPath: ""
    property string cpuFreqPath: ""
    property bool cpuTempAvailable: cpuTempPath.length > 0
    property bool cpuClockAvailable: cpuFreqPath.length > 0

    Timer {
        interval: 1
        running: true
        repeat: true
        onTriggered: {
            fileMeminfo.reload()
            fileStat.reload()
            fileCpuTemp.reload()
            fileCpuFreq.reload()

            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
            swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

            const textStat = fileStat.text()
            const cpuLine = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle = stats[3]

                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff = idle - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }

                previousCpuStats = { total, idle }
            }

            const tempRaw = Number(fileCpuTemp.text().trim())
            cpuTempC = (!isNaN(tempRaw) && tempRaw > 0) ? (tempRaw / 1000) : 0

            const freqRaw = Number(fileCpuFreq.text().trim())
            cpuClockMHz = (!isNaN(freqRaw) && freqRaw > 0) ? (freqRaw / 1000) : 0
            cpuClockString = cpuClockMHz > 0 ? (cpuClockMHz / 1000).toFixed(2) + " GHz" : "--"

            interval = Config.options?.resources?.updateInterval ?? 3000
        }
    }

    FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }
    FileView { id: fileCpuTemp; path: root.cpuTempPath }
    FileView { id: fileCpuFreq; path: root.cpuFreqPath }

    Process {
        id: detectCpuTempPathProc
        running: true
        command: ["bash", "-c", "for z in /sys/class/thermal/thermal_zone*; do [ -r \"$z/type\" ] || continue; t=$(cat \"$z/type\" 2>/dev/null); case \"$t\" in *x86_pkg_temp*|*k10temp*|*cpu*|*pkg*|*soc*) [ -r \"$z/temp\" ] && { echo \"$z/temp\"; exit 0; } ;; esac; done; for z in /sys/class/hwmon/hwmon*; do [ -r \"$z/name\" ] || continue; n=$(cat \"$z/name\" 2>/dev/null); case \"$n\" in *coretemp*|*k10temp*|*zenpower*|*cpu*) for i in \"$z\"/temp*_input; do [ -r \"$i\" ] && { echo \"$i\"; exit 0; }; done ;; esac; done"]
        stdout: StdioCollector {
            id: tempPathCollector
            onStreamFinished: {
                root.cpuTempPath = tempPathCollector.text.trim()
            }
        }
    }

    Process {
        id: detectCpuFreqPathProc
        running: true
        command: ["bash", "-c", "for p in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do [ -r \"$p\" ] && { echo \"$p\"; exit 0; }; done"]
        stdout: StdioCollector {
            id: freqPathCollector
            onStreamFinished: {
                root.cpuFreqPath = freqPathCollector.text.trim()
            }
        }
    }
}

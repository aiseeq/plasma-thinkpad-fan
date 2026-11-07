.pragma library

function parseStatus(stdout, exitCode) {
    var result = { helperMissing: exitCode !== 0, level: null, thinkfanRunning: false,
                   freqMhz: null, throttleCount: null, holdState: "unknown", partsCount: 0 }
    var parts = (stdout || "").trim().split("|")
    result.partsCount = parts.length
    if (parts.length >= 2) {
        result.level = parts[0]
        result.thinkfanRunning = parts[1] === "active"
    }
    if (parts.length >= 4) {
        var freq = parseInt(parts[2])
        var count = parseInt(parts[3])
        result.freqMhz = parts[2] === "unavailable" || Number.isNaN(freq) ? null : freq
        result.throttleCount = parts[3] === "unavailable" || Number.isNaN(count) ? null : count
    }
    if (parts.length >= 5)
        result.holdState = parts[4] === "active" ? "active" : parts[4] === "inactive" ? "inactive" : "unknown"
    return result
}

function mode(level, thinkfanRunning, holdState) {
    if (thinkfanRunning || level === "auto") return "automatic"
    if (holdState === "active") return "manual"
    if (holdState === "inactive") return "level-unheld"
    return "unknown"
}

function throttle(previous, current) {
    if (previous === null || previous === undefined || current === null || current === undefined)
        return null
    return Math.max(0, current - previous)
}

function nextThrottleBaseline(current) {
    return current === null || current === undefined ? null : current
}

function applyStatus(previousThrottleCount, stdout, exitCode) {
    var result = parseStatus(stdout, exitCode)
    var complete = exitCode === 0 && result.partsCount >= 5 && result.level !== null && result.level !== ""
    if (!complete) {
        result.level = null
        result.thinkfanRunning = false
        result.freqMhz = null
        result.throttleCount = null
        result.holdState = "unknown"
    }
    result.throttleDelta = complete ? throttle(previousThrottleCount, result.throttleCount) : null
    result.throttleBaseline = complete ? nextThrottleBaseline(result.throttleCount) : null
    result.throttling = result.throttleDelta !== null && result.throttleDelta > 0
    return result
}

function sensorValue(value) {
    return value === null || value === undefined || Number.isNaN(Number(value)) ? null : Math.round(value)
}

function switchError(exitCode, stderr) {
    return exitCode === 0 ? "" : "switch-failed"
}

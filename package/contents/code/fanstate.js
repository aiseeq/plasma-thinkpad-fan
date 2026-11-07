.pragma library

// Returns parsed status fields with the same defaults as the original widget.
function parseStatus(stdout, exitCode) {
    var result = { helperMissing: exitCode !== 0, level: null, thinkfanRunning: false,
                   freqMhz: 0, throttleCount: 0, holdState: "unknown", partsCount: 0 }

    var parts = (stdout || "").trim().split("|")
    result.partsCount = parts.length
    if (parts.length >= 2) {
        result.level = parts[0]
        result.thinkfanRunning = parts[1] === "active"
    }
    if (parts.length >= 4) {
        var freq = parseInt(parts[2])
        var count = parseInt(parts[3])
        result.freqMhz = Number.isNaN(freq) ? 0 : freq
        result.throttleCount = Number.isNaN(count) ? 0 : count
    }
    if (parts.length >= 5)
        result.holdState = parts[4] === "active" ? "active" : parts[4] === "inactive" ? "inactive" : "unknown"
    return result
}

// Returns the original widget mode derived from thinkfan state and numeric level.
function mode(level, thinkfanRunning, holdState) {
    if (thinkfanRunning || level === "auto") return "automatic"
    return "manual"
}

// Returns whether the counter grew since the previous sample, as in the original widget.
function throttle(previous, current) {
    return previous >= 0 && current > previous
}

// Returns the next counter baseline; unavailable readings clear it.
function nextThrottleBaseline(current) {
    return current === null || current === undefined ? null : current
}

// Returns a rounded sensor value, using the original widget's zero fallback.
function sensorValue(value) {
    return value !== undefined ? Math.round(value) : 0
}

// Returns the original widget's empty switch error message.
function switchError(exitCode, stderr) {
    return ""
}

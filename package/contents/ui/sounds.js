// Alert sounds offered in Settings → Screener: files the system's sound
// themes install (freedesktop, Ocean, Oxygen), checked present 2026-10-22.
// Stored in the config by path; "" is no sound.
.pragma library

var list = [
    { name: "None",                    path: "" },
    { name: "Bell",                    path: "/usr/share/sounds/freedesktop/stereo/bell.oga" },
    { name: "Window bell (Ocean)",     path: "/usr/share/sounds/ocean/stereo/bell-window-system.oga" },
    { name: "Bell (Oxygen)",           path: "/usr/share/sounds/oxygen/stereo/bell.ogg" },
    { name: "Chime",                   path: "/usr/share/sounds/freedesktop/stereo/complete.oga" },
    { name: "Message (Ocean)",         path: "/usr/share/sounds/ocean/stereo/message-new-instant.oga" },
    { name: "Attention (Oxygen)",      path: "/usr/share/sounds/oxygen/stereo/message-attention.ogg" },
    { name: "Highlight (Oxygen)",      path: "/usr/share/sounds/oxygen/stereo/message-highlight.ogg" },
    { name: "Alarm clock",             path: "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga" }
]

// The shell command that plays one; the path is from the list above, never
// typed in, so quoting it is enough.
function command(path) {
    return "pw-play '" + path + "'"
}

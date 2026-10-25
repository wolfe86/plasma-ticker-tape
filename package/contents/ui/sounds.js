// Alert sounds offered in Settings → Screener: files the system's sound
// themes install (freedesktop, Ocean, Oxygen), checked present on the
// developer's machine 2026-10-22 -- not on everyone's: Oxygen is often not
// installed. Stored in the config by path; "" is no sound; any other path is
// a file the user chose.
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

function quote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

// The shell command that plays one. `player` is the user's own command from
// Settings → Screeners ("%f" is the file; without it the file goes last).
// Left empty, the first player installed is used -- PipeWire's, PulseAudio's,
// libcanberra's, then ffmpeg's -- and a file that is not there falls back to
// the freedesktop bell, which every sound theme depends on.
function command(path, player) {
    const f = quote(path)
    const p = String(player || "").trim()
    if (p) return p.indexOf("%f") >= 0 ? p.split("%f").join(f) : p + " " + f
    return "f=" + f + "; [ -e \"$f\" ] || f=/usr/share/sounds/freedesktop/stereo/bell.oga; "
         + "if command -v pw-play >/dev/null 2>&1; then pw-play \"$f\"; "
         + "elif command -v paplay >/dev/null 2>&1; then paplay \"$f\"; "
         + "elif command -v canberra-gtk-play >/dev/null 2>&1; then canberra-gtk-play -f \"$f\"; "
         + "elif command -v ffplay >/dev/null 2>&1; then ffplay -nodisp -autoexit -loglevel quiet \"$f\"; fi"
}
function name(path) {
    const s = list.find(x => x.path === path)
    return s ? s.name : String(path).replace(/.*\//, "")
}

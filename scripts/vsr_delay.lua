-- Video enhancement pipeline: RTX VSR (always on) + a switchable enhancement mode.
--
--   DLSS 5            : ReShade DLSS 5 preset, 50/60fps streams capped to 30fps,
--                       mpv renders in dumb mode without interpolation.
--   Frame Generation  : ReShade preset without DLSS 5 (the add-on goes idle), native
--                       frame rate, mpv display-resample + interpolation to the display.
--
-- The mode is chosen from the right-click menu ("Enhancement Mode"), which sends
-- `script-message-to vsr_delay set-mode fg|dlss`, and is remembered across launches.
--
-- ReShade is driven through its preset shortcut keys (ReShade.ini):
--   F13 -> ReShadePreset.ini (DLSS 5)   F14 -> ReShadePreset_FG.ini (no effects)
-- The keys are delivered with PostMessage WM_KEYDOWN/WM_KEYUP straight to mpv's
-- window (ReShade hooks its WndProc), so no window focus is needed and mpv merely
-- logs an unbound-key press. ReShade saves PresetPath to ReShade.ini on every
-- switch, which is used to confirm it. StartupPresetPath makes every launch start
-- on the DLSS 5 preset so its NGX session is opened (and warmed up) once at
-- startup and later switches back to DLSS 5 are instant.

local utils = require "mp.utils"
local options = require "mp.options"

local o = {
    tscale = "oversample",
    reshade_ini = "~~home/../ReShade.ini",
    switch_timeout = 3,
}
options.read_options(o, "enhancement")

local filter_added = false
local held = false
local warmup_timer = nil
local saved = nil
local warming = false

local MODE_FILE = mp.command_native({ "expand-path", "~~state/enhancement_mode" })
local RESHADE_INI = mp.command_native({ "expand-path", o.reshade_ini })
local MODE_PROP = "user-data/enhancement/mode"
local PRESETS = {
    dlss = { key = 0x7C, scan = 0x64, file = "ReShadePreset.ini" },    -- F13
    fg = { key = 0x7D, scan = 0x65, file = "ReShadePreset_FG.ini" },   -- F14
}

-- mpv.conf values to return to when leaving Frame Generation
local DLSS_PROPS = {
    ["gpu-dumb-mode"] = mp.get_property("gpu-dumb-mode"),
    ["video-sync"] = mp.get_property("video-sync"),
    ["interpolation"] = mp.get_property("interpolation"),
    ["tscale"] = mp.get_property("tscale"),
}
local FG_PROPS = {
    ["gpu-dumb-mode"] = "no",   -- interpolation needs mpv's FBO renderer
    ["video-sync"] = "display-resample",
    ["interpolation"] = "yes",
    ["tscale"] = o.tscale,
}

local mode = "dlss"            -- what the user selected
local reshade_preset = "dlss"  -- what ReShade is running (StartupPresetPath)
local switching = false

-- The DLSS 5 add-on stalls Present several times while it spins up: ~1s when it opens
-- its NGX session on the first frame, ~0.5s when it builds its DLSS feature on the next
-- new frames, and ~0.3s when VSR switches the swapchain to 4K. mpv reports A/V desync
-- once audio runs >0.5s ahead of video, so:
--   1. stay paused for SESSION_SECS after the first frame (absorbs the session stall);
--   2. play muted at WARMUP_SPEED so new frames still reach the add-on, but each stall
--      only moves A/V by stall*speed;
--   3. inject d3d11vpp only after the add-on has built its feature on the plain decoded
--      frames (if d3d11 frames reach the VO during that first build, the add-on's
--      D3D12->D3D11 blit crashes in d3d11.dll with 0xC0000005);
--   4. return to normal speed once the 4K rebuild is done.
-- The add-on only counts frames arriving <50ms apart, so with the 30fps cap the warm-up
-- speed must stay >= ~0.67 for it to build at all.
local SESSION_SECS = 2.0
local WARMUP_SPEED = 0.7
local VSR_AT_SECS = 2.0
local WARMUP_SECS = 4.5

local function video_track()
    for _, t in ipairs(mp.get_property_native("track-list", {})) do
        if t.type == "video" and not t.albumart then return t end
    end
    return {}
end

local function vsr_needed()
    return (video_track()["demux-h"] or 0) < 2160
end

local function cap_needed()
    return vsr_needed() and (video_track()["demux-fps"] or 0) > 35
end

local function has_filter(label)
    for _, f in ipairs(mp.get_property_native("vf", {})) do
        if f.label == label then return true end
    end
    return false
end

-- Cap 50/60fps to 30fps to prevent the 100% 3D usage bottleneck with VSR + DLSS 5.
-- Prepended so it always runs before d3d11vpp (VSR then only scales 30 frames/s).
local function set_fps_cap(on)
    if on and cap_needed() and not has_filter("fpscap") then
        mp.command("no-osd vf pre @fpscap:fps=30")
    elseif not on and has_filter("fpscap") then
        mp.command("no-osd vf remove @fpscap")
    end
end

local function apply_props(props)
    for name, value in pairs(props) do
        if value and mp.get_property(name) ~= value then mp.set_property(name, value) end
    end
end

local function mode_label()
    if mode == "fg" then return "Frame Generation (" .. math.floor((mp.get_property_number("display-fps", 0)) + 0.5) .. "Hz)" end
    return cap_needed() and "DLSS 5 (30 FPS Cap)" or "DLSS 5"
end

function inject_vsr()
    if not filter_added then
        if not vsr_needed() then
            mp.osd_message("4K Native - VSR Skipped", 4)
            filter_added = true
            return
        end

        mp.command("no-osd vf add @vsr:d3d11vpp=scale=2:scaling-mode=nvidia")
        mp.osd_message("RTX VSR 2x + " .. mode_label(), 4)
        filter_added = true
    end
end

---------------------------------------------------------------------------
-- ReShade preset control

local function read_preset_path()
    local f = io.open(RESHADE_INI, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s:match("\nPresetPath=([^\r\n]*)")
end

local function preset_is(name)
    local p = read_preset_path()
    return p ~= nil and p:lower():sub(-#PRESETS[name].file) == PRESETS[name].file:lower()
end

-- ReShade starts on StartupPresetPath (DLSS 5) but only writes PresetPath when the
-- preset changes, so the file can still name the preset of a previous session. Reset
-- it at launch so that every confirmed switch is a real change of that line.
local function normalize_preset_path()
    local f = io.open(RESHADE_INI, "rb")
    if not f then return end
    local s = f:read("*a")
    f:close()
    local want = ".\\" .. PRESETS.dlss.file
    if not s:find("\nStartupPresetPath=[^\r\n]*" .. PRESETS.dlss.file:gsub("%.", "%%.")) then return end
    local new, n = s:gsub("(\nPresetPath=)[^\r\n]*", function(prefix) return prefix .. want end, 1)
    if n == 1 and new ~= s then
        local out = io.open(RESHADE_INI, "wb")
        if out then out:write(new) out:close() end
    end
end

local function press_key(preset)
    local p = PRESETS[preset]
    local hwnd = mp.get_property_number("window-id")
    if not hwnd or hwnd == 0 then return false end
    local ps = string.format(
        "Add-Type -Namespace W -Name U -MemberDefinition '[DllImport(\"user32.dll\")] public static extern " ..
        "bool PostMessageW(System.IntPtr h, uint m, System.IntPtr w, System.IntPtr l);';" ..
        "$h=[IntPtr]%d; [void][W.U]::PostMessageW($h,0x100,[IntPtr]%d,[IntPtr]1);" ..
        "Start-Sleep -Milliseconds 600; [void][W.U]::PostMessageW($h,0x101,[IntPtr]%d,[IntPtr]0xC0000001)",
        hwnd, p.key, p.key)
    mp.command_native_async({
        name = "subprocess", playback_only = false,
        args = { "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", ps },
    }, function() end)
    return true
end

local switch_gen = 0

-- Switch ReShade to `preset`; cb(ok). Retries up to 3 times.
local function switch_reshade(preset, cb)
    if reshade_preset == preset then return cb(true) end
    switch_gen = switch_gen + 1
    local gen, attempts = switch_gen, 0
    local function attempt()
        if not press_key(preset) then return cb(false) end
        attempts = attempts + 1
        local t0 = mp.get_time()
        local poll
        poll = mp.add_periodic_timer(0.2, function()
            if preset_is(preset) then
                poll:kill()
                reshade_preset = preset
                if gen == switch_gen then cb(true) end
            elseif gen ~= switch_gen then
                poll:kill()
            elseif mp.get_time() - t0 > o.switch_timeout then
                poll:kill()
                if attempts < 3 then attempt() else cb(false) end
            end
        end)
    end
    attempt()
end

---------------------------------------------------------------------------
-- Mode switching

local function save_mode()
    local f = io.open(MODE_FILE, "wb")
    if f then f:write(mode) f:close() end
end

local function load_mode()
    local f = io.open(MODE_FILE, "rb")
    local m = f and f:read("*l")
    if f then f:close() end
    return (m == "fg" or m == "dlss") and m or "dlss"
end

local function publish()
    mp.set_property(MODE_PROP, mode)
end

local function set_mode(target, quiet)
    if target ~= "fg" and target ~= "dlss" then return end
    if switching then
        if switching == target then return mp.osd_message("Enhancement Mode: switch in progress…", 2) end
        switch_gen = switch_gen + 1 -- cancel the pending switch (e.g. still waiting for focus)
        switching = false
    end
    if target == mode and reshade_preset == target then
        if not quiet then mp.osd_message("Enhancement Mode: " .. mode_label() .. " already active", 2) end
        return
    end
    if warming then
        -- The startup DLSS 5 warm-up must finish first; apply right after it
        mode = target
        save_mode()
        publish()
        return mp.osd_message("Enhancement Mode: " .. mode_label() .. " after warm-up", 2)
    end

    switching = target
    if not quiet then
        mp.osd_message("Switching to " .. (target == "fg" and "Frame Generation" or "DLSS 5") .. "…", 5)
    end

    if target == "fg" then
        -- Turn DLSS 5 off before lifting the cap, so the GPU never runs both at full rate
        switch_reshade("fg", function(ok)
            switching = false
            if not ok then
                return mp.osd_message("Frame Generation: ReShade did not switch presets (DLSS 5 kept)", 5)
            end
            mode = "fg"
            set_fps_cap(false)
            apply_props(FG_PROPS)
            save_mode()
            publish()
            mp.osd_message("RTX VSR 2x + " .. mode_label() .. " · DLSS 5 off", 4)
        end)
    else
        -- Cap and stop interpolating first, then bring DLSS 5 back
        mode = "dlss"
        apply_props(DLSS_PROPS)
        set_fps_cap(true)
        save_mode()
        publish()
        switch_reshade("dlss", function(ok)
            switching = false
            if ok then
                mp.osd_message("RTX VSR 2x + " .. mode_label(), 4)
            else
                mp.osd_message("DLSS 5: ReShade did not switch presets (press F13 in the player)", 6)
            end
        end)
    end
end

mp.register_script_message("set-mode", function(m) set_mode(m) end)

---------------------------------------------------------------------------
-- Smart content detection: pick the enhancement mode per file
--
--   live stream (no duration or not seekable, e.g. IPTV m3u8) -> Frame Generation
--   anything else (VOD, local files)                         -> DLSS 5
--
-- file-loaded fires once per file and after the on_preloaded hook, so a
-- detected "fg" while the DLSS 5 warm-up is running is deferred and applied
-- by end_warmup(). Manual menu toggles never re-fire this event.
-- URL hints catch seekable live streams too (HLS DVR/timeshift reports a
-- duration), while duration/seekable covers non-URL live sources. Bare
-- ".m3u8" is deliberately NOT a hint: VOD HLS playlists use it too.
local LIVE_HINTS = { "/live/", "rtmp://", "rtsp://", "srt://", "rtp://" }
mp.register_event("file-loaded", function()
    local url = (mp.get_property("stream-open-filename") or mp.get_property("path") or ""):lower()
    local live = mp.get_property_number("duration") == nil
        or not mp.get_property_bool("seekable", true)
    for _, hint in ipairs(LIVE_HINTS) do
        if url:find(hint, 1, true) then live = true break end
    end
    set_mode(live and "fg" or "dlss", true)
end)

---------------------------------------------------------------------------
-- Per-file setup and DLSS 5 warm-up

local function end_warmup(completed)
    if warmup_timer then
        warmup_timer:kill()
        warmup_timer = nil
    end
    if saved then
        mp.set_property_number("speed", saved.speed)
        mp.set_property_bool("mute", saved.mute)
        saved = nil
    end
    if warming then
        warming = false
        if completed and mode == "fg" then set_mode("fg", true) end
    end
end

function on_preloaded()
    end_warmup()
    filter_added, held = false, false

    if reshade_preset == "fg" then
        -- DLSS 5 is idle: no add-on stalls to absorb, so no warm-up and no cap
        apply_props(mode == "fg" and FG_PROPS or DLSS_PROPS)
        inject_vsr()
        return
    end

    -- DLSS 5 is active (always the case on the first file of a launch)
    apply_props(DLSS_PROPS)
    set_fps_cap(true)
    warming = true
    if not mp.get_property_bool("pause") then
        held = true
        mp.set_property_bool("pause", true)
    end
end

function on_playback_restart()
    if not held then return end
    held = false
    mp.add_timeout(SESSION_SECS, function()
        saved = { speed = mp.get_property_number("speed", 1), mute = mp.get_property_bool("mute") }
        mp.set_property_bool("mute", true)
        mp.set_property_number("speed", WARMUP_SPEED)
        mp.set_property_bool("pause", false)

        -- Count wall time spent actually playing (not waiting on the cache)
        local elapsed = 0
        warmup_timer = mp.add_periodic_timer(0.1, function()
            if mp.get_property_bool("core-idle") then return end
            elapsed = elapsed + 0.1
            if elapsed >= VSR_AT_SECS then inject_vsr() end
            if elapsed >= WARMUP_SECS then end_warmup(true) end
        end)
    end)
end

normalize_preset_path()
mode = load_mode()
publish()

mp.add_hook("on_preloaded", 50, on_preloaded)
mp.register_event("playback-restart", on_playback_restart)
mp.register_event("end-file", function() end_warmup(false) end)

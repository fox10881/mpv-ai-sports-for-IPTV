-- The IPTV provider load-balances every request to a different edge server, and each
-- edge is at a different point of the stream (unrelated EXT-X-MEDIA-SEQUENCE values).
-- FFmpeg's HLS demuxer re-requests the original URL on every playlist reload, lands on
-- a different edge, and jumps to older segments ("Media sequence changed unexpectedly").
-- Resolve the redirect once and pin the whole session to that edge.

local function resolve_redirect(url)
    local r = mp.command_native({
        name = "subprocess",
        args = { "curl.exe", "-s", "-o", "NUL", "-m", "5", "-w", "%{redirect_url}", url },
        capture_stdout = true,
        playback_only = false,
    })
    if r.status ~= 0 then return nil end
    local target = (r.stdout or ""):gsub("%s+$", "")
    return target ~= "" and target or nil
end

mp.add_hook("on_load", 10, function()
    local url = mp.get_property("stream-open-filename", "")
    if not url:match("^https?://.+/live/.+%.m3u8") then return end
    local target = resolve_redirect(url)
    if target then
        mp.msg.info("pinned live stream to edge " .. (target:match("^https?://[^/]+") or "?"))
        mp.set_property("stream-open-filename", target)
    end
end)

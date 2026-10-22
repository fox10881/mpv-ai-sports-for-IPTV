-- Live football scores + UI language for the right-click context menu.
--
-- The "Live Scores / النتائج المباشرة" submenu lists live and upcoming matches
-- (ESPN public scoreboard). Up to 3 matches can be tracked; all of them are
-- pinned together at the top-centre of the screen as ONE translucent ASS
-- overlay whose lines stack automatically, refreshed in the background.
-- A ✓ appears beside each tracked match and "Stop tracking" hides them all.
--
-- A top-level "Language / اللغة" item toggles the whole context menu between
-- English and Arabic: menu.conf is rewritten in place (every known title is
-- translated, commands and conditions are preserved), the live menu-data is
-- patched the same way, and the choice is persisted in ~~state/menu_lang.
--
-- select.lua reads ~~/menu.conf once, so updates go to two places:
--   * menu.conf (whole file when the language changes; only our block on
--     score refreshes), so it is correct on the next launch;
--   * the live "menu-data" property, so the open session sees it immediately.

local utils = require "mp.utils"
local options = require "mp.options"

local o = {
    refresh_interval = 30,
    timeout = 15,
    font = "Segoe UI",
    menu_conf = "~~/menu.conf",
    max_upcoming = 40,
    max_tracked = 3,
}
options.read_options(o, "live_scores")

local SCRIPT = mp.get_script_name()
local TRACKED_PROP = "user-data/live_scores/tracked"
local LANG_FILE = mp.command_native({ "expand-path", "~~state/menu_lang" })
local WHITE, GREY, GOLD, RED, SOFTRED = "&HFFFFFF&", "&HB4B4B4&", "&H00C8FF&", "&H3C3CFF&", "&H8080FF&"
local LANG_ITEM_TITLE = "Language / اللغة"
local LANG_CMD = "script-message-to " .. SCRIPT .. " toggle-lang"

-- FotMob's public feed: much faster than ESPN's scoreboard endpoint (~0.3s) and
-- not edge-cached as aggressively. %s is today's date (YYYYMMDD).
local API = {
    en = "https://www.fotmob.com/api/data/matches?date=%s&timezone=UTC&ccode3=USA&lang=en",
    ar = "https://www.fotmob.com/api/data/matches?date=%s&timezone=UTC&ccode3=SAU&lang=ar",
}
-- The matches feed always returns Latin names; the Arabic web frontend resolves
-- them client-side through this id->name dictionary (Participants = teams,
-- TournamentTemplates = leagues). Fetched once per session in Arabic mode.
local TM_URL = "https://www.fotmob.com/api/translationmapping?locale=ar"

local STR = {
    en = {
        menu_title = "Live Sc&ores",
        stop = "&Stop tracking", refresh = "&Refresh now",
        scale_up = "Zoom interface &in (+)", scale_down = "Zoom interface &out (-)",
        no_live = "No matches live right now", upcoming = "&Upcoming", more = "more",
        updated = "Updated", update_failed = "Update failed", loading = "Loading matches…",
        stale = "Live Scores: match list is out of date, refreshing…",
        hidden = "Live score overlays hidden", untracked = "Removed from tracking",
        ui_scale = "Overlay size", retrying = "update failed (%s), retrying",
        gone = "match no longer listed", vs = "vs",
        lang_set = "Menu language: English",
    },
    ar = {
        menu_title = "النتائج المباشرة",
        stop = "إيقاف التتبع", refresh = "تحديث الآن",
        scale_up = "تكبير الواجهة (+)", scale_down = "تصغير الواجهة (-)",
        no_live = "لا توجد مباريات مباشرة الآن", upcoming = "المباريات القادمة", more = "المزيد",
        updated = "آخر تحديث", update_failed = "فشل التحديث", loading = "جاري تحميل المباريات…",
        stale = "النتائج المباشرة: القائمة غير محدثة، جاري التحديث…",
        hidden = "تم إخفاء نتائج المباريات المتتبعة", untracked = "أُزيلت من التتبع",
        ui_scale = "حجم الواجهة", retrying = "فشل التحديث (%s)، جارٍ إعادة المحاولة",
        gone = "المباراة لم تعد مدرجة", vs = "ضد",
        lang_set = "لغة القائمة: العربية",
    },
}

-- Statuses the feed returns in English; shown in Arabic when lang=ar
local STATUS_AR = {
    HT = "استراحة", Halftime = "استراحة", FT = "انتهت", ["Full Time"] = "انتهت",
    ["Full-Time"] = "انتهت", Scheduled = "لم تبدأ", Postponed = "مؤجلة",
    Postp = "مؤجلة", Canceled = "ملغاة", Cancelled = "ملغاة", Canc = "ملغاة",
    Abandoned = "ملغاة", Abn = "ملغاة", Delayed = "متأخرة", Suspended = "موقوفة",
    ["Not started"] = "لم تبدأ", ["Walkover"] = "انسحاب", AET = "بعد الوقت الإضافي",
    ["Penalties"] = "ركلات الترجيح",
}
local STATUS_EN = {}
for en, ar in pairs(STATUS_AR) do STATUS_EN[ar] = en end

-- Every menu.conf title -> Arabic. Kept bidirectional: toggling back to English
-- reverses it exactly (mnemonic '&' included), so the file round-trips cleanly.
local EN2AR = {
    ["Pla&y"] = "تشغيل", ["Pa&use"] = "إيقاف مؤقت", ["&Stop"] = "إيقاف",
    ["Ope&n"] = "فتح", ["&Clipboard"] = "الحافظة", ["&History"] = "السجل",
    ["&Watch later"] = "المشاهدة لاحقاً", ["&Playlist"] = "قائمة التشغيل",
    ["&Tracks"] = "المسارات", ["P&layback"] = "التشغيل",
    ["&Display duration"] = "مدة العرض",
    ["1 second"] = "1 ثانية", ["2 seconds"] = "2 ثانية", ["5 seconds"] = "5 ثوانٍ",
    ["10 seconds"] = "10 ثوانٍ", ["Infinite"] = "بلا نهاية",
    ["Sp&eed"] = "السرعة",
    ["Set/clear &A-B loop points"] = "تعيين/مسح نقطتي التكرار A-B",
    ["&Loop file"] = "تكرار الملف", ["L&oop playlist"] = "تكرار القائمة",
    ["Seek &10 seconds forward"] = "تقديم 10 ثوانٍ",
    ["Seek 1&0 seconds backward"] = "إرجاع 10 ثوانٍ",
    ["Seek 10 &minutes forward"] = "تقديم 10 دقائق",
    ["Seek 10 m&inutes backward"] = "إرجاع 10 دقائق",
    ["&Reload"] = "إعادة التحميل", ["&Next file"] = "الملف التالي",
    ["&Previous file"] = "الملف السابق",
    ["N&ext sub-playlist"] = "القائمة الفرعية التالية",
    ["P&revious sub-playlist"] = "القائمة الفرعية السابقة",
    ["&Shuffle"] = "خلط", ["&Unshuffle"] = "إلغاء الخلط",
    ["&Chapters"] = "الفصول", ["&Editions/Titles"] = "الإصدارات/العناوين",
    ["&Video"] = "فيديو", ["&Track"] = "المسار", ["&Fill"] = "ملء",
    ["&Stretch"] = "تمديد", ["&Unscaled"] = "الحجم الأصلي", ["&Zoom"] = "تكبير",
    ["&Aspect ratio"] = "نسبة العرض", ["&Default"] = "الافتراضي",
    ["&Center"] = "توسيط",
    ["Rotate &clockwise"] = "تدوير مع عقارب الساعة",
    ["Rotate c&ounterclockwise"] = "تدوير عكس عقارب الساعة",
    ["&Deband"] = "إزالة التدرج", ["D&einterlace"] = "إزالة التشابك",
    ["&Screenshot"] = "لقطة شاشة",
    ["Screenshot &without subtitles"] = "لقطة بدون ترجمة",
    ["&Audio"] = "صوت", ["&Devices"] = "الأجهزة", ["&Channels"] = "القنوات",
    ["&Auto"] = "تلقائي", ["&Stereo"] = "ستيريو", ["&Mono"] = "أحادي",
    ["Increase &volume"] = "رفع الصوت", ["Decrease v&olume"] = "خفض الصوت",
    ["&Mute"] = "كتم",
    ["Increase d&elay"] = "زيادة التأخير", ["Decrease de&lay"] = "إنقاص التأخير",
    ["Increase &delay"] = "زيادة التأخير", ["Decrease d&elay"] = "إنقاص التأخير",
    ["&Subtitle"] = "ترجمة", ["&Visible"] = "إظهار",
    ["Scale &up"] = "تكبير", ["Scale d&own"] = "تصغير",
    ["&Lines"] = "الأسطر", ["&Secondary subtitle"] = "الترجمة الثانوية",
    ["&Window"] = "النافذة", ["&Fullscreen"] = "ملء الشاشة",
    ["&Border"] = "الإطار", ["&Title bar"] = "شريط العنوان",
    ["&Always on top"] = "دائماً في الأعلى", ["&Window scale"] = "حجم النافذة",
    ["&Screenshot window"] = "لقطة النافذة",
    ["V&iew"] = "عرض", ["&Playback statistics"] = "إحصائيات التشغيل",
    ["&File information"] = "معلومات الملف",
    ["&Key bindings"] = "اختصارات لوحة المفاتيح", ["&Time OSD"] = "شاشة العرض الزمنية",
    ["&Cycle OSC visibility"] = "تبديل ظهور OSC", ["&OSC layout"] = "تخطيط OSC",
    ["&Bottom bar"] = "الشريط السفلي", ["&Top bar"] = "الشريط العلوي",
    ["&Floating"] = "عائم", ["B&ox"] = "صندوق", ["&Slimbox"] = "صندوق نحيف",
    ["S&lim bottom bar"] = "الشريط السفلي النحيف",
    ["Sl&im top bar"] = "الشريط العلوي النحيف",
    ["P&rofiles"] = "الأنماط", ["T&ools"] = "أدوات",
    ["Copy &path"] = "نسخ المسار", ["Copy &subtitle"] = "نسخ الترجمة",
    ["Copy &title"] = "نسخ العنوان",
    ["&Hardware decoding"] = "فك التشفير بالعتاد",
    ["P&roperties"] = "الخصائص", ["&Console"] = "وحدة التحكم",
    ["&Edit config file"] = "تحرير ملف الإعدادات",
    ["Edit key &bindings"] = "تحرير الاختصارات",
    ["&Online documentation"] = "التوثيق عبر الإنترنت", ["S&upport"] = "الدعم",
    ["&Enhancement Mode"] = "وضع التحسين",
    ["&Frame Generation (120Hz)"] = "توليد الإطارات (120Hz)",
    ["&Quit"] = "خروج", ["Quit an&d save position"] = "خروج وحفظ الموضع",
}
local AR2EN = {}
for en, ar in pairs(EN2AR) do if en ~= ar then AR2EN[ar] = en end end

-- Language state
local function load_lang()
    local f = io.open(LANG_FILE, "rb")
    local v = f and f:read("*l")
    if f then f:close() end
    return (v == "en" or v == "ar") and v or "ar"
end
local lang = load_lang()
local function T() return STR[lang] end
local function api_url() return string.format(API[lang], os.date("%Y%m%d")) end
local function save_lang()
    local f = io.open(LANG_FILE, "wb")
    if f then f:write(lang) f:close() end
end

-- All titles that ever headed our score block (for block find/replace)
local OUR_TITLES = {
    [STR.ar.menu_title] = true, [STR.en.menu_title] = true,
    ["Live Sc&ores"] = true, ["Live Scores"] = true,
}
local QUIT_TITLES = { ["&Quit"] = true, ["خروج"] = true }

-- One overlay per slot, all along the top edge: 1 top-centre, 2 top-left,
-- 3 top-right
local MAXS = 3
local ovs, SLOT = {}, {
    { an = 8, x = 960 },  -- \an8 centre
    { an = 7, x = 30 },   -- \an7 left
    { an = 9, x = 1890 }, -- \an9 right
}
for i = 1, MAXS do
    ovs[i] = mp.create_osd_overlay("ass-events")
    ovs[i].res_x, ovs[i].res_y = 1920, 1080
end
local TOP_Y = 26

local matches, by_id, updated, last_error = {}, {}, nil, nil
local tracked, fetching = {}, false
local scale = 1.0
local TMAP, tm_fetching = nil, false -- {teams=..., leagues=...} once loaded

---------------------------------------------------------------------------
-- Helpers

local function esc(s)
    s = tostring(s or ""):gsub("\\", "\\\239\187\160"):gsub("{", "\\{"):gsub("[\r\n]", " ")
    return s
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- LTR-isolate clock-style details ("85'", "45:12") so RTL Arabic text doesn't
-- flip the minute and prime mark around
local function ltr(s)
    if tostring(s):match("^%d+['’:]") then return "\226\128\170" .. s .. "\226\128\172" end
    return s
end

-- Menu titles: no tabs/newlines (menu.conf separators) and literal '&' (mnemonics)
local function menu_text(s)
    s = tostring(s or ""):gsub("[\t\r\n]", " "):gsub("&", "&&")
    return s
end

-- ISO-8601 UTC ("2026-10-21T23:00:00Z") -> local "HH:MM"
local function local_time(iso)
    local y, mo, d, h, mi = tostring(iso or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
    if not y then return "" end
    local now = os.time()
    local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                        hour = tonumber(h), min = tonumber(mi), sec = 0, isdst = false })
    local now_utc = os.date("!*t", now)
    now_utc.isdst = false
    return os.date("%H:%M", t + os.difftime(now, os.time(now_utc)))
end

-- Order-independent serialisation, used to detect whether menu-data needs patching
local function canon(v)
    if type(v) ~= "table" then return utils.format_json(v) or "null" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. canon(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end

local function xlate_title(title)
    return (lang == "ar" and EN2AR or AR2EN)[title] or title
end

---------------------------------------------------------------------------
-- Data

-- Resolve display names: Arabic dictionary when available, else the feed's
-- Latin names. Called at parse time and re-applied when the map or language
-- changes after the fact.
local function resolve_names(m)
    local ar = lang == "ar" and TMAP
    m.home = (ar and TMAP.teams[m.home_id]) or m.home_en
    m.away = (ar and TMAP.teams[m.away_id]) or m.away_en
    m.league = (ar and TMAP.leagues[m.tid]) or m.league_en
end

-- FotMob status: { utcTime, started, ongoing, finished, cancelled, scoreStr,
--                  liveTime:{short,long}, reason:{short,long} }
local function to_match(league, ev)
    if type(ev) ~= "table" or ev.id == nil
        or type(ev.home) ~= "table" or type(ev.away) ~= "table" then return nil end
    local id = tostring(ev.id):gsub("[^%w%-]", "")
    if id == "" then return nil end
    local st = type(ev.status) == "table" and ev.status or {}
    local reason = type(st.reason) == "table" and st.reason or {}
    local live = type(st.liveTime) == "table" and st.liveTime or {}
    local state
    if st.cancelled then state = "post"
    elseif st.finished then state = "post"
    elseif st.started or st.ongoing then state = "in"
    else state = "pre" end
    local m = {
        id = id,
        league_en = league.name or "",
        home_en = ev.home.longName or ev.home.name or "?",
        away_en = ev.away.longName or ev.away.name or "?",
        home_id = tostring(ev.home.id or ""),
        away_id = tostring(ev.away.id or ""),
        tid = tostring(league.primaryId or league.parentLeagueId or league.id or ""),
        hs = trim(ev.home.score), as = trim(ev.away.score),
        state = state,
        date = tostring(st.utcTime or ev.timeTS or ""),
    }
    resolve_names(m)
    if state == "in" then
        m.detail = trim(live.short ~= "" and live.short or reason.short or "")
        m.detail = ltr(m.detail)
    elseif state == "pre" then
        m.detail = local_time(st.utcTime)
    else
        m.detail = trim(reason.short ~= "" and reason.short or "FT")
    end
    m.detail = m.detail:gsub("\226\128\142", "") -- strip LRM marks
    if lang == "ar" then m.detail = STATUS_AR[m.detail] or m.detail end
    if m.hs == "" then m.hs = "-" end
    if m.as == "" then m.as = "-" end
    return m
end

local function parse(body)
    local data = utils.parse_json(body or "")
    if type(data) ~= "table" or type(data.leagues) ~= "table" then error("unexpected API response") end
    local list, all = {}, {}
    for _, league in ipairs(data.leagues) do
        for _, ev in ipairs(type(league.matches) == "table" and league.matches or {}) do
            local m = to_match(league, ev)
            if m then
                all[m.id] = m
                if m.state == "in" or m.state == "pre" then list[#list + 1] = m end
            end
        end
    end
    table.sort(list, function(a, b)
        if (a.state == "in") ~= (b.state == "in") then return a.state == "in" end
        return tostring(a.date) < tostring(b.date)
    end)
    return list, all
end

-- Async fetch; cb(list, by_id) on success or cb(nil, nil, err) on failure. Never throws.
local function fetch(cb)
    mp.command_native_async({
        name = "subprocess",
        args = lang == "ar"
            and { "curl.exe", "-s", "-S", "-f", "-L", "--compressed", "-m", tostring(o.timeout),
                  "-A", "Mozilla/5.0 (mpv live_scores)",
                  "-H", "Accept-Language: ar,ar-SA;q=0.9,en;q=0.8", api_url() }
            or  { "curl.exe", "-s", "-S", "-f", "-L", "--compressed", "-m", tostring(o.timeout),
                  "-A", "Mozilla/5.0 (mpv live_scores)", api_url() },
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    }, function(success, res, err)
        if not success or type(res) ~= "table" or res.status ~= 0 then
            local msg = type(res) == "table" and trim(res.stderr) or ""
            if msg == "" then msg = (type(res) == "table" and res.error_string) or err or "request failed" end
            msg = msg:gsub("^curl: %(%d+%)%s*", "")
            return cb(nil, nil, msg:sub(1, 90))
        end
        local ok, list, all = pcall(parse, res.stdout)
        if not ok then
            mp.msg.warn("live_scores: " .. tostring(list))
            return cb(nil, nil, "unexpected API response")
        end
        cb(list, all)
    end)
end

---------------------------------------------------------------------------
-- Score overlays: one ASS event per slot, spread horizontally along the top

local function rounded_rect(x0, y0, x1, y1, r)
    x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.ceil(x1), math.ceil(y1)
    r = math.min(r, (x1 - x0) / 2, (y1 - y0) / 2)
    return string.format(
        "m %d %d l %d %d b %d %d %d %d %d %d l %d %d b %d %d %d %d %d %d " ..
        "l %d %d b %d %d %d %d %d %d l %d %d b %d %d %d %d %d %d",
        x0 + r, y0, x1 - r, y0, x1, y0, x1, y0, x1, y0 + r,
        x1, y1 - r, x1, y1, x1, y1, x1 - r, y1,
        x0 + r, y1, x0, y1, x0, y1, x0, y1 - r,
        x0, y0 + r, x0, y0, x0, y0, x0 + r, y0)
end

-- Draw `text` (one ASS event) with a translucent rounded box sized to its real bounds
local function draw_with_box(ov, text, alpha, pad, fallback)
    ov.data, ov.hidden, ov.compute_bounds = text, true, true
    local ok, b = pcall(ov.update, ov)
    ov.hidden, ov.compute_bounds = false, false
    if not (ok and type(b) == "table" and b.x0 and b.x1 and b.x1 > b.x0) then b = fallback end
    local box = string.format("{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H101010&\\1a&H%02X&\\p1}%s{\\p0}",
        alpha, rounded_rect(b.x0 - pad, b.y0 - pad * 0.6, b.x1 + pad, b.y1 + pad * 0.6, 14 * scale))
    ov.data = box .. "\n" .. text
    ov:update()
end

local function render_slot(i)
    local ov, m = ovs[i], tracked[i]
    if not m then return ov:remove() end
    local s = SLOT[i]
    local flash = m.flash_until and mp.get_time() < m.flash_until
    local status = m.state == "in"
        and string.format("{\\1c%s}●{\\1c%s} %s", RED, GREY, esc(m.detail))
        or esc(m.detail)
    local fs_l, fs_s, fs_e = 20 * scale, 36 * scale, 16 * scale
    local text = string.format(
        "{\\an%d\\pos(%d,%d)\\fn%s\\bord%.1f\\3c&H000000&\\3a&H40&\\shad0\\q2}" ..
        "{\\fs%.1f\\1c%s}%s  ·  %s\\N" ..
        "{\\fs%.1f\\b1\\1c%s}%s  {\\1c%s}%s{\\1c%s}  %s",
        s.an, s.x, TOP_Y, o.font, 1.4 * scale,
        fs_l, GREY, esc(m.league), status,
        fs_s, WHITE, esc(m.home), flash and GOLD or WHITE,
        m.state == "pre" and T().vs or (esc(m.hs) .. " - " .. esc(m.as)),
        WHITE, esc(m.away))
    if m.error then
        text = text .. string.format("\\N{\\fs%.1f\\b0\\1c%s}%s",
            fs_e, SOFTRED, esc(string.format(T().retrying, m.error)))
    end
    local est = (math.max(#m.home + #m.away + 12, #m.league + #m.detail + 4)) * 11 * scale
    local fb = { y0 = TOP_Y, y1 = TOP_Y + 64 * scale }
    if s.an == 8 then fb.x0, fb.x1 = s.x - est, s.x + est
    elseif s.an == 7 then fb.x0, fb.x1 = s.x, s.x + 2 * est
    else fb.x0, fb.x1 = s.x - 2 * est, s.x end
    draw_with_box(ov, text, 0x90, 22 * scale, fb)
end

local function render_scores()
    for i = 1, MAXS do render_slot(i) end
end

---------------------------------------------------------------------------
-- Context menu model, rendered both to menu-data items and to menu.conf lines

local function tracked_ids()
    local set = {}
    for _, m in ipairs(tracked) do set[m.id] = true end
    return set
end

local function match_title(m)
    local score = m.state == "pre" and T().vs or (m.hs .. " - " .. m.as)
    local when = m.state == "in" and ("● " .. m.detail) or m.detail
    return menu_text(string.format("%s     %s  %s  %s", when, m.home, score, m.away))
end

local function match_entry(m)
    return { title = match_title(m), shortcut = menu_text(m.league), id = m.id,
             cmd = "script-message-to " .. SCRIPT .. " track " .. m.id }
end

local function build_entries()
    local t = T()
    local entries = {
        { title = t.stop, cmd = "script-message-to " .. SCRIPT .. " stop", stop = true },
        { title = t.refresh, cmd = "script-message-to " .. SCRIPT .. " refresh" },
        { title = t.scale_up, cmd = "script-message-to " .. SCRIPT .. " scale-up" },
        { title = t.scale_down, cmd = "script-message-to " .. SCRIPT .. " scale-down" },
        { sep = true },
    }
    local live, upcoming = {}, {}
    for i = #tracked, 1, -1 do
        local tr = tracked[i]
        if not (by_id[tr.id] and (tr.state == "in" or tr.state == "pre")) then
            table.insert(live, 1, match_entry(tr)) -- keep finished/vanished tracked matches visible
        end
    end
    for _, m in ipairs(matches) do
        local list = m.state == "in" and live or upcoming
        list[#list + 1] = match_entry(m)
    end

    if #live == 0 then
        entries[#entries + 1] = { title = t.no_live, info = true }
    end
    for _, e in ipairs(live) do entries[#entries + 1] = e end

    if #upcoming > 0 then
        local sub = {}
        for i = 1, math.min(#upcoming, o.max_upcoming) do sub[i] = upcoming[i] end
        if #upcoming > o.max_upcoming then
            sub[#sub + 1] = { title = t.more .. " (" .. (#upcoming - o.max_upcoming) .. ")…", info = true }
        end
        entries[#entries + 1] = { sep = true }
        entries[#entries + 1] = { title = t.upcoming .. " (" .. #upcoming .. ")", submenu = sub }
    end

    entries[#entries + 1] = { sep = true }
    local footer = last_error and (t.update_failed .. ": " .. last_error)
        or (updated and (t.updated .. " " .. updated) or t.loading)
    entries[#entries + 1] = { title = menu_text(footer), info = true }
    return entries
end

local function to_menu_data(entries)
    local ids = tracked_ids()
    local items = {}
    for _, e in ipairs(entries) do
        local it
        if e.sep then
            it = { type = "separator" }
        elseif e.submenu then
            it = { title = e.title, type = "submenu", submenu = to_menu_data(e.submenu), state = {} }
        else
            it = { title = e.title, cmd = e.info and "ignore" or e.cmd, state = {} }
            if e.shortcut and e.shortcut ~= "" then it.shortcut = e.shortcut end
            if e.info or (e.stop and #tracked == 0) then it.state[#it.state + 1] = "disabled" end
            if e.id and ids[e.id] then it.state[#it.state + 1] = "checked" end
        end
        items[#items + 1] = it
    end
    return items
end

local function to_conf_lines(entries, depth, out)
    local indent = string.rep("\t", depth)
    for _, e in ipairs(entries) do
        if e.sep then
            out[#out + 1] = ""
        elseif e.submenu then
            out[#out + 1] = indent .. e.title
            to_conf_lines(e.submenu, depth + 1, out)
        elseif e.info then
            out[#out + 1] = indent .. e.title .. "\tignore\tdisabled=true"
        elseif e.stop then
            out[#out + 1] = string.format('%s%s\t%s\tdisabled=(p["%s"] or "") == ""',
                indent, e.title, e.cmd, TRACKED_PROP)
        elseif e.id then
            out[#out + 1] = string.format(
                '%s%s\t%s\tchecked=("," .. (p["%s"] or "") .. ","):find(",%s,",1,true) ~= nil',
                indent, e.title, e.cmd, TRACKED_PROP, e.id)
        else
            out[#out + 1] = indent .. e.title .. "\t" .. e.cmd
        end
    end
    return out
end

---------------------------------------------------------------------------
-- menu.conf: translate every line, then rewrite only our block

local function line_title(line) return line:match("^([^\t]*)") end

local function translate_conf_line(line)
    local indent, rest = line:match("^(%s*)(%S.-)%s*$")
    if not rest or rest == "" then return line end
    local title, tail = rest:match("^([^\t]*)\t(.*)$")
    if not title then title = rest end
    local nt = xlate_title(title)
    if nt == title then return line end
    return indent .. nt .. (tail and ("\t" .. tail) or "")
end

local function update_menu_conf(entries)
    local path = mp.command_native({ "expand-path", o.menu_conf })
    local f = io.open(path, "rb")
    local content = f and f:read("*a")
    if f then f:close() end
    if not content or content == "" then content = mp.get_property("default-menu") or "" end
    local nl = content:find("\r\n", 1, true) and "\r\n" or "\n"

    local lines = {}
    for line in (content .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
    while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end

    -- Drop our score blocks (any known title) and the language toggle line;
    -- translate everything else to the active language
    local kept = {}
    local i = 1
    while i <= #lines do
        local line = lines[i]
        local title = not line:match("^%s") and line_title(line) or nil
        if title and OUR_TITLES[title] then
            i = i + 1
            while i <= #lines and (lines[i] == "" or lines[i]:match("^%s")) do i = i + 1 end
        elseif title == LANG_ITEM_TITLE then
            i = i + 1 -- re-inserted below
        else
            kept[#kept + 1] = translate_conf_line(line)
            i = i + 1
        end
    end
    while #kept > 0 and kept[#kept] == "" do kept[#kept] = nil end

    -- Insert "Language / اللغة" + our score block just above the Quit group
    local pos = #kept + 1
    for k, line in ipairs(kept) do
        if not line:match("^%s") and QUIT_TITLES[line_title(line)] then pos = k break end
    end
    if pos > 1 and kept[pos - 1] == "" and pos <= #kept then pos = pos - 1 end

    local merged = {}
    for k = 1, pos - 1 do merged[#merged + 1] = kept[k] end
    merged[#merged + 1] = LANG_ITEM_TITLE .. "\t" .. LANG_CMD
    merged[#merged + 1] = ""
    for _, l in ipairs(to_conf_lines(entries, 1, { T().menu_title })) do
        merged[#merged + 1] = l
    end
    for k = pos, #kept do merged[#merged + 1] = kept[k] end

    local new_content = table.concat(merged, nl) .. nl
    if new_content == content then return end

    local tmp = path .. ".tmp"
    local out, err = io.open(tmp, "wb")
    if not out then return mp.msg.warn("live_scores: cannot write " .. tmp .. ": " .. tostring(err)) end
    out:write(new_content)
    out:close()
    os.remove(path)
    local ok, rerr = os.rename(tmp, path)
    if not ok then mp.msg.warn("live_scores: cannot replace menu.conf: " .. tostring(rerr)) end
end

---------------------------------------------------------------------------
-- Live menu-data: translate all items, insert the toggle, upsert our block

local desired_item, desired_canon = nil, nil

local function xlate_items(items)
    local changed = false
    for _, it in ipairs(items) do
        if type(it) == "table" then
            if type(it.title) == "string" then
                local nt = xlate_title(it.title)
                if nt ~= it.title then it.title = nt changed = true end
            end
            if it.submenu and not OUR_TITLES[it.title] then
                if xlate_items(it.submenu) then changed = true end
            end
        end
    end
    return changed
end

local function find_idx(data, titles)
    for i, it in ipairs(data) do
        if type(it) == "table" and titles[it.title] then return i end
    end
end

local function patch_menu_data()
    local data = mp.get_property_native("menu-data")
    if type(data) ~= "table" then return end
    local before = canon(data)

    xlate_items(data)

    -- Language toggle item (constant title in both languages)
    local lidx
    for i, it in ipairs(data) do
        if type(it) == "table" and it.title == LANG_ITEM_TITLE then lidx = i break end
    end
    if lidx then data[lidx].cmd, data[lidx].state = LANG_CMD, {}
    else
        local pos = find_idx(data, QUIT_TITLES) or #data + 1
        if pos > 1 and type(data[pos - 1]) == "table" and data[pos - 1].type == "separator" then
            pos = pos - 1
        end
        table.insert(data, pos, { title = LANG_ITEM_TITLE, cmd = LANG_CMD, state = {} })
    end

    if desired_item then
        local idx = find_idx(data, OUR_TITLES)
        if idx then
            data[idx] = desired_item
        else
            local pos = find_idx(data, QUIT_TITLES) or #data + 1
            if pos > 1 and type(data[pos - 1]) == "table" and data[pos - 1].type == "separator" then
                pos = pos - 1
            end
            table.insert(data, pos, desired_item)
        end
    end

    if canon(data) ~= before then mp.set_property_native("menu-data", data) end
end

local function rebuild_menu(write_conf)
    local entries = build_entries()
    desired_item = { title = T().menu_title, type = "submenu",
                     submenu = to_menu_data(entries), state = {} }
    desired_canon = canon(desired_item)
    patch_menu_data()
    if write_conf then
        local ok, err = pcall(update_menu_conf, entries)
        if not ok then mp.msg.warn("live_scores: menu.conf update failed: " .. tostring(err)) end
    end
end

-- select.lua republishes its own menu-data whenever a menu item's state changes
mp.observe_property("menu-data", "native", function() patch_menu_data() end)

---------------------------------------------------------------------------
-- Tracking

local function publish_tracked()
    local ids = {}
    for _, m in ipairs(tracked) do ids[#ids + 1] = m.id end
    mp.set_property(TRACKED_PROP, table.concat(ids, ","))
end

local function set_tracked_all(list)
    tracked = list or {}
    publish_tracked()
    render_scores()
    rebuild_menu(false)
end

local function add_tracked(m)
    if #tracked >= math.max(1, math.min(3, o.max_tracked)) then
        table.remove(tracked, 1) -- replace the oldest tracked match
    end
    m.error = nil
    m.added_at = mp.get_time()
    tracked[#tracked + 1] = m
end

local function merge_tracked(found, old)
    if old.state == "in" and (found.hs ~= old.hs or found.as ~= old.as) then
        found.flash_until = mp.get_time() + 20
        mp.add_timeout(20.5, render_scores)
    else
        found.flash_until = old.flash_until
    end
    found.added_at, found.error = old.added_at, nil
    return found
end

-- One-time fetch of FotMob's Arabic name dictionary; upgrades all names once it lands.
local function fetch_tm()
    if TMAP or tm_fetching or lang ~= "ar" then return end
    tm_fetching = true
    mp.command_native_async({
        name = "subprocess",
        args = { "curl.exe", "-s", "-S", "-f", "-L", "--compressed", "-m", tostring(o.timeout),
                 "-A", "Mozilla/5.0 (mpv live_scores)",
                 "-H", "Accept-Language: ar,ar-SA;q=0.9,en;q=0.8", TM_URL },
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    }, function(success, res)
        tm_fetching = false
        local d = success and type(res) == "table" and res.status == 0
            and utils.parse_json(res.stdout or "")
        if type(d) ~= "table" or type(d.Participants) ~= "table" then
            return mp.msg.warn("live_scores: translation map fetch failed")
        end
        TMAP = { teams = d.Participants,
                 leagues = type(d.TournamentTemplates) == "table" and d.TournamentTemplates or {} }
        local all = {}
        for _, m in ipairs(matches) do all[m.id] = m end
        for _, m in ipairs(tracked) do all[m.id] = m end
        for _, m in pairs(all) do resolve_names(m) end
        render_scores()
        rebuild_menu(true)
    end)
end

local function refresh()
    if fetching then return end
    fetching = true
    fetch_tm() -- kick the one-time Arabic dictionary fetch if needed
    fetch(function(list, all, err)
        fetching = false
        if list then
            matches, by_id, updated, last_error = list, all, os.date("%H:%M"), nil
            for i, t in ipairs(tracked) do
                if by_id[t.id] then
                    tracked[i] = merge_tracked(by_id[t.id], t)
                else
                    t.error = T().gone
                end
            end
        else
            last_error = err
            for _, t in ipairs(tracked) do t.error = err end
        end
        render_scores()
        rebuild_menu(list ~= nil)
    end)
end

mp.register_script_message("track", function(id)
    id = tostring(id)
    local m = by_id[id]
    if not m then
        mp.osd_message(T().stale, 3)
        return refresh()
    end
    for i, t in ipairs(tracked) do
        if t.id == id then
            table.remove(tracked, i) -- clicking a tracked match untracks it
            set_tracked_all(tracked)
            return mp.osd_message(T().untracked .. ": " .. (t.home or ""), 2)
        end
    end
    add_tracked(m)
    set_tracked_all(tracked)
end)

mp.register_script_message("stop", function()
    if #tracked == 0 then return end
    set_tracked_all({})
    mp.osd_message(T().hidden, 2)
end)

mp.register_script_message("refresh", refresh)

local function bump_scale(delta)
    scale = math.max(0.5, math.min(2.0, math.floor((scale + delta) * 100 + 0.5) / 100))
    render_scores()
    mp.osd_message(T().ui_scale .. ": " .. math.floor(scale * 100 + 0.5) .. "%", 2)
end
mp.register_script_message("scale-up", function() bump_scale(0.15) end)
mp.register_script_message("scale-down", function() bump_scale(-0.15) end)

mp.register_script_message("toggle-lang", function()
    lang = lang == "ar" and "en" or "ar"
    save_lang()
    -- Re-localise statuses and names of everything currently shown
    local smap = lang == "ar" and STATUS_AR or STATUS_EN
    for _, t in ipairs(tracked) do
        t.detail = smap[t.detail] or t.detail
        resolve_names(t)
    end
    for _, m in ipairs(matches) do resolve_names(m) end
    if lang == "ar" then fetch_tm() end
    render_scores()
    rebuild_menu(true) -- translate menu.conf + patch live menu-data
    mp.osd_message(T().lang_set, 3)
    refresh() -- re-fetch with the matching locale
end)

-- Debug/demo: pin three synthetic matches with very long names to check stacking
mp.register_script_message("_demo", function()
    tracked = {
        { id = "demo1", state = "in", detail = "67'", hs = "2", as = "1",
          league_en = "Qatar Stars League · الدرجة الأولى",
          home_en = "Wolverhampton Wanderers Wanderers FC", away_en = "Borussia Mönchengladbach United",
          home_id = "", away_id = "", tid = "" },
        { id = "demo2", state = "in", detail = "استراحة", hs = "0", as = "0",
          league_en = "Saudi Pro League",
          home_en = "نادي الاتحاد السعودي جدة", away_en = "نادي الهلال السعودي الرياض",
          home_id = "", away_id = "", tid = "" },
        { id = "demo3", state = "pre", detail = "22:30", hs = "-", as = "-",
          league_en = "CONMEBOL Sudamericana",
          home_en = "Club Atlético Independiente de Avellaneda", away_en = "Sportivo Luqueño",
          home_id = "", away_id = "", tid = "" },
    }
    for _, m in ipairs(tracked) do resolve_names(m) end
    publish_tracked()
    render_scores()
end)

mp.add_key_binding(nil, "dismiss", function() mp.commandv("script-message-to", SCRIPT, "stop") end)

mp.set_property(TRACKED_PROP, "")
rebuild_menu(true) -- apply the persisted language to menu.conf on startup too
refresh()
mp.add_periodic_timer(math.max(15, o.refresh_interval), refresh)

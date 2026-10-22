local utils = require 'mp.utils'
local os = require 'os'

-- تحديد مسار مجلد السجلات واسم الملف بناءً على الوقت والتاريخ
local debug_dir = "C:/mpv/debug"
local time_str = os.date("%Y-%m-%d_%H-%M-%S")
local log_path = debug_dir .. "/session_" .. time_str .. ".log"

-- تفعيل تسجيل الديبق العميق وتوجيهه للملف
mp.set_property("log-file", log_path)
mp.set_property("msg-level", "all=v")

-- وظيفة لتنظيف الجلسات القديمة والإبقاء على آخر 10 فقط
local function cleanup_old_logs()
    local files = utils.readdir(debug_dir, "files")
    if not files then return end

    local log_files = {}
    for _, file in ipairs(files) do
        if string.match(file, "^session_.*%.log$") then
            table.insert(log_files, file)
        end
    end

    -- ترتيب الملفات من الأقدم للأحدث
    table.sort(log_files)

    -- حذف الملفات الأقدم إذا زاد العدد عن 10
    while #log_files > 10 do
        local file_to_delete = debug_dir .. "/" .. log_files[1]
        os.remove(file_to_delete)
        table.remove(log_files, 1)
    end
end

-- تنفيذ التنظيف فور تشغيل المشغل
cleanup_old_logs()
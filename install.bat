@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo ============================================================
echo   mpv AI Sports ^& Cinema - AI/DLSS Binary Installer
echo   مثبّت ملفات الذكاء الاصطناعي و DLSS
echo ============================================================
echo.

REM --- sanity check: this script must live inside the mpv folder ---
if not exist "portable_config\mpv.conf" (
    echo [ERROR] portable_config\mpv.conf not found.
    echo Extract this repository INSIDE your mpv folder first, then run again.
    echo خطأ: استخرج ملفات المستودع داخل مجلد mpv أولاً ثم أعد التشغيل.
    pause
    exit /b 1
)

set "ZIP=%TEMP%\mpv-dlss5-base.zip"
set "XDIR=%TEMP%\mpv-dlss5-extract"

echo [1/4] Downloading ahaoboy/mpv-dlss5 nightly binaries (~160 MB)...
echo       جارٍ تحميل ملفات DLSS...
curl -L --fail -o "%ZIP%" "https://github.com/ahaoboy/mpv-dlss5/releases/download/nightly/mpv-dlss5.zip"
if errorlevel 1 goto :fail_download

echo [2/4] Extracting...
if exist "%XDIR%" rmdir /s /q "%XDIR%"
mkdir "%XDIR%"
tar -xf "%ZIP%" -C "%XDIR%"
if errorlevel 1 goto :fail_extract

REM The zip puts all binaries under externals\ . We copy that folder's
REM contents into the mpv root, EXCLUDING all *.ini files so our custom
REM ReShade.ini / ReShadePreset*.ini configs are never overwritten.
REM Top-level mpv.conf / input.conf / script.json in the zip are
REM upstream examples and are never copied.
echo [3/4] Merging binaries (protecting your .ini configs)...
if exist "%XDIR%\externals" (
    robocopy "%XDIR%\externals" "%~dp0." /E /XF *.ini >nul
) else (
    robocopy "%XDIR%" "%~dp0." /E /XF *.ini mpv.conf input.conf script.json menu.conf >nul
)
if errorlevel 8 goto :fail_copy

echo [4/4] Cleaning up...
del /q "%ZIP%" >nul 2>&1
rmdir /s /q "%XDIR%" >nul 2>&1

REM --- verify the critical binaries landed ---
if not exist "dxgi.dll" goto :fail_copy
if not exist "renodx-dlss5.addon64" goto :fail_copy
if not exist "dlss5-feed.addon64" goto :fail_copy

echo.
powershell -NoProfile -Command "Write-Host 'AI & DLSS Binaries downloaded and merged successfully! mpv AI Sports & Cinema is ready.' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host 'تم تحميل ودمج ملفات الذكاء الاصطناعي و DLSS بنجاح! المشغّل جاهز.' -ForegroundColor Green"
echo.
pause
exit /b 0

:fail_download
echo.
echo [ERROR] Download failed - check your internet connection.
echo فشل التحميل - تحقق من اتصال الإنترنت.
goto :cleanup

:fail_extract
echo.
echo [ERROR] Extraction failed - the zip may be corrupt. Re-run the script.
echo فشل الاستخراج - الملف تالف. أعد تشغيل السكربت.
goto :cleanup

:fail_copy
echo.
echo [ERROR] File copy failed - try running as Administrator.
echo فشل نسخ الملفات - جرّب التشغيل كمسؤول.
goto :cleanup

:cleanup
del /q "%ZIP%" >nul 2>&1
rmdir /s /q "%XDIR%" >nul 2>&1
pause
exit /b 1

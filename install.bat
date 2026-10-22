@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo ============================================================
echo   mpv AI Sports ^& Cinema - One-Click Installer
echo   المثبّت الشامل - نقرة واحدة
echo ============================================================
echo.

REM --- sanity check: this script must live where the repo was extracted ---
if not exist "portable_config\mpv.conf" (
    echo [ERROR] portable_config\mpv.conf not found.
    echo Extract the repository ZIP into an empty folder first, then run this file.
    echo خطأ: استخرج ملفات المستودع في مجلد فارغ أولاً ثم أعد التشغيل.
    pause
    exit /b 1
)

REM Windows bsdtar handles both .7z and .zip - call it explicitly so a
REM Git/MSYS tar earlier in PATH can't be picked up by mistake.
set "TAR=%SystemRoot%\System32\tar.exe"
set "DIR=%TEMP%\mpv-ai-install"

if exist "%DIR%" rmdir /s /q "%DIR%"
mkdir "%DIR%\mpv" "%DIR%\dlss5"

REM ================================================================
REM STEP 1 - base mpv player (zhongfly/mpv-winbuild, latest release)
REM ================================================================
if exist "mpv.exe" (
    echo [1/5] mpv.exe already present - skipping player download.
) else (
    echo [1/5] Downloading mpv player ^(zhongfly/mpv-winbuild latest^)...
    echo       جارٍ تحميل مشغّل mpv...

    REM Asset names carry a rolling build hash, so resolve the URL
    REM dynamically. Prefer the x86-64-v3 build, fall back to plain x86_64.
    set "MPV_URL="
    for /f "usebackq delims=" %%U in (`powershell -NoProfile -Command "try { $a=(Invoke-RestMethod 'https://api.github.com/repos/zhongfly/mpv-winbuild/releases/latest').assets; $u=($a | Where-Object { $_.name -match '^mpv-x86_64-v3-\d+-git-.*\.7z$' } | Select-Object -First 1 -ExpandProperty browser_download_url); if (-not $u) { $u=($a | Where-Object { $_.name -match '^mpv-x86_64-\d+-git-.*\.7z$' } | Select-Object -First 1 -ExpandProperty browser_download_url) }; $u } catch { '' }"`) do set "MPV_URL=%%U"
    if not defined MPV_URL goto :fail_download

    curl -L --fail -o "%DIR%\mpv.7z" "%MPV_URL%"
    if errorlevel 1 goto :fail_download

    echo       Extracting mpv...
    "%TAR%" -xf "%DIR%\mpv.7z" -C "%DIR%\mpv"
    if errorlevel 1 goto :fail_extract

    robocopy "%DIR%\mpv" "%~dp0." /E >nul
    if errorlevel 8 goto :fail_copy
    if not exist "mpv.exe" goto :fail_copy
)

REM ================================================================
REM STEP 2 - AI / DLSS / ReShade binaries (ahaoboy/mpv-dlss5 nightly)
REM ================================================================
echo [2/5] Downloading ahaoboy/mpv-dlss5 nightly binaries (~160 MB)...
echo       جارٍ تحميل ملفات DLSS...
curl -L --fail -o "%DIR%\mpv-dlss5.zip" "https://github.com/ahaoboy/mpv-dlss5/releases/download/nightly/mpv-dlss5.zip"
if errorlevel 1 goto :fail_download

echo [3/5] Extracting DLSS binaries...
"%TAR%" -xf "%DIR%\mpv-dlss5.zip" -C "%DIR%\dlss5"
if errorlevel 1 goto :fail_extract

REM The zip puts all binaries under externals\ . Copy into the mpv root
REM EXCLUDING all *.ini files so our custom ReShade.ini / ReShadePreset*.ini
REM are never overwritten. Top-level mpv.conf / input.conf / script.json
REM in the zip are upstream examples and are never copied.
echo [4/5] Merging AI binaries (protecting your .ini configs)...
if exist "%DIR%\dlss5\externals" (
    robocopy "%DIR%\dlss5\externals" "%~dp0." /E /XF *.ini >nul
) else (
    robocopy "%DIR%\dlss5" "%~dp0." /E /XF *.ini mpv.conf input.conf script.json menu.conf >nul
)
if errorlevel 8 goto :fail_copy

REM --- verify the critical binaries landed ---
if not exist "dxgi.dll" goto :fail_copy
if not exist "renodx-dlss5.addon64" goto :fail_copy
if not exist "dlss5-feed.addon64" goto :fail_copy

echo [5/5] Cleaning up temporary files...
del /q "%DIR%\mpv.7z" "%DIR%\mpv-dlss5.zip" >nul 2>&1
rmdir /s /q "%DIR%" >nul 2>&1

echo.
powershell -NoProfile -Command "Write-Host 'mpv player + AI & DLSS Binaries fully installed! mpv AI Sports & Cinema is ready.' -ForegroundColor Green"
powershell -NoProfile -Command "Write-Host 'اكتمل التثبيت! تم تحميل مشغّل mpv وملفات الذكاء الاصطناعي - المشغّل جاهز.' -ForegroundColor Green"
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
echo [ERROR] Extraction failed - the archive may be corrupt. Re-run the script.
echo فشل الاستخراج - الملف تالف. أعد تشغيل السكربت.
goto :cleanup

:fail_copy
echo.
echo [ERROR] File copy failed - try running as Administrator.
echo فشل نسخ الملفات - جرّب التشغيل كمسؤول.
goto :cleanup

:cleanup
rmdir /s /q "%DIR%" >nul 2>&1
pause
exit /b 1

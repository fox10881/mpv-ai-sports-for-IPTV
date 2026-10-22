# mpv AI Sports & Cinema Build

[English](#english-version) | [العربية](#النسخة-العربية)

---

<a name="english-version"></a>
## English Version

A portable mpv build tuned for **live IPTV football streams** on NVIDIA RTX hardware. It combines a massive anti-stutter caching pipeline, RTX Video Super Resolution, DLSS 5 via ReShade, native 120Hz frame generation, and a fully bilingual (English/Arabic) context menu with live match scores.

> **Requirements:** Windows 10/11, NVIDIA RTX GPU (VSR + DLSS features), mpv portable build.

### Installation

1. Download this repository (Code → Download ZIP) and extract it into an **empty folder** (e.g. `C:\mpv`).
2. Double-click **`install.bat`** — it automatically downloads the latest [mpv build](https://github.com/zhongfly/mpv-winbuild) **and** the AI/DLSS/ReShade binaries from [ahaoboy/mpv-dlss5](https://github.com/ahaoboy/mpv-dlss5) nightly, then merges everything without overwriting this repo's custom `.ini` configs.
3. Launch `mpv.exe` — done.

> This repo ships **config & scripts only** — no mpv or NVIDIA/DLSS binaries are hosted here; `install.bat` fetches them from their upstream projects at runtime. Requires a CPU with AVX2 (x86-64-v3, ~2013+).

### Features

#### 1. IPTV Anti-Stutter System

Built for unstable HLS live streams: a ~1 GiB demuxer cache with 30 s readahead, automatic reconnect (`reconnect`, `reconnect_streamed`, `reconnect_delay_max`), corrupt-packet discarding, live-edge startup (`live_start_index=-1`), and disabled resume/position saving so every channel always starts at the live edge.

![IPTV Anti-Stutter](assets/iptv_caching.png)

#### 2. AI Upscaling — RTX VSR + DLSS 5

RTX Video Super Resolution is **permanently active** via `d3d11vpp=scale=2:scaling-mode=nvidia`. On top of it, the DLSS 5 ReShade add-on provides AI upscaling. For streams above ~35 fps a `fps=30` cap filter is injected to keep GPU headroom and prevent the DLSS overload crash. The D3D11 hardware decoder is used with copy-back (`d3d11va-copy`) for stability with ReShade.

![AI Upscaling](assets/ai_upscaling.png)

#### 3. 120Hz Frame Generation

A second enhancement path uses mpv's native interpolation (`video-sync=display-resample`, `interpolation=yes`, `tscale=oversample`) with no fps cap — ideal for native 50/60 fps sports streams on a 120 Hz display. Frame Generation and DLSS 5 are **mutually exclusive** and switch on the fly from the right-click menu; ReShade presets are swapped via direct `PostMessage` to the mpv window (no focus needed).

![Frame Generation](assets/frame_gen.png)

#### 4. FotMob Live Scores Overlay

Track up to **3 live matches** while you watch: right-click → *Live Scores / النتائج المباشرة*, pick a match, and its score pins to the top of the screen in a horizontal side-by-side layout (top-left `\an7`, top-center `\an8`, top-right `\an9`). Data comes from FotMob (~0.3 s, refreshed every 30 s); Arabic mode resolves club and league names through FotMob's own `translationmapping` dictionary. Includes scale +/- controls, goal flash, toggle-to-untrack, and graceful error handling.

![FotMob Live Scores](assets/scores_showcase.jpg)

#### 5. Dynamic Context Menu

`live_scores.lua` programmatically manages `menu.conf` and the live `menu-data` property: the score submenu, checkmarks (✓) on tracked matches, the mutually exclusive **Enhancement Mode** submenu, and a `Language / اللغة` toggle that translates the **entire** context menu between English and Arabic mid-session — persisted across restarts.

![Context Menu](assets/context_menu.png)

#### 6. Audio Sync Fix

`display-resample` + `audio-buffer=1` keep A/V drift at ~0.000 s even on 50 fps streams at 120 Hz — verified with 0 dropped and 0 mistimed frames during live tests.

![Audio Sync](assets/audio_sync.png)

### Repository Layout

| Path | Purpose |
|---|---|
| `portable_config/mpv.conf` | Caching, D3D11 pipeline, VSR, sync settings |
| `portable_config/input.conf` | Keybindings (`Ctrl+d` dismiss, F13/F14 ignored) |
| `portable_config/menu.conf` | Generated context menu (bilingual, live scores, modes) |
| `scripts/vsr_delay.lua` | VSR/fps-cap filter chain + enhancement mode manager |
| `scripts/live_edge.lua` | Live-edge startup & resume suppression |
| `scripts/live_scores.lua` | FotMob scores overlay + menu engine + translations |
| `scripts/crash_logger.lua` | Session logging |
| `ReShade*.ini` | ReShade runtime + DLSS / Frame-Gen presets |
| `assets/` | Screenshots — drop your images here |

> **Note:** Binaries (mpv.exe, DLLs, `.addon64`), shader packs, caches, logs and runtime state are intentionally not tracked — this repo is config + scripts only.

---

<a name="النسخة-العربية"></a>
## النسخة العربية

نسخة محمولة من مشغّل mpv مُحسَّنة خصيصاً لـ **بث مباريات كرة القدم المباشرة (IPTV)** على بطاقات NVIDIA RTX. تجمع بين نظام تخزين مؤقت ضخم مضاد للتقطيع، وترقية الذكاء الاصطناعي عبر RTX VSR وDLSS 5، وتوليد الإطارات بمعدل 120Hz، وقائمة سياقية ثنائية اللغة (عربي/إنجليزي) مع نتائج المباريات المباشرة.

> **المتطلبات:** ويندوز 10/11، بطاقة NVIDIA RTX (لميزات VSR وDLSS)، نسخة mpv المحمولة.

### التثبيت

1. حمّل هذا المستودع (Code → Download ZIP) واستخرجه في **مجلد فارغ** (مثل `C:\mpv`).
2. انقر نقراً مزدوجاً على **`install.bat`** — سيحمّل تلقائياً أحدث [نسخة mpv](https://github.com/zhongfly/mpv-winbuild) **و** ملفات الذكاء الاصطناعي وDLSS وReShade من النسخة الليلية لمشروع [ahaoboy/mpv-dlss5](https://github.com/ahaoboy/mpv-dlss5)، ثم يدمج كل شيء دون استبدال ملفات `.ini` المخصصة في هذا المستودع.
3. شغّل `mpv.exe` — انتهى.

> هذا المستودع يحتوي **الإعدادات والسكربتات فقط** — لا تُستضاف هنا أي ملفات mpv أو NVIDIA/DLSS ثنائية؛ يقوم `install.bat` بجلبها من مشاريعها الأصلية عند التشغيل. يتطلب معالجاً يدعم AVX2 (x86-64-v3، ~2013 فأحدث).

### الميزات

#### 1. نظام منع التقطيع في IPTV

مصمم لبث HLS غير المستقر: ذاكرة demuxer بسعة ~1 جيجابايت مع قراءة مسبقة 30 ثانية، إعادة اتصال تلقائية، تجاهل الحزم التالفة، تشغيل من حافة البث المباشر، وتعطيل الاستئناف ليبدأ كل قناة دائماً من النقطة الحية.

![نظام منع التقطيع](assets/iptv_caching.png)

#### 2. الترقية بالذكاء الاصطناعي — RTX VSR وDLSS 5

تقنية RTX Video Super Resolution تعمل **بشكل دائم** عبر `d3d11vpp=scale=2:scaling-mode=nvidia`، وفوقها إضافة DLSS 5 في ReShade. للبث الذي يتجاوز ~35 إطاراً يُطبَّق حد أقصى `fps=30` للحفاظ على مساحة في المعالج الرسومي ومنع الانهيار. يُستخدم فك الترميز `d3d11va-copy` لضمان الاستقرار مع ReShade.

![الترقية بالذكاء الاصطناعي](assets/ai_upscaling.png)

#### 3. توليد الإطارات بمعدل 120Hz

مسار ثانٍ يعتمد الاستيفاء الأصلي في mpv (`display-resample` + `interpolation`) دون حد للإطارات — مثالي لبث 50/60 إطاراً على شاشة 120Hz. وضعا توليد الإطارات وDLSS 5 **متنافيان** ويتبدلان فورياً من قائمة النقر الأيمن، مع تبديل ملفات ReShade عبر `PostMessage` مباشرة إلى نافذة mpv دون الحاجة لتركيز النافذة.

![توليد الإطارات](assets/frame_gen.png)

#### 4. طبقة نتائج المباريات المباشرة (FotMob)

تابع حتى **3 مباريات مباشرة** أثناء المشاهدة: نقرة يمين ← *النتائج المباشرة* ← اختر مباراة، فيثبت نتيجتها أعلى الشاشة بتخطيط أفقي جنباً إلى جنب (يمين `\an7`، وسط `\an8`، يسار `\an9`). البيانات من FotMob (~0.3 ثانية، تحديث كل 30 ثانية)؛ الوضع العربي يترجم أسماء الأندية والبطولات عبر قاموس `translationmapping` الرسمي في FotMob. يشمل أزرار تكبير/تصغير، وميض عند الأهداف، وإيقاف التتبع بالنقر، ومعالجة آمنة للأخطاء.

![نتائج المباريات المباشرة](assets/scores_showcase.jpg)

#### 5. القائمة السياقية الديناميكية

سكربت `live_scores.lua` يدير `menu.conf` وخاصية `menu-data` برمجياً: قائمة النتائج الفرعية، علامات الصح (✓) بجانب المباريات المتتبعة، قائمة **وضع التحسين** المتنافية، وزر `Language / اللغة` الذي يترجم **القائمة كاملة** بين العربية والإنجليزية أثناء التشغيل — مع حفظ الاختيار بين الجلسات.

![القائمة السياقية](assets/context_menu.png)

#### 6. إصلاح مزامنة الصوت

`display-resample` مع `audio-buffer=1` يحافظان على انحراف صوت/صورة ~0.000 ثانية حتى على بث 50 إطاراً بمعدل عرض 120Hz — تم التحقق بصفر إطارات مسقطة وصفر إطارات متأخرة أثناء اختبارات مباشرة.

![مزامنة الصوت](assets/audio_sync.png)

### بنية المشروع

| المسار | الوظيفة |
|---|---|
| `portable_config/mpv.conf` | التخزين المؤقت، مسار D3D11، VSR، المزامنة |
| `portable_config/input.conf` | اختصارات المفاتيح |
| `portable_config/menu.conf` | القائمة السياقية المولّدة (ثنائية اللغة) |
| `scripts/vsr_delay.lua` | سلسلة مرشحات VSR + مدير وضع التحسين |
| `scripts/live_edge.lua` | التشغيل من حافة البث المباشر |
| `scripts/live_scores.lua` | طبقة النتائج + محرك القائمة + الترجمات |
| `scripts/crash_logger.lua` | تسجيل الأخطاء |
| `ReShade*.ini` | إعدادات ReShade وملفات DLSS/توليد الإطارات |
| `assets/` | لقطات الشاشة — ضع صورك هنا |

> **ملاحظة:** الملفات الثنائية (mpv.exe، DLLs، `.addon64`) وحزم الشيدر والذاكرة المؤقتة والسجلات وحالات التشغيل غير متتبعة عمداً — هذا المستودع يحتوي الإعدادات والسكربتات فقط.

# Roadmap

## Phase 1 — MQL5 Core Framework ✅ (این نسخه)
- [x] `IAnalyzer` interface + ارکستریتور در `.mq5` اصلی
- [x] `CBarClassifier`: Trend/Doji/Inside/Outside + H1/H2/H3+/L1/L2/L3+
- [x] `CSwingDetector`: فراکتال N-باری قابل‌تنظیم
- [x] `CTradingRangeDetector`: امتیازدهی رنج/ترند بر اساس overlap + displacement
- [x] `CPatternDetector`: Double Top/Bottom، Triangle، Wedge سه‌فشاره، ساختار HH/HL و LH/LL
- [x] `CChartRenderer`: جداسازی کامل رسم از منطق
- [x] README + دیاگرام کلاس‌ها + مستندسازی کامل

## Phase 2 — دقت و اعتبارسنجی 🟡 (این نسخه — بخش قابل‌کدنویسی انجام شد)
- [ ] بک‌تست دستی روی چند نماد/تایم‌فریم و مقایسه با تشخیص چشمی طبق کتاب بروکس — **بر عهده‌ی شما**، چون نیاز به اجرای واقعی روی MT5 دارد؛ از اسکریپت `PAB_UnitTests.mq5` برای regression check سریع استفاده کنید
- [x] اضافه‌کردن شرط "close محل" برای H2/L2 (Close Location Value + کم‌عمق‌تر بودن نسبت به پول‌بک قبلی → `ENUM_SIGNAL_QUALITY`، نمایش با `*` روی چارت)
- [x] پارامتری‌کردن ATR واقعی MT5 (`iATR`) — تزریق به `CTradingRangeDetector` از طریق `SetATRSeries()`، با fallback خودکار به میانگین ساده در نبود آن (مثلاً داخل unit test)
- [x] بهینه‌سازی ring buffer در `CBarClassifier`/`CSwingDetector` — هر دو حالا circular buffer با push در O(1) هستند
- [x] اضافه‌کردن unit-test harness به‌صورت اسکریپت MQL5 مستقل (`MQL5/Scripts/PAB_UnitTests.mq5`) — ۵ گروه تست روی هر آنالایزر

## Phase 3 — عمق تحلیلی بیشتر (وفادار به بروکس) ✅ (این نسخه)
- [x] Always-In state machine — `CAlwaysInTracker`: وضعیت چسبنده که فقط با شکست ساختاری (close فراتر از آخرین swing تأییدشده‌ی مخالف) عوض می‌شود، بر خلاف `ENUM_MARKET_STATE` که هر بار دوباره امتیازدهی می‌شود
- [x] تشخیص Breakout bar — `CBarClassifier::IsBreakoutBar()`: بار ترند قوی که هم CLV مطلوب دارد هم یک اکسترمم N-باری تازه می‌سازد
- [x] Climax bar / Exhaustion detection — `CBarClassifier::IsClimaxBar()`: رنج غیرعادی بزرگ (نسبت به میانگین/ATR) + بسته‌شدن ضعیف/بی‌تصمیم
- [x] Measured Move detection مستقل — `CMeasuredMoveDetector`: پروجکشن سبک سه-swing، **جایگزین موتور FM-indicator نیست** (به یادداشت scope داخل فایل نگاه کنید؛ یکپارچه‌سازی واقعی در Phase 5)
- [x] رفع یک باگ واقعی از Phase 1: `SPatternInfo`/`SMeasuredMoveInfo` به‌جای `barIndex` (که با اومدن بار جدید نامعتبر می‌شد) حالا `datetime` پایدار نگه می‌دارند — دقیقاً همان الگویی که `CSwingDetector` از اول درست پیاده کرده بود

## Phase 4 — پورت NinjaTrader (NinjaScript / C#) ✅ (این نسخه)
- [x] بازنویسی لایه‌ی `ChartRenderer` معادل با Draw.* API نینجاتریدر — `PabChartRenderer`، anchor زمانی از ابتدا (بدون باگ stale-index)
- [x] پورت کلاس‌های تحلیلی از MQL5 به C# — `PabBarClassifier`, `PabSwingDetector`, `PabTradingRangeDetector`, `PabPatternDetector`, `PabAlwaysInTracker`, `PabMeasuredMoveDetector`، همگی 1:1 با منطق MQL5
- [x] هم‌راستاسازی پارامترها بین دو پلتفرم — همان نام‌ها/مقادیر پیش‌فرض، فقط PascalCase
- [x] بهبود معماری با استفاده از قابلیت‌هایی که MQL5 ندارد: `PabRingBuffer<T>` جنریک واحد (به‌جای دو پیاده‌سازی تکراری)، `ATR()` sub-indicator به‌جای handle/CopyBuffer
- [ ] کامپایل و تست واقعی روی NinjaTrader 8 — **بر عهده‌ی شما**، چون این محیط NT8 SDK ندارد؛ به `NinjaTrader/README.md` نگاه کنید
- [ ] رنگ‌ها به‌عنوان NinjaScriptProperty input (فعلاً فقط در کد قابل تغییرند — نیاز به boilerplate سریالایز XML برای Brush)

## Phase 5 — یکپارچه‌سازی با FM-Indicator
- [ ] استفاده از `CTradingRangeDetector.State()` و `CAlwaysInTracker.State()` به‌عنوان context filter برای پروجکشن‌های Measured Move موجود در FM-indicator
- [ ] استفاده از `CPatternDetector` برای تأیید/رد زون‌های reversal موجود در FM-Indicator
- [ ] جایگزینی/کنار گذاشتن `CMeasuredMoveDetector` سبک این پروژه به نفع موتور کامل‌تر FM-indicator، و صرفاً پاس‌دادن context (always-in, breakout/climax) به آن
- [ ] مستندسازی مشترک بین دو ریپو (یا merge اختیاری در آینده)

## Phase 6 (اختیاری) — لایه‌ی ریسرچ
- [ ] Export تاریخچه‌ی سیگنال‌ها (H1/H2/L1/L2, patterns, range) به CSV برای تحلیل آماری بیرون از MT5
- [ ] معیارهای MAE/MFE برای هر نوع سیگنال، مشابه کاری که در FM-Indicator انجام شد

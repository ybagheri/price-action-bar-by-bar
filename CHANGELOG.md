# Changelog

## [1.0.0-nt8] - Phase 4 - 2026-09-24
### Added
- پورت کامل NinjaTrader 8 (NinjaScript/C#) در `NinjaTrader/PriceActionBarByBar.cs` — معماری 1:1 با نسخه‌ی MQL5: همان کلاس‌ها (`PabBarClassifier`, `PabSwingDetector`, `PabTradingRangeDetector`, `PabPatternDetector`, `PabAlwaysInTracker`, `PabMeasuredMoveDetector`, `PabChartRenderer`)
- بهبودهای معماری خاص C#: `PabRingBuffer<T>` جنریک واحد (جایگزین دو پیاده‌سازی تکراری در MQL5)، اتصال مستقیم به `ATR()` sub-indicator بدون handle/CopyBuffer
- `NinjaTrader/README.md`: راهنمای نصب، جدول تفاوت‌های معماری با MQL5، و محدودیت‌های شناخته‌شده‌ی این پورت

## [1.2.0] - Phase 3 - 2026-09-24
### Added
- `CAlwaysInTracker`: وضعیت always-in چسبنده (Long/Short/None) که فقط با شکست ساختاری آخرین swing مخالف عوض می‌شود
- `CBarClassifier`: فیلدهای جدید `isBreakoutBar` و `isClimax` روی هر بار، با پارامترهای قابل‌تنظیم (`InpBreakoutLookback`, `InpBreakoutClvMin`, `InpClimaxLookback`, `InpClimaxRangeMult`, `InpClimaxBodyRatioMax`)
- `CMeasuredMoveDetector`: پروجکشن سبک سه-swing، مستقل از FM-indicator (نگاه کنید به SCOPE NOTE داخل فایل)
- نشانگرهای جدید روی چارت: مثلث زرد برای breakout bar، "X" قرمز برای climax bar، خط نقطه‌چین آبی‌روشن برای هدف Measured Move
- وضعیت Always-In به پنل بالا-چپ اضافه شد
- ۳ گروه تست جدید در `PAB_UnitTests.mq5`: Breakout/Climax، Always-In، Measured Move

### Fixed
- باگ واقعی از Phase 1: `SPatternInfo` و `SMeasuredMoveInfo` به‌جای `barIndex` (که با اومدن هر بار جدید معنایش عوض می‌شد و رندر را روی بار اشتباه می‌فرستاد) حالا `datetime` پایدار ذخیره می‌کنند — همان الگوی درستی که `CSwingDetector` از ابتدا استفاده می‌کرد

## [1.1.0] - Phase 2 - 2026-09-23
### Added
- امتیاز کیفیت سیگنال برای بارهای پول‌بک (`ENUM_SIGNAL_QUALITY`): بر اساس Close Location Value و کم‌عمق‌تر بودن نسبت به پول‌بک قبلی در همان دنباله؛ روی چارت با `*` و اندازه‌ی فونت نمایش داده می‌شود
- اتصال ATR واقعی MT5 (`iATR`) به `CTradingRangeDetector` از طریق تزریق وابستگی (`SetATRSeries`)، با ورودی جدید `InpUseRealATR` و `InpATRPeriod`
- اسکریپت unit-test مستقل و بدون-چارت: `MQL5/Scripts/PAB_UnitTests.mq5` (۵ گروه تست: طبقه‌بندی بار، شمارش پول‌بک، swing، رنج، الگو)
- ورودی جدید `InpClvFavorableMin` برای تنظیم آستانه‌ی کیفیت سیگنال

### Changed
- ساختار ریپو به ساختار واقعی MT5 data-folder بازآرایی شد (`MQL5/Indicators`, `MQL5/Include/PriceActionBarByBar`, `MQL5/Scripts`)
- `CBarClassifier` و `CSwingDetector`: ring buffer از شیفت حافظه‌ی O(n) به circular buffer با push در O(1) تبدیل شد
- `SBarInfo` فیلد جدید `clv` (Close Location Value) و `signalQuality` گرفت

## [1.0.0] - Phase 1 - 2026-09-23
### Added
- ساختار پروژه‌ی OOP کامل: `IAnalyzer` interface + 5 کلاس اصلی (`CBarClassifier`, `CSwingDetector`, `CTradingRangeDetector`, `CPatternDetector`, `CChartRenderer`)
- طبقه‌بندی بار به سبک بروکس: Trend Bar (Bull/Bear) / Doji / Inside / Outside
- شماره‌گذاری پول‌بک H1/H2/H3+ و L1/L2/L3+ با state machine مستقل leg-tracking
- تشخیص swing high/low با فراکتال N-باری قابل‌تنظیم
- تشخیص رژیم بازار (Trading Range / Bull Trend / Bear Trend / Transition) بر اساس overlap و displacement
- تشخیص الگو: Double Top/Bottom، Triangle، Wedge سه‌فشاره (Rising/Falling)، ساختار HH/HL و LH/LL
- لایه‌ی رندرینگ مستقل با پنل وضعیت بازار، لیبل پول‌بک، مارکر swing، مستطیل رنج و annotation الگو
- README کامل با دیاگرام کلاس‌ها (Mermaid)، راهنمای نصب، پارامترها و راهنمای توسعه
- ROADMAP شش‌فازی شامل پورت NinjaTrader و یکپارچه‌سازی با FM-Indicator

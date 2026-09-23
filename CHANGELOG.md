# Changelog

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

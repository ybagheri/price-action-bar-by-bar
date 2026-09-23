# Roadmap

## Phase 1 — MQL5 Core Framework ✅ (این نسخه)
- [x] `IAnalyzer` interface + ارکستریتور در `.mq5` اصلی
- [x] `CBarClassifier`: Trend/Doji/Inside/Outside + H1/H2/H3+/L1/L2/L3+
- [x] `CSwingDetector`: فراکتال N-باری قابل‌تنظیم
- [x] `CTradingRangeDetector`: امتیازدهی رنج/ترند بر اساس overlap + displacement
- [x] `CPatternDetector`: Double Top/Bottom، Triangle، Wedge سه‌فشاره، ساختار HH/HL و LH/LL
- [x] `CChartRenderer`: جداسازی کامل رسم از منطق
- [x] README + دیاگرام کلاس‌ها + مستندسازی کامل

## Phase 2 — دقت و اعتبارسنجی
- [ ] بک‌تست دستی روی چند نماد/تایم‌فریم و مقایسه با تشخیص چشمی طبق کتاب بروکس
- [ ] اضافه‌کردن شرط "close محل" برای H2/L2 (فیلتر قدرت سیگنال، نه فقط شمارش)
- [ ] پارامتری‌کردن ATR واقعی MT5 (`iATR`) به‌جای `AverageRange` ساده در `PAB_Utils`
- [ ] بهینه‌سازی ring buffer در `CBarClassifier`/`CSwingDetector` (فعلاً push-front با شیفت O(n) است — روی تاریخچه‌ی خیلی طولانی در اولین لود می‌تواند کند باشد؛ گزینه: circular index به‌جای شیفت واقعی حافظه)
- [ ] اضافه‌کردن unit-test harness به‌صورت اسکریپت MQL5 مستقل (بدون چارت) برای هر آنالایزر

## Phase 3 — عمق تحلیلی بیشتر (وفادار به بروکس)
- [ ] Always-In state machine (تفکیک صریح‌تر بین ترند قوی/ضعیف)
- [ ] Signal-bar quality scoring (شبیه ratio table که در FM-Indicator ساخته شد)
- [ ] تشخیص Breakout bar با معیار قدرت (close near extreme, minimal opposite tail)
- [ ] Climax bar / Exhaustion detection
- [ ] Measured Move detection مستقل (یا اتصال مستقیم به موتور موجود در `ybagheri/FM-indicator`)

## Phase 4 — پورت NinjaTrader (NinjaScript / C#)
- [ ] بازنویسی فقط لایه‌ی `ChartRenderer` معادل با Draw.* API نینجاتریدر
- [ ] پورت کلاس‌های تحلیلی از MQL5 به C# (تغییرات نحوی جزئی، منطق یکسان)
- [ ] هم‌راستاسازی پارامترها بین دو پلتفرم برای رفتار یکسان

## Phase 5 — یکپارچه‌سازی با FM-Indicator
- [ ] استفاده از `CTradingRangeDetector.State()` به‌عنوان context filter برای پروجکشن‌های Measured Move
- [ ] استفاده از `CPatternDetector` برای تأیید/رد زون‌های reversal موجود در FM-Indicator
- [ ] مستندسازی مشترک بین دو ریپو (یا merge اختیاری در آینده)

## Phase 6 (اختیاری) — لایه‌ی ریسرچ
- [ ] Export تاریخچه‌ی سیگنال‌ها (H1/H2/L1/L2, patterns, range) به CSV برای تحلیل آماری بیرون از MT5
- [ ] معیارهای MAE/MFE برای هر نوع سیگنال، مشابه کاری که در FM-Indicator انجام شد

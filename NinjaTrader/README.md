# PriceActionBarByBar — NinjaTrader 8 Port (Phase 4)

این یک پورت معماری 1:1 از نسخه‌ی MQL5 (در `../MQL5`) به NinjaScript/C# برای NinjaTrader 8 است — همان مرزبندی کلاس‌ها، همان جداسازی تحلیل از رسم، فقط زبان و مدل به‌روزرسانی per-bar پلتفرم فرق می‌کند.

## نصب

1. NinjaTrader 8 را باز کنید → منوی **Tools → Edit NinjaScript → Indicator...** یا مستقیماً فایل را کپی کنید به:
   `Documents\NinjaTrader 8\bin\Custom\Indicators\PriceActionBarByBar.cs`
2. در NinjaScript Editor (که با کپی فایل و ری‌استارت یا با F5 داخل NinjaTrader باز می‌شود) کامپایل کنید: منوی **Compile** یا `F5`. اگر خطای کامپایل گرفتید، بخش «تفاوت‌های شناخته‌شده» پایین را چک کنید.
3. روی چارت: **Indicators → PriceActionBarByBar** را اضافه کنید.

## چرا یک فایل واحد؟

NinjaScript ایندیکاتورها را به‌صورت یک فایل مستقل کامپایل می‌کند. برخلاف MQL5 که `#include` بین فایل‌های جدا (`BarClassifier.mqh`, `SwingDetector.mqh`, ...) را طبیعی پشتیبانی می‌کند، پیاده‌سازی چندفایلی در NinjaTrader نیاز به بسته‌بندی به‌صورت **AddOn** (اسمبلی مجزا با ارجاع از ایندیکاتور) دارد. برای یک ایندیکاتور drop-in، همه‌چیز در `PriceActionBarByBar.cs` است، ولی با `#region` دقیقاً مطابق مرزبندی فایل‌های MQL5 سازمان‌دهی شده — اگر بعداً خواستید این کلاس‌ها را بین چند پروژه/ایندیکاتور دیگر هم به اشتراک بگذارید، تبدیل به یک AddOn (پروژه‌ی `NinjaTrader.Custom` جدا، یا یک DLL مرجع) گزینه‌ی درست است.

## تفاوت‌های معماری با نسخه‌ی MQL5

| موضوع | MQL5 | NinjaTrader (این پورت) |
|---|---|---|
| مدل به‌روزرسانی | `OnCalculate()` می‌تواند کل تاریخچه را دوباره پردازش کند (`prev_calculated`) | `OnBarUpdate()` دقیقاً یک‌بار per بار بسته‌شده، به ترتیب زمانی — بدون نیاز به منطق reprocessing |
| Ring buffer | دستی، در `CBarClassifier` و `CSwingDetector` هرکدام جدا پیاده شده (MQL5 جنریک ندارد) | یک `PabRingBuffer<T>` جنریک، در هر دو کلاس استفاده می‌شود |
| ATR واقعی | `iATR()` handle + `CopyBuffer()` هر بار | `ATR(period)` sub-indicator، مستقیم با `_atr[barsAgo]` قابل‌خواندن |
| Anchor رسم | زمانی (`datetime`) — بعد از رفع باگ Phase 3 | زمانی (`DateTime`) از همان ابتدا — این پورت هرگز باگ stale-index نسخه‌ی MQL5 Phase 1/2 را نداشت |
| رنگ‌ها | `input color ...` مستقیم | فیلدهای `public Brush` روی `PabChartRenderer` (به دلیل پیچیدگی سریالایز XML بره‌ای Brush در NinjaScriptProperty، رنگ‌ها به‌عنوان input در پنل تنظیمات expose نشده‌اند — مستقیماً در کد `PabChartRenderer` عوض کنید) |

## پارامترها

پارامترها دقیقاً معادل نسخه‌ی MQL5‌اند (همان نام‌ها با PascalCase به‌جای `Inp` prefix)، در پنل Properties ایندیکاتور زیر شش گروه: **Bar Classification، Swing Detection، Trading Range، Pattern Detection، Breakout Climax، Display**. برای توضیح هر پارامتر به README اصلی (`../README.md`) مراجعه کنید — مقادیر پیش‌فرض یکسان‌اند.

## محدودیت‌های این پورت

- **رنگ‌ها input نیستند** (توضیح در جدول بالا) — برای تغییر، فیلدهای `public Brush Color...` در کلاس `PabChartRenderer` را ویرایش کنید.
- **بدون unit-test harness جداگانه** — NinjaScript مکانیزم اسکریپت مستقل بدون چارت مثل MQL5 Scripts ندارد؛ برای اعتبارسنجی منطق، از **Strategy Analyzer** یا از اجرای ایندیکاتور روی داده‌ی تاریخی و مقایسه‌ی چشمی با خروجی MQL5 استفاده کنید.
- این پورت با `Calculate.OnBarClose` نوشته شده — یعنی هیچ رسمی روی بار در حال شکل‌گیری (تیک به تیک) انجام نمی‌شود، دقیقاً مثل رفتار نهایی نسخه‌ی MQL5 بعد از بسته‌شدن هر بار.
- تست کامپایل واقعی روی NinjaTrader 8 انجام نشده (این محیط NT8 SDK ندارد) — قبل از استفاده‌ی جدی، حتماً خودتان کامپایل و روی چند نماد/تایم‌فریم چک کنید؛ اگر خطای کامپایلی دیدید، برایم بفرستید تا رفعش کنیم.

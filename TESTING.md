# Testing

## Verified commands

MQL5 compile with the installed MetaEditor:

```powershell
& "C:\Program Files\Alpari MT5_2\metaeditor64.exe" /compile:"<path>\PriceActionBarByBar.mq5" /log:"<temp>\compile.log"
& "C:\Program Files\Alpari MT5_2\metaeditor64.exe" /compile:"<path>\PAB_UnitTests.mq5" /log:"<temp>\tests.log"
```

MetaEditor writes UTF-16 logs. Confirm `0 errors, 0 warnings`; process exit alone is insufficient.

Python:

```powershell
python -m unittest discover -s tests -v
python -m compileall -q pab_research tests
```

Run these from `research/`.

## Current evidence

- MQL5 indicator compile: 0 errors, 0 warnings.
- MQL5 harness compile: 0 errors, 0 warnings.
- Python tests: 6 passed.
- Python syntax compilation: passed.
- MQL5 harness runtime: not automatically executed in this environment.

## MQL5 harness coverage

The synthetic script contains 11 groups covering bar classification, pullback numbering, swings, range/trend, patterns, breakout/climax, Always-In, measured move, duplicate processing, stale range clearing, context, setup composition, and NO TRADE.

## Required expansion

- Execute the script in MT5 and archive raw Journal output.
- Add real indicator lifecycle tests for duplicate ticks and history reload.
- Add Strategy Tester fixtures using broker history.
- Add shared MQL5/NT golden fixtures.
- Add session and multi-timeframe tests when implemented.

No assertion should be reported as passed unless the runtime log shows it.

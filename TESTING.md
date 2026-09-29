# Testing

## Verified commands

MQL5 compile with the installed MetaEditor:

```powershell
$me   = "C:\Users\bagheri\AppData\Roaming\Alpari MT5_3\MetaEditor64.exe"
$data = "C:\Users\bagheri\AppData\Roaming\MetaQuotes\Terminal\0BCB0986AE04DC375BC47CA5AA358455"
Copy-Item ".\MQL5\Include\PriceActionBarByBar\*" "$data\MQL5\Include\PriceActionBarByBar\" -Force
Copy-Item ".\MQL5\Indicators\*" "$data\MQL5\Indicators\" -Force
Copy-Item ".\MQL5\Scripts\*"    "$data\MQL5\Scripts\" -Force
& $me "/compile:$data\MQL5\Indicators\PriceActionBarByBar.mq5" "/log:$env:TEMP\ind.log"
& $me "/compile:$data\MQL5\Scripts\PAB_UnitTests.mq5"           "/log:$env:TEMP\tests.log"
```

MetaEditor writes UTF-16 logs. Confirm `0 errors, 0 warnings`; process exit alone is insufficient.
The indicator uses `../Include/...` relative paths, so it must be compiled **from inside the
terminal data folder**, not from the repository. Copy the sources across on every MQL5 change:
a stale copy there silently tests old code.

Python, from `research/`:

```powershell
python -m pip install -e .          # once; makes `python -m pab_research` work
python -m pytest tests -q
python -m unittest discover -s tests -t .
python -m compileall -q pab_research tests
```

The editable install is required before the documented report entry point
works. Without it, `python -m pab_research` fails with `No module named
pab_research`, because an embeddable Python build ignores both `PYTHONPATH`
and the implicit current directory. `research/pyproject.toml` pins the
package list explicitly, so adding a stray directory under `research/`
cannot silently change what gets installed.

`unittest` discovery needs `-t .`; `research/tests/__init__.py` exists so the
repository root lands on `sys.path`. `pytest` works without extra flags for
the same reason, and `testpaths` in `pyproject.toml` means bare
`python -m pytest` from `research/` is equivalent to `python -m pytest tests`.

## Current evidence

- MQL5 indicator compile: 0 errors, 0 warnings.
- MQL5 harness compile: 0 errors, 0 warnings.
- MQL5 harness runtime: 54 passed, 0 failed (Alpari MT5_3 build 6230, EURUSD H1, 2026-09-29).
  Archived at `research/test_artifacts/mql5_harness_20260929.txt`.
- Python tests: 57 passed, `pytest` and `unittest` agree.
- Python syntax compilation: passed.

## MQL5 harness coverage

The synthetic script contains 12 groups covering bar classification, pullback numbering, swings,
range/trend, patterns, normalized pattern slopes, breakout/climax, Always-In, measured move,
duplicate processing, stale range clearing, context, setup composition, and NO TRADE.

## Running the harness

The harness is a Script, not an indicator, so it is launched by hand: open any chart, then run
`PAB_UnitTests` from Navigator > Scripts. Results go to the Experts journal. A startup config
(`/config:`) is not sufficient — if a terminal instance is already running, the config is
forwarded to it and ignored, so the terminal must be closed first. Automating this is roadmap
item 7.

## Required expansion

- Add real indicator lifecycle tests for duplicate ticks and history reload.
- Add Strategy Tester fixtures using broker history.
- Add shared MQL5/NT golden fixtures.
- Add session and multi-timeframe tests when implemented.

No assertion should be reported as passed unless the runtime log shows it.

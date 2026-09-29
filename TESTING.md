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
forwarded to it and ignored, so the terminal must be closed first.

## Headless historical export

`MQL5/Experts/PabEventExport.mq5` replays real broker history through the same
`CPabEngine` the chart uses and writes both the event CSV and the bar CSV the
research layer needs. It runs unattended from the MT5 Strategy Tester:

```powershell
$me   = "C:\Users\bagheri\AppData\Roaming\Alpari MT5_3\MetaEditor64.exe"
$term = "C:\Users\bagheri\AppData\Roaming\Alpari MT5_3\terminal64.exe"
$data = "C:\Users\bagheri\AppData\Roaming\MetaQuotes\Terminal\0BCB0986AE04DC375BC47CA5AA358455"

# 1. Copy sources into the terminal and compile inside Experts\ (the tester
#    prepends Experts\ to the Expert= path and will not look in Indicators\).
Copy-Item ".\MQL5\Include\PriceActionBarByBar\*" "$data\MQL5\Include\PriceActionBarByBar\" -Force
Copy-Item ".\MQL5\Experts\*" "$data\MQL5\Experts\" -Force
& $me "/compile:$data\MQL5\Experts\PabEventExport.mq5" "/log:$env:TEMP\export.log"

# 2. CRITICAL: the tester caches inputs per expert in a .set file and /config:
#    does NOT override it. Without this, stale values are silently reused.
Remove-Item "$data\MQL5\Profiles\Tester\PabEventExport.set" -Force -ErrorAction SilentlyContinue

# 3. Run. The terminal must be CLOSED, or the config is forwarded to the
#    running instance and ignored.
@"
[Tester]
Expert=PabEventExport.ex5
Symbol=EURUSD
Period=M5
Model=0
FromDate=2024.01.01
ToDate=2026.09.01
ShutdownTerminal=1
Deposit=10000
Optimization=0
Visual=0
"@ | Set-Content "$env:TEMP\export.ini" -Encoding ASCII
& $term "/config:$env:TEMP\export.ini"

# 4. Collect. In the Strategy Tester, relative file paths resolve to the
#    AGENT's data folder, not the terminal's.
$agent = "$env:APPDATA\MetaQuotes\Tester\0BCB0986AE04DC375BC47CA5AA358455\Agent-127.0.0.1-3000\MQL5\Files"
Copy-Item "$agent\pab_events.csv","$agent\pab_bars.csv" <somewhere>\ -Force
```

Traps found the hard way, all of which produce a silent wrong result rather
than an error:

- **The `.set` file.** MT5 writes `MQL5\Profiles\Tester\<Expert>.set` on
  every run and reuses it. A compiled-in default change is ignored. Delete it
  before each run, or read the inputs echoed at the top of the tester log to
  confirm what actually ran.
- **`Expert=` is resolved under `Experts\`.** Pointing it at
  `MQL5\Indicators\...ex5` fails with "EX5 not found", because the tester
  prepends the folder.
- **An indicator in `Experts\` gets no `OnCalculate`.** MT5 drives an Expert
  through `OnInit`/`OnTick`, so an indicator placed there writes its header
  and no rows. This is why the replay is a real EA.
- **Files land in the agent folder.** `MetaQuotes\Tester\<hash>\Agent-...-3000\MQL5\Files`,
  not under the terminal. Searching only the terminal folder finds nothing.
- **Tester inputs cannot be set from the CLI.** No `ExpertParameters` /
  `Parameters` spelling is honoured, so the replay's date range is
  compiled-in. An empty bound means "all available history".
- **Only cached history is available.** The window must lie inside what the
  broker has actually downloaded; the EA reports the range it got.

## Required expansion

- Re-run the harness after the Phase 16 engine refactor; the new assertions
  are compiled but unproven.
- Add real indicator lifecycle tests for duplicate ticks and history reload.
- Add shared MQL5/NT golden fixtures.
- Add session and multi-timeframe tests when implemented.

No assertion should be reported as passed unless the runtime log shows it.

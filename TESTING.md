# Testing

## Where the terminal actually is on this machine

The paths below are verified on 2026-09-30. They differ from the ones earlier
versions of this file carried, which pointed at `C:\Program Files\Alpari
MT5_3` and a `BazikadeStore` user. Neither exists here, and a command built
from them fails for a reason that has nothing to do with the code under test.

```powershell
$hash  = "0BCB0986AE04DC375BC47CA5AA358455"          # Alpari MT5_3 data folder
$me    = "C:\Users\bagheri\AppData\Roaming\Alpari MT5_3\MetaEditor64.exe"
$term  = "C:\Users\bagheri\AppData\Roaming\Alpari MT5_3\terminal64.exe"
$data  = "$env:APPDATA\MetaQuotes\Terminal\$hash"
$agent = "$env:APPDATA\MetaQuotes\Tester\$hash\Agent-127.0.0.1-3000"
```

The Alpari terminals are installed under `AppData\Roaming`, not `Program
Files`, and the data folder is reached through `MetaQuotes\Terminal\<hash>`
as usual. To confirm which install a hash belongs to, read
`origin.txt` out of the data folder. Other Alpari terminals
(`Alpari MT5`, `_2`, `_4`, `_5`) and an **Epic Pips MT5 Terminal** are also
present and are used for unrelated work, so any process check must compare the
executable path rather than the process name.

## Verified commands

MQL5 compile with the installed MetaEditor:

```powershell
$me   = "C:\Users\bagheri\AppData\Roaming\Alpari MT5_3\MetaEditor64.exe"
$data = "$env:APPDATA\MetaQuotes\Terminal\0BCB0986AE04DC375BC47CA5AA358455"
Copy-Item ".\MQL5\Include\PriceActionBarByBar\*" "$data\MQL5\Include\PriceActionBarByBar\" -Force
Copy-Item ".\MQL5\Indicators\*" "$data\MQL5\Indicators\" -Force
Copy-Item ".\MQL5\Scripts\*"    "$data\MQL5\Scripts\" -Force
& $me "/compile:$data\MQL5\Indicators\PriceActionBarByBar.mq5" "/log:$env:TEMP\ind.log"
& $me "/compile:$data\MQL5\Scripts\PAB_UnitTests.mq5"           "/log:$env:TEMP\tests.log"
```

MetaEditor writes UTF-16 logs. Confirm `0 errors, 0 warnings`; process exit
alone is insufficient. `MetaEditor64.exe /compile:... /log:...` returns exit
code **1 even on a clean compile**, so the log text is the only verdict.
It also holds the log file open for a moment after exiting, so a script that
reads the log immediately can fail with a sharing violation; retry, or read it
a second or two later. The indicator uses `../Include/...` relative paths, so
it must be compiled **from inside the terminal data folder**, not from the
repository. Copy the sources across on every MQL5 change: a stale copy there
silently tests old code.

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
- MQL5 export EA compile: 0 errors, 0 warnings.
- MQL5 unit-test Script compile: 0 errors, 0 warnings.
- MQL5 harness runtime, **headless**: 84 passed, 0 failed (Alpari MT5_3 build
  6230, 2026-09-29). Archived at
  `research/test_artifacts/mql5_harness_20260929_cost.txt`.
- Python tests: 124 passed, `pytest` and `unittest` agree.
- Python syntax compilation: passed.
- Costed multi-market export: 319,650 events across 4 markets and 2
  timeframes, all eight combinations measured, 0 excluded for missing bars,
  with break-even and assumed-spread re-pricing. Archived at
  `research/test_artifacts/study_costed_multi_market_2013.txt`.

Two earlier runs are kept for the record:
`mql5_harness_20260929_headless.txt` (69/0, before the cost group) and
`mql5_harness_20260929.txt` (54/0, the interactive run made before the
pipeline moved into `CPabEngine`). Both are superseded.

## MQL5 harness coverage

The suite contains 15 groups covering bar classification, pullback numbering,
swings, range/trend, patterns, normalized pattern slopes, breakout/climax,
Always-In, measured move, duplicate processing, stale range clearing, context,
setup composition, the NO TRADE contract, the failed-breakout definition, and
execution costs.

## Running the harness

The suite lives in `Include/PriceActionBarByBar/PabTests.mqh` and has two
entry points that call the same `RunAllPabTests()`:

- **Headless (preferred for evidence).** `Experts/PAB_HarnessEA.mq5` runs it
  in the Strategy Tester from the command line and writes a machine-readable
  `pab_harness.txt`. Takes about 0.15 seconds and needs nobody present.
- **Interactive.** `Scripts/PAB_UnitTests.mq5` runs from Navigator > Scripts
  on any chart, with output in the Experts journal.

There is deliberately only one copy of the assertions. Two copies drift, and a
suite that only runs when someone remembers is not a regression suite.

```powershell
$data = "$env:APPDATA\MetaQuotes\Terminal\0BCB0986AE04DC375BC47CA5AA358455"
$me   = "C:\Users\bagheri\AppData\Roaming\Alpari MT5_3\MetaEditor64.exe"
$term = "C:\Users\bagheri\AppData\Roaming\Alpari MT5_3\terminal64.exe"

Copy-Item ".\MQL5\Include\PriceActionBarByBar\*" "$data\MQL5\Include\PriceActionBarByBar\" -Force
Copy-Item ".\MQL5\Experts\*" "$data\MQL5\Experts\" -Force
& $me "/compile:$data\MQL5\Experts\PAB_HarnessEA.mq5" "/log:$env:TEMP\harness.log"

# Same .set trap as the export below: delete it or stale inputs are reused.
Remove-Item "$data\MQL5\Profiles\Tester\PAB_HarnessEA.set" -Force -ErrorAction SilentlyContinue

@"
[Tester]
Expert=PAB_HarnessEA.ex5
Symbol=EURUSD
Period=M5
FromDate=2026.06.01
ToDate=2026.06.05
ShutdownTerminal=1
Deposit=10000
Optimization=0
Visual=0
"@ | Set-Content "$env:TEMP\harness.ini" -Encoding ASCII
& $term "/config:$env:TEMP\harness.ini"

Get-Content "$env:APPDATA\MetaQuotes\Tester\AB546F93664BD7249969F5973868F430\Agent-127.0.0.1-3000\MQL5\Files\pab_harness.txt"
```

`pab_harness.txt` is rewritten on every run, never appended, so a stale PASS
cannot be mistaken for the current one. It carries the engine version and the
MT5 build, so an archived result says what produced it.

## Scope of the harness

Unit tests over the analyzer classes. They do **not** cover `CPabEngine`, the
indicator's `OnCalculate`, the chart renderer, or the event export. Those are
exercised only by the historical replay below, which covers the engine but not
the chart lifecycle. Chart lifecycle has no runtime test at all; that is an
open gap.

## Headless historical export

`MQL5/Experts/PabEventExport.mq5` replays real broker history through the same
`CPabEngine` the chart uses and writes both the event CSV and the bar CSV the
research layer needs. It runs unattended from the MT5 Strategy Tester:

```powershell
$me   = "C:\Users\bagheri\AppData\Roaming\Alpari MT5_3\MetaEditor64.exe"
$term = "C:\Users\bagheri\AppData\Roaming\Alpari MT5_3\terminal64.exe"
$data = "$env:APPDATA\MetaQuotes\Terminal\0BCB0986AE04DC375BC47CA5AA358455"

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
$agent = "$env:APPDATA\MetaQuotes\Tester\AB546F93664BD7249969F5973868F430\Agent-127.0.0.1-3000\MQL5\Files"
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
- **Only cached history is available, and which history is cached varies
  between runs.** The window must lie inside what the broker has actually
  downloaded, and the cached range shifts as the terminal refreshes. The EA
  prints the range it actually replayed, and an archived result must quote
  that line rather than the range you asked for. A `CopyRates` failure and a
  slow history download can both stall a run; cap the per-run timeout.
- **Runs can leave a stale `pab_harness.txt` or CSV behind.** The harness
  rewrites its summary each run, but the export only writes when the replay
  reaches the write loop, so a timed-out run can leave the previous run's
  output in place. Delete the target files before each run and check the
  timestamps, not just the presence.
- **The run takes minutes, not seconds, when history is not yet cached.** A
  multi-symbol study is eight separate terminal launches, because the
  tester's `Symbol` and `Period` are fixed at launch and running them in
  parallel would have each launch forward its config to whichever instance
  won the race. Observed per-run times were 13 s to 400 s depending on the
  download. A run that appears hung is usually downloading. On 2026-09-30,
  after the agent had been churning, single launches took **760 s to 1008 s**
  and a full 16-run sweep was not completable. Budget for it or narrow the
  study; do not read a timeout as a hang.
- **The tester's `FromDate`/`ToDate` do NOT bound the replay.** They drive the
  tick stream only. The exporter's own compiled-in `InpFromDate`/`InpToDate`
  are what select bars. A run configured for 2012-2014 with the exporter
  inputs left empty reported `EURUSD H4, 1546 bars from 2011-01-03 to
  2011-12-30`, a window that does not intersect the one requested. This is
  the single easiest way to believe you measured a period you did not.
- **`CopyRates` with `(start_time, stop_time)` returns 4401 in the tester.**
  ERR_NO_HISTORY, for a window it demonstrably holds: the same symbol and
  timeframe load fine through the positional `(start_pos, count)` overload.
  Measured for all four symbols at H4 and D1. The exporter therefore always
  uses the positional form and filters by timestamp itself. Do not "simplify"
  it back.
- **The agent does not hold every timeframe for every year, and which year it
  serves drifts between runs** on the same machine and broker. Unbounded, the
  same export served 2011, then 2010, then 2009 within one afternoon. Two
  timeframes measured minutes apart can be measuring different YEARS, which
  silently invalidates any comparison between them. Pin the window, then
  **read the range the run printed** and confirm all timeframes landed on the
  same period before comparing anything.
- **A matching log line is not a fresh log line.** The agent log accumulates
  every run of the day, so selecting the *first* line matching
  `"bars from"` returns an earlier run's range. Match on the
  `PabEventExport (SYMBOL,PERIOD)` tag and take the *last* match, or a study
  can report eight identical "results" that are one stale line read eight
  times.

## The Strategy Tester has no historical spread

This is the single most important limitation for anything cost-related, and it
is a property of the platform rather than of this project.

`MQL5/Experts/PabSpreadProbe.mq5` is the probe that establishes this, and
running it is how to re-check rather than re-argue the point. Its output is
archived at `research/test_artifacts/spread_probe_20260930.txt`.

```
PabEventExport: CopyBuffer copied -1 of 73752 spread values - error 4807
PabEventExport: costs ASSUMED (iSpread unavailable)
```

`iSpread` returns a valid handle inside the tester, but `CopyBuffer` on it
fails with error **4807** and yields no values. There is therefore no per-bar
historical spread to read in a headless replay. The chart path is unaffected:
`OnCalculate` receives a real `spread[]` array, so a live chart does measure
per-bar spread correctly.

Consequences, all of them deliberate:

- The exporter writes **blank** cost fields, not `0.0`. A blank reads as "no
  cost data"; a `0.0` would assert that trading was free, and would have
  produced a "net" expectancy that was really the gross one.
- The research report prints `n/a` for `costR` and `netR` and says GROSS in
  those words.
- `--break-even` and `--cost-scenario` exist because of this. Break-even
  solves for the cost from the sample itself, so no cost guess enters it.

To get a measured historical cost you need live forward collection, or tick
data exported from the terminal.

**Phase 20 tried the tick route and it does not work headlessly.** The reasons,
in the order they matter, with the probe that establishes each:

- `CopyTicksRange` in the tester is clipped to the tester's **current** time.
  Querying 2013.01.02..2013.01.03 from a run sitting at 2013.01.02 00:05
  returned exactly one tick: the one that woke `OnTick`.
- Real tick mode does not engage. The tester log for the real-ticks run says
  `EURUSD,M5: 3145 ticks, 842 bars generated`. Requesting real ticks made the
  tick count **132x worse** than the 416,989 of the generated run, which is
  what a fallback looks like, not an error.
- No per-day tick files exist under `bases\...\ticks\<symbol>\`. Only the
  `ticks.dat` index is there, so there is no cached tick history to
  reconstruct from.
- `ACCOUNT_TRADE_MODE` reads 0 inside the tester, so an agent cannot reach the
  broker to download ticks, and a `/config` run does not trigger the download
  the terminal UI would.

The bid and ask the tester supplies are therefore SYNTHESISED from OHLC and
the spread inside them is a tester **setting**. It is a plausible number that
says nothing about the broker, which is precisely why it must not be written
into a cost column as though it were measured.

One trap in that probe cost several compiles, because the error points at the
wrong argument. `CopyTicksRange`'s array is the **second** parameter and its
times are `ulong` **milliseconds**, not `datetime`:

```mql5
int CopyTicksRange(const string symbol_name,
                   MqlTick&    ticks_array[],
                   uint        flags = COPY_TICKS_ALL,
                   ulong       from_msc = 0,
                   ulong       to_msc   = 0);
```

A `datetime` there gives error 246 and a literal gives 137 "lvalue expected".

## Required expansion

- Add real indicator lifecycle tests for duplicate ticks and history reload.
  The harness does not reach OnCalculate or the renderer.
- Obtain a measured spread on a historical study. See above. This needs
  terminal UI interaction (the History dialog, or an indicator left running on
  a live chart); it is not reachable from the command line.
- Widen the swing study past one market and one year. Phase 20 covered EURUSD
  2009 only, because the tester agent could not serve the other three symbols
  on H4 and D1 in a common window.
- Add shared MQL5/NT golden fixtures.
- Add session and multi-timeframe tests when implemented.

No assertion should be reported as passed unless the runtime log shows it.

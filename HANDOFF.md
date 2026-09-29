# Handoff Summary - 2026-09-29

State of the repository after Phase 17. Both the measurement pipeline and the
regression suite now run unattended, and the first real measurement says the
engine has no edge.

## What this project is

An explainable MetaTrader 5 indicator that formalizes selected Price Action and
Al Brooks-style concepts as decision support for reading charts. It places no
orders, is not a trading system, and makes no profitability claim. The
measurement below confirms that caution was warranted.

MQL5 is the canonical engine. `research/` Python validates and measures what
MQL5 exported; it never re-derives a setup, and research-only algorithms must
be labelled separately.

## Verified state

| Check | Result | Evidence |
| --- | --- | --- |
| MQL5 indicator compile | 0 errors, 0 warnings | MetaEditor log, 2026-09-29 |
| MQL5 harness compile | 0 errors, 0 warnings | MetaEditor log, 2026-09-29 |
| MQL5 export EA compile | 0 errors, 0 warnings | MetaEditor log, 2026-09-29 |
| MQL5 harness runtime, **headless** | **69 passed, 0 failed** | `research/test_artifacts/mql5_harness_20260929_headless.txt` |
| Real headless export | 72,189 bars, 72,188 events, 10 s | `research/test_artifacts/real_export_eurusd_m5_2023.txt` |
| Python tests | 67 passed | `pytest` and `unittest` both agree |
| Python `compileall` | clean | `research/` |

**What the harness does not cover.** It exercises the analyzer classes, not
`CPabEngine`, not `OnCalculate`, and not the chart renderer. The chart path is
compile-verified and replay-verified but not lifecycle-verified: duplicate
ticks and history reload remain untested. That is the main remaining gap.

## The headline finding

EURUSD M5, Alpari-MT5-Demo, 2023-01-02 to 2023-12-29, 72,188 events:

- Resolved expectancy by setup type: **-0.06R to +0.04R**.
- Win rate by setup type: **38.2% to 55.4%**.
- Walk-forward degradation (OOS - IS): **+0.01R, +0.9 pp** — the two halves
  performed the same, not that either was good.
- `trend_pullback` is the worst at 38.2% win rate and `failed_breakout` the
  best at 55.4%, but neither expectancy is distinguishable from zero at this
  sample size.

All figures are **gross of spread, slippage, and commission**, because the
export does not carry them. Realistic costs on EURUSD M5 would consume
several times the measured edge, so the net is worse than shown.

The setups are also too tight to measure at M5: average bars-to-exit is 1.9 to
2.8 for every type except `breakout_follow_through` at 10.8, and roughly one
exit in five touches both the target and the stop inside a single bar
(`ambiguous`, unresolvable). A two-bar hold cannot separate skill from noise.

**Do not tune parameters to improve these numbers.** That is exactly the
overfitting the walk-forward split exists to detect, and one symbol on one
yearframe cannot support tuning.

## What Phase 16 and 17 changed

**One engine, two drivers.** `CPabEngine` owns the analyzer set and the
per-bar pipeline. The chart calls `Evaluate()` once per `OnCalculate`; the
replay calls it after every bar. `Evaluate()` takes the newest bar's close and
time as arguments instead of reading series index 1, which is what lets both
share it. ATR injection stays a separate call because the injected series is
indexed by position and is only valid at the instant it was copied.

**A headless replay.** `MQL5/Experts/PabEventExport.mq5` is a real EA, not a
Script and not the indicator, because MT5 only calls `OnCalculate` for files
built as indicators; a file in `Experts\` runs through `OnInit`/`OnTick` and
wrote a header with no rows. It places no orders.

**A headless regression suite.** The assertions moved into
`Include/PriceActionBarByBar/PabTests.mqh`, called by both
`Scripts/PAB_UnitTests.mq5` (interactive) and `Experts/PAB_HarnessEA.mq5`
(headless). There is one copy on purpose: two copies drift. The headless EA
writes `pab_harness.txt` with the verdict, engine version, MT5 build, and the
names of any failing assertions, rewritten every run so a stale PASS cannot
be mistaken for the current one. It finishes in about 0.15 seconds.

**Five defects that only a real export could expose.** None were findable from
the synthetic fixtures, because the fixtures did not resemble the real file:

1. A setup could be given a target on the wrong side of entry — a measured
   move adopted on direction alignment alone, with `reward/risk` taking an
   absolute value, so an unreachable target scored a healthy R:R. 6,025 of
   72,188 rows.
2. The resistance clamp could land the target on top of entry, which exports
   as the same printed price. A target must now clear entry by > 1 point.
3. A rejected setup leaked `direction=long` and stale levels. All NO TRADE
   exits now route through one `NoTrade()` helper.
4. `failed_breakout` fired on 74% of all bars, because the test only asked
   whether the bar sat below the swing high. 53,329 events before, 12,654
   after.
5. The research layer **could not read a real MQL5 export at all**:
   `csv.DictReader` defaults to comma while `FILE_CSV` defaults to tab, and
   `datetime.fromisoformat` rejects MQL5's dotted `TimeToString` output. Every
   test passed because the fixtures were written with Python's comma default.

**A sixth defect, found by the first headless harness run** rather than by
reading: `mmUsable` required only `targetPrice > entry`, so a measured move a
fraction of a point beyond entry was adopted and then rejected by the
one-point guard, turning a usable setup into NO TRADE. A too-close resistance
clamp already fell back to the baseline, so the two were inconsistent. This is
the clearest argument for having made the suite runnable unattended.

Plus a performance defect only real volumes expose: `evaluate_setup` sorted
the whole bar list per event, roughly five billion operations. `BarSeries`
builds the index once; the same report now takes 50 seconds.

`SETUP_TYPES` also did not mirror `SetupTypeLabel()`: it listed `"none"`, which
is a *direction*, and omitted `"no_trade"`, so every no-trade row was rejected.
A test now pins the set.

## Conventions that matter

- **Series order.** Analyzers expect index 0 to be the newest bar. Build
  fixtures oldest-first and displacement, net move, and overlap direction are
  silently inverted.
- **Series indexes are not stable.** They shift on every new bar and restart
  on a history reload. Anything that must survive across bars — slopes,
  pattern spans, fold boundaries — keys off timestamps.
- **Compare like with like.** A raw price quantity is not comparable across
  symbols or timeframes. Normalize to a fraction or ratio first.
- **Closed bars only.** Index 0 is forming and cannot produce a decision.
  Analyzer updates are idempotent by bar timestamp.
- **A NO TRADE row carries nothing.** No direction, no levels. Both the export
  schema and the research layer require this, and a stale entry on a declined
  row invites a reader to treat it as a proposal.
- **No unverifiable claims.** No assertion passes without a log. No win rate
  without a real export. No figure may include costs the export lacks.

## Honest gaps

- **The harness does not reach the chart lifecycle.** It covers the analyzers,
  not `CPabEngine`, `OnCalculate`, or the renderer. Duplicate ticks and
  history reload are unproven.
- Costs are absent from the export; every expectancy figure is gross.
- The setups resolve too fast to measure at M5.
- One symbol, one timeframe, one year. Multi-instrument and multi-regime
  validation are open.
- Higher-timeframe and session context are not implemented; single timeframe.
- NinjaTrader is never compiled, is not at parity, and its slope math still
  hardcodes adjacent x coordinates.
- Tester inputs cannot be set from the command line, so a replay's date range
  is compiled-in. Empty means "all available history".

## Next steps

`ROADMAP.md` holds the authoritative list. In order:

1. Repeat the real export on more symbols and timeframes, then re-run the
   walk-forward per instrument. One symbol and one year is not a study.
2. Add spread, slippage, and commission to the export so expectancy can be
   reported net. Until then no figure is comparable to a broker statement.
3. Decide whether the setups should be widened. At under three bars to exit
   the M5 measurement is not informative, and that is a design question
   rather than a parameter tweak.
4. Indicator lifecycle integration tests, so `OnCalculate` and the renderer
   have runtime evidence rather than compile evidence.
5. Higher-timeframe context using closed HTF bars.
6. Session/prior-day/overnight levels with broker-time assumptions.
7. NinjaTrader: apply the normalized slope and compile it.

## Environment notes

- Local repo: `E:\price-action-bar-by-bar`, remote
  `git@github.com:ybagheri/price-action-bar-by-bar.git`, default branch `main`.
- Two repo-local git settings exist and are required:
  `core.autocrlf=true` (otherwise a commit rewrites every file's line
  endings) and `core.sshCommand` pointing at Windows OpenSSH (Git otherwise
  uses its bundled MSYS ssh, which reads a different `known_hosts` and fails
  with "Host key verification failed").
- MT5 for this project is `C:\Users\bagheri\AppData\Roaming\Alpari MT5_3`, data
  folder `...\MetaQuotes\Terminal\0BCB0986AE04DC375BC47CA5AA358455`. Several
  other Alpari terminals run concurrently for unrelated projects, so process
  checks must match the executable path, not the process name.
- Compile check:
  `& "...\Alpari MT5_3\MetaEditor64.exe" /compile:"<file>.mq5" /log:"<log>"`
  MetaEditor writes UTF-16 logs; confirm `0 errors, 0 warnings` from the log
  text, not the process exit code. The indicator includes `../Include/...`,
  so it must be compiled from inside the terminal data folder.
- The headless replay recipe, including the `.set`-file trap and the agent
  output folder, is in `TESTING.md`. Every trap there produces a silently
  wrong result rather than an error.
- Python runs from `research/` after `python -m pip install -e .`. On this
  machine `python` is an embeddable build that ignores `PYTHONPATH` and the
  implicit current directory.

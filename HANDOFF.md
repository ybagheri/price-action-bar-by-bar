# Handoff Summary - 2026-09-29

State of the repository after Phases 13 and 14, intended as a cold-start brief
for whoever continues this work.

## What this project is

An explainable MetaTrader 5 indicator that formalizes selected Price Action and
Al Brooks-style concepts as decision support for reading charts. It places no
orders, is not a trading system, and makes no profitability claim.

MQL5 is the canonical engine. `research/` Python validates and measures what
MQL5 exported; it never re-derives a setup, and research-only algorithms must
be labelled separately.

## Verified state

| Check | Result | Evidence |
| --- | --- | --- |
| MQL5 indicator compile | 0 errors, 0 warnings | MetaEditor log, 2026-09-29 |
| MQL5 harness compile | 0 errors, 0 warnings | MetaEditor log, 2026-09-29 |
| MQL5 harness runtime | 54 passed, 0 failed | `research/test_artifacts/mql5_harness_20260929.txt` |
| Python tests | 46 passed | `pytest` and `unittest` both agree |
| Python `compileall` | clean | `research/` |

Runtime was on Alpari MT5_3 build 6230, EURUSD H1, 2026-09-29. Do not report
any assertion as passing unless a runtime log shows it.

## What was done in the last two phases

**Phase 13 - walk-forward and multi-instrument validation.** Added
`research/pab_research/validation.py`: chronological splitting of the event
stream into contiguous, non-overlapping, alternating in-sample / out-of-sample
blocks, pooled IS vs OOS comparison, and an expectancy and win-rate
degradation gap. Also `group_by_instrument` and `instrument_walk_forward`.
Exposed as `--walk-forward N`, `--walk-forward-per-instrument`, and
`--group instrument`.

**Phase 14 - normalized pattern slopes, and two provenance bugs.** Three real
defects, all found by reading rather than by a failing test:

1. `PATTERN_TRIANGLE` was unreachable. The triangle branch compared a raw
   price-per-bar-index slope against `InpConvergenceMin = 0.15`; on a 1.10
   instrument that slope is about 0.0025, so the condition could never hold.
2. Pattern slopes read `SSwingPoint.barIndex`, a series position that shifts
   every time a new bar arrives and restarts on a history reload, so two swings
   confirmed at different moments could yield different slopes for the same
   geometry.
3. The event export wrote engine version `1.30` while the compiled indicator
   reported `#property version "1.20"`. Since archived research results are
   keyed off that string, the two drifting apart is a provenance defect, not a
   cosmetic one.

Fixes: `CPabUtils::NormalizedSlopePerBar` measures a fraction of price per bar
from swing **timestamps**; `CPatternDetector` takes the chart period and uses
it; `InpConvergenceMin` now defaults to `0.00020` and means 0.020%/bar. Engine
version moved to a single `PAB_ENGINE_VERSION` macro used by the export, with
`#property version` kept in step at `1.40`. The export also gained `symbol` and
`period` columns, without which multi-instrument grouping has nothing to group
on; old files still load and those rows report as `unspecified` rather than
being dropped.

## Conventions that matter

- **Series order.** Analyzers expect index 0 to be the newest bar and
  `bars[n-1]` the oldest. Hand-built `SBarInfo` fixtures that are built
  oldest-first silently invert displacement, net move, and overlap direction.
  Route OHLC fixtures through `BuildSeries` in the harness.
- **Closed bars only.** Forming bar index 0 cannot produce a confirmed
  decision. Analyzer updates are idempotent by bar timestamp.
- **Series indexes are not stable.** Anything that must survive across bars —
  slopes, pattern spans, fold boundaries — keys off timestamps.
- **Compare like with like.** A raw price quantity is not comparable across
  symbols or timeframes. Normalize to a fraction or a ratio first.
- **Separation of concerns.** Detection stays separate from decision, risk,
  explanation, and rendering.
- **No unverifiable claims.** No assertion passes without a log. No win rate
  without a real export. Costs (spread, slippage, commission) are not in the
  export, so no reported figure may include them.

## Honest gaps

- **The reporting and walk-forward tooling has still never been run against a
  real event export.** It has been exercised on synthetic fixtures and on a
  clearly labelled synthetic CLI sample. There is no measured win rate or
  expectancy for this project, and none should be implied.
- Indicator lifecycle (duplicate ticks, history reload) has no runtime test.
- No Strategy Tester run, no broker-spread modeling, no multi-instrument study.
- Higher-timeframe and session context are not implemented; single timeframe only.
- The NinjaTrader port has never been compiled, is not at parity, and its slope
  math still hardcodes adjacent x coordinates, which is dimensionally wrong.
- Harness execution still needs a human to open a chart and run the script.
  A `/config:` startup file is not a substitute: if a terminal instance is
  already running, the config is forwarded to it and ignored.

## Next steps

`ROADMAP.md` holds the authoritative ordered list. In order:

1. **Run the tooling against a real export.** Set `InpExportEvents=true` on
   historical or replay data, let MT5 write the event CSV, export matching bar
   history as CSV with `open_time`/`high`/`low`, then run
   `python -m pab_research events.csv bars.csv --walk-forward 4`. Archive the
   output the way the harness output was archived. Do this across more than
   one symbol so the instrument grouping and the per-instrument walk-forward
   are exercised on real data rather than fixtures.
2. Configurable higher-timeframe context using closed HTF bars.
3. Session/prior-day/overnight levels with broker-time assumptions.
4. Apply the timestamp-normalized slope to NinjaTrader and compile it.
5. MQL5 indicator lifecycle integration tests.
6. Automate the harness run so evidence does not depend on a human.

## Environment notes

- Local repo: `E:\price-action-bar-by-bar`, remote
  `git@github.com:ybagheri/price-action-bar-by-bar.git`, default branch `main`.
- Compile check used in this session:
  `& "C:\Users\bagheri\AppData\Roaming\Alpari MT5_3\MetaEditor64.exe" /compile:"<file>.mq5" /log:"<log>"`
  MetaEditor writes UTF-16 logs; confirm `0 errors, 0 warnings` from the log
  text, not from the process exit code.
- MQL5 sources must be copied into the terminal data folder
  (`%APPDATA%\MetaQuotes\Terminal\<hash>\MQL5\`) before running, and a stale
  copy there will silently test old code. The indicator includes
  `../Include/...`, so it must be compiled from inside the data folder.
- Python runs from `research/`. On this machine `python` is an embeddable
  build, which ignores both `PYTHONPATH` and the implicit current directory:
  use `python -m unittest discover -s tests -t .`, or plain
  `python -m pytest tests -q`. See `TESTING.md`.
- The demo terminal logs in as Alpari-MT5-Demo. Do not disturb a running
  instance without asking.

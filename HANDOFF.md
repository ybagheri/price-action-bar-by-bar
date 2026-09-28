# Handoff Summary - 2026-09-28

State of the repository at commit `9eede75` (Phases 11 and 12), intended as a
cold-start brief for whoever continues this work.

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
| MQL5 indicator compile | 0 errors, 0 warnings | MetaEditor log |
| MQL5 harness compile | 0 errors, 0 warnings | MetaEditor log |
| MQL5 harness runtime | 41 passed, 0 failed | `research/test_artifacts/mql5_harness_20260928.txt` |
| Python tests | 27 passed | `pytest` and `unittest` both agree |
| Python `compileall` | clean | `research/` |

The MQL5 harness has now actually been executed in MT5 (Alpari MT5_2, EURUSD
M5). This closes the long-standing "compiled but never run" gap. Do not report
any assertion as passing unless a runtime log shows it.

## What was done in the last two phases

**Phase 11 - harness runtime (`62ccd55`).** Running the harness surfaced two
failing assertions. Both were test fixture defects, not engine defects:

- The pullback fixture expected `H1` on the bar whose high (1.1058) still
  exceeded the prior leg extreme (1.1057). That bar correctly resets the leg,
  so the first pullback is the following bar.
- The context fixture was built oldest-first, but `CContextAnalyzer` consumes
  series order (index 0 = newest closed bar). Inverted input made net move
  negative, so bullish displacement was never detected.

**Phase 12 - aggregate reporting (`9eede75`).** Added win rate, expectancy in
R, MFE/MAE, and bars-to-exit grouped by setup type or engine status, plus a
runnable `python -m pab_research EVENTS.csv BARS.csv` entry point.

Two genuine bugs were fixed along the way: a UTF-8 BOM on the first CSV column
name made the loader raise `KeyError: event_id` (loaders now read
`utf-8-sig`), and `python -m pab_research.report` emitted a `runpy` warning
because the package imported the module it was executing (moved to
`__main__.py`).

## Conventions that matter

- **Series order.** Analyzers expect index 0 to be the newest bar and
  `bars[n-1]` the oldest. Hand-built `SBarInfo` fixtures that are built
  oldest-first silently invert displacement, net move, and overlap direction.
  Route OHLC fixtures through `BuildSeries` in the harness.
- **Closed bars only.** Forming bar index 0 cannot produce a confirmed
  decision. Analyzer updates are idempotent by bar timestamp.
- **Separation of concerns.** Detection stays separate from decision, risk,
  explanation, and rendering.
- **No unverifiable claims.** No assertion passes without a log. No win rate
  without a real export. Costs (spread, slippage, commission) are not in the
  export, so no reported figure may include them.

## Honest gaps

- The reporting tool has **never been run against a real event export**. It
  has only been exercised on synthetic fixtures. There is no measured win rate
  or expectancy for this project, and none should be implied.
- Indicator lifecycle (duplicate ticks, history reload) has no runtime test.
- No Strategy Tester run, no broker-spread modeling, no walk-forward, no
  multi-instrument study.
- Higher-timeframe and session context are not implemented; single timeframe only.
- The NinjaTrader port has never been compiled and is not at parity.

## Next steps

`ROADMAP.md` holds the authoritative ordered list. The immediate next item
requires a human in front of MT5:

1. **Run the report against a real export.** Set `InpExportEvents=true` on
   historical/replay data, let MT5 write the event CSV, export matching bar
   history as CSV with `open_time`/`high`/`low`, then run
   `python -m pab_research events.csv bars.csv`. Archive the output the way
   the harness output was archived. This is the only way the reporting work
   becomes evidence rather than a tool.
2. Broader historical and multi-instrument validation with walk-forward
   separation.
3. Configurable higher-timeframe context using closed HTF bars.
4. Session/prior-day/overnight levels with broker-time assumptions.
5. Replace index-based pattern slopes with stable normalized measurements.
6. Shared fixtures and NinjaTrader 8 compilation.
7. MQL5 indicator lifecycle integration tests.

## Environment notes

- Local repo: `D:\Projects\price-action-bar-by-bar`, remote
  `git@github.com:ybagheri/price-action-bar-by-bar.git`, default branch `main`.
- Compile check used in this session:
  `& "C:\Program Files\Alpari MT5_2\metaeditor64.exe" /compile:"<file>.mq5" /log:"<log>"`
  MetaEditor writes UTF-16 logs; confirm `0 errors, 0 warnings` from the log
  text, not from the process exit code.
- MQL5 sources must be copied into the terminal data folder
  (`%APPDATA%\MetaQuotes\Terminal\<hash>\MQL5\`) before running, and a stale
  copy there will silently test old code. Verify hashes or copy after every
  MQL5 change.
- Python runs from `research/`.

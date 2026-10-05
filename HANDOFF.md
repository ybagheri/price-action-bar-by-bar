# Handoff Summary - 2026-10-05

State of the repository after Phase 24. Phases 21-24 added the lifecycle
test groups (authored, not yet executed), fixed the NinjaTrader port's
dimensionally-wrong slopes, hardened the research loaders against corrupt
bar files, and normalized line endings with CI for the Python layer.

## What this project is

An explainable MetaTrader 5 indicator that formalizes selected Price Action and
Al Brooks-style concepts as decision support for reading charts. It places no
orders, is not a trading system, and makes no profitability claim. The
measurement work below confirms that caution was warranted.

MQL5 is the canonical engine. `research/` Python validates and measures what
MQL5 exported; it never re-derives a setup, and research-only algorithms must
be labelled separately.

## Verified state

| Check | Result | Evidence |
| --- | --- | --- |
| MQL5 indicator compile | 0 errors, 0 warnings | MetaEditor log, 2026-09-29 |
| MQL5 harness compile | 0 errors, 0 warnings | MetaEditor log, 2026-09-30 |
| MQL5 export EA compile | 0 errors, 0 warnings | MetaEditor log, 2026-09-30 |
| MQL5 spread probe compile | 0 errors, 0 warnings | MetaEditor log, 2026-09-30 |
| MQL5 unit-test Script compile | 0 errors, 0 warnings | MetaEditor log, 2026-09-29 |
| MQL5 harness runtime, **headless** | **84 passed, 0 failed** | `research/test_artifacts/mql5_harness_20260930.txt` |
| Spread viability probe | **BLOCKED, with evidence** | `research/test_artifacts/spread_probe_20260930.txt` |
| Swing-timeframe study | 79,673 events, EURUSD 2009, M5/H1/H4/D1 | `research/test_artifacts/study_swing_timeframes_eurusd_2009.txt` |
| Costed multi-market study (prior) | 319,650 events, 4 markets, 2 timeframes, 8 combinations | `research/test_artifacts/study_costed_multi_market_2013.txt` |
| Python tests | **142 passed** | `pytest` and `unittest` both agree, 2026-10-05 |
| Python `compileall` | clean | `research/` |
| CI (Python) | on every push and PR | `.github/workflows/python.yml` |

**What the harness does not yet cover, and what Phase 21 changed.** The
runtime evidence still covers the analyzer classes, not `CPabEngine`, not
`OnCalculate`, and not the chart renderer. Phase 21 committed two lifecycle
groups — `TestEnginePipeline` (closed-bar gate, duplicate ticks,
history-reload determinism) and `TestRendererLifecycle` (stable object keys,
no duplication on redraw, `ClearAll`) — but they were authored on a machine
with no MetaEditor and are **not yet executed**. The 84/0 figure above is the
last *run* evidence. Running the harness is roadmap item 1.

**The environment notes at the end of this file were wrong until Phase 20.**
They pointed at `C:\Program Files\Alpari MT5_3` and a `BazikadeStore` user.
On this machine the Alpari terminals are installed under `AppData\Roaming`
and the user is `bagheri`. `TESTING.md` now carries verified paths. A second
broker, **Epic Pips MT5 Terminal**, is also installed and unused, which is
the obvious feed for roadmap item 3.

## Phases 21-24 in brief

- **Phase 21** — lifecycle integration test groups in the shared harness
  (`MQL5/Include/PriceActionBarByBar/PabTests.mqh`), which now includes
  `PabEngine.mqh` and `ChartRenderer.mqh`. Committed, not yet executed.
- **Phase 22** — the NinjaTrader port's pattern slopes are now a fraction of
  price per bar keyed off swing timestamps
  (`PabUtils.NormalizedSlopePerBar`), the direct port of the MQL5 fix. The
  old index-based slope was dimensionally wrong and the triangle branch could
  never fire on a 1.10 instrument. Not yet compiled (no NT8 SDK here).
- **Phase 23** — the research layer rejects bar files with duplicated
  `open_time` (both loaders), and `research/tests/test_loading.py` (18
  tests) pins that, the look-ahead invariant, event level-side validation,
  empty/header-only files, and `filter_window` bounds.
- **Phase 24** — `.gitattributes` (`* text=auto eol=lf`) ends the CRLF churn
  recorded below; `.github/workflows/python.yml` runs the suite on every
  push and PR. MQL5 is deliberately absent from CI: no runner hosts MetaEditor.

## Phase 20: the measured spread is blocked, and now we know why

Item 1 on the roadmap was to obtain a measured spread. It was investigated
before any code was written, and it is **not obtainable headlessly on this
machine**. `MQL5/Experts/PabSpreadProbe.mq5` is the probe; its output is
archived so the conclusion can be re-checked instead of re-argued.

What it established, in order of how much it matters:

- `iSpread` + `CopyBuffer` still fails with error **4807**. Phase 19's
  finding reconfirmed.
- `CopyTicksRange` cannot substitute. In the tester it is clipped to the
  tester's **current** time: a query for 2013.01.02..2013.01.03 from a run
  sitting at 2013.01.02 00:05 returned exactly one tick, the one that woke
  `OnTick`.
- Real tick mode does not engage. Requesting it made the tick count **132x
  worse** (3,145 against 416,989), and the log says `3145 ticks, 842 bars
  generated`. It degrades instead of failing loudly.
- There are no per-day tick files anywhere on this machine, only `ticks.dat`
  index files, so there is no cached tick history to reconstruct from.
- `ACCOUNT_TRADE_MODE` reads 0 inside the tester, so an agent cannot reach
  the broker to download ticks.

**The consequence is the important part.** The bid and ask the tester supplies
are synthesised from OHLC and the spread inside them is a tester **setting**.
The probe reports 35.0 points there and that number is real, but it is a
configuration value, not a measurement of Alpari. Writing it into a cost
column as "measured" is the exact failure this project exists to prevent, so
the blank cost columns from Phase 19 are left alone.

Live forward collection remains possible in principle; the terminal *is*
authorized to Alpari-MT5-Demo. It needs a chart left running for days or
weeks, it cannot be driven from the command line, and it cannot cover 2009
retrospectively. It is therefore not a substitute for a measured historical
spread, only a measurement of a different period.

## Phase 20: the swing timeframes, measured for the first time

EURUSD, 2009, all four timeframes over the **same** window, engine 1.50 and
an identical parameter fingerprint to Phase 19, so the only variable is the
timeframe.

| timeframe | events | resolved | win% | gross R | break-even | bars to exit |
| --- | --- | --- | --- | --- | --- | --- |
| M5 | 71,816 | 31,799 | 47.7% | +0.003 | 0.0001% of price | 2.5 |
| H1 | 6,071 | 2,708 | 47.6% | +0.035 | 0.0060% of price | 2.8 |
| H4 | 1,531 | 678 | 42.6% | **-0.068** | n/a, gross < 0 | 2.7 |
| D1 | 255 | 122 | 48.4% | +0.115 | 0.1152% of price | 3.3 |

Walk-forward, 4 chronological folds, decisions never crossing a boundary:

| timeframe | in-sample | out-of-sample | degradation |
| --- | --- | --- | --- |
| M5 | -0.00R | +0.01R | +0.01R |
| H1 | +0.01R | +0.06R | +0.05R |
| H4 | -0.10R | -0.03R | +0.07R |
| D1 | +0.30R | **-0.09R** | **-0.39R** |

**No timeframe shows an out-of-sample edge.** H4 is negative in both halves
and in 3 of 4 folds. H4 is also the one group whose gross expectancy is
negative *before any cost is applied*, so break-even is undefined and no cost
model can rescue it. That is a stronger negative than Phase 19's, which at
least had a positive gross figure to erode.

**D1 is the trap in this study and is reported so it cannot be misused.**
+0.115R is the largest positive gross figure anywhere in this project, and it
is entirely in-sample: +0.30R becomes -0.09R out of sample, a **-0.39R**
degradation on 122 resolved outcomes. The report prints `reliable: yes` for
D1, but that flag only means the resolved count cleared a threshold. It says
nothing about whether the edge is real, and on this evidence it is not.

One number is worth a note because it cuts against the roadmap. At 0.001% of
price, H1 is still **positive** (+0.025R) where M5 is already clearly negative
(-0.038R), because H1's wider stop makes the same cost a smaller fraction of
R. That is not a reason to prefer H1: H1's break-even is 0.0060% of price, it
is already negative at 0.005%, and this is one market in one year.

## Roadmap item 5 does not reproduce

Item 5 was predicated on "H1 setups take 24-34 bars to exit with slightly
negative expectancy, suggesting the stop and target logic is not doing
anything on that timeframe." **On this sample that does not happen.** H1 exits
in 2.8 bars and is +0.035R gross. Bars-to-exit is 2.4 to 3.3 on every
timeframe *including D1*, under the same engine and parameters that produced
Phase 19's 28.9-bar H1 figure. Same market, different year, so the long
holding period is a property of the 2013 sample rather than of H1 setup
construction.

That does not make the 2013 figure wrong. It makes it unreproducible, which
means it should not be cited as a structural fact about H1.

The mechanism, recorded without changing anything:

- `evaluate_setup` in `research/pab_research/outcomes.py` has **no maximum
  holding horizon**. It walks forward until the target or invalidation is
  touched, so `bars_to_exit` is purely a consequence of where the levels sit.
- The baseline target is `entry +/- 2.0 * bar.range`
  (`DecisionEngine.mqh:166`) - two times the range of the single bar the
  decision was taken on - and is then clamped toward context resistance or
  support (`DecisionEngine.mqh:185-201`) before the 1.50 reward/risk gate.
- Because the target is anchored to one bar's range, the holding period in
  **bars** is roughly timeframe-invariant, which is what 2.4-3.3 shows. The
  holding period in **time** is not: 2.5 M5 bars is about 12 minutes, 3.3 D1
  bars is about a week. No figure reported anywhere in this project counts
  hours rather than bars, so that asymmetry has been invisible until now.

**No threshold was tuned in response to any of this.**

## A fixed 1:2 payoff does not rescue it, and the trap is worth knowing

A reader's most likely next step is to ask what happens with a fixed 1:2
payoff and 0.5% account risk, so `research/pab_fixed_rr.py` answers it
directly. It replaces only the target with `entry +/- 2 * risk`, keeps the
engine's own stop, and re-simulates. Research-only, labelled as such.

The number that matters is the **win rate**, because 1:2 breaks even at 33.3%
and the engine's own R:R delivers about 47%:

| | engine's own R:R | 1:2 win rate | 1:2 gross R | balance, no cost | at 0.001% spread |
| --- | --- | --- | --- | --- | --- |
| M5 | 47.7% | 34.1% | +0.022 | +64.5%, DD 58% | **-79.5%** |
| H1 | 47.6% | 32.8% | -0.017 | +4.7%, DD 19% | +1.0% |
| H4 | 42.6% | 30.6% | -0.082 | -10.0%, DD 15% | -10.5% |
| D1 | 48.4% | 33.1% | -0.008 | +2.9% on 42 trades | +2.9% |

**Reusing the 47.7% in a 1:2 formula claims +0.43R and is wrong.** Widening the
target from ~1.7R to 2R means fewer targets are reached, and the win rate a 1:2
target actually produces is 34.1%. The shortcut overstates by +0.41R to
+0.46R, and it overstates in the profitable direction every time.

The 1:2 win rate lands between 30.6% and 34.1% on **every** timeframe from M5
to D1, essentially on the 33.3% the payoff needs. That regularity is the real
result: at 1:2 the engine is very nearly a fair coin with a 2:1 bet, and the
near-zero gross expectancy is structural rather than noisy.

The M5 +64.5% is not a result and must never be quoted alone. It assumes
trading is free. At 0.001% of price - below any retail FX spread - the same
curve is **-79.5%**, and at 0.005% it is a total wipeout. The per-trade edge
is +0.014R while that same 0.001% spread costs 0.0156R, so cost is about
**twice** the edge. That is Phase 19's result expressed as an account curve.
The 58% drawdown is a second, independent reason not to read the gross figure
as an outcome. Archived at
`research/test_artifacts/fixed_rr_0p5pct_eurusd_2009.txt`.

## Why the swing study is one market and one year

Widening to all four symbols at H4 and D1 hit a platform limitation that is
easy to mistake for missing data.

The Strategy Tester's `FromDate`/`ToDate` **do not bound what the exporter
replays**; they drive the tick stream only. A run configured for 2012-2014
with the exporter's date inputs empty reported `EURUSD H4, 1546 bars from
2011-01-03 to 2011-12-30`, which does not intersect what was requested. This
is the easiest possible way to believe you measured a period you did not.

The agent also does not hold every timeframe for every year, and **which year
it serves drifts between runs** on the same machine and broker. Unbounded,
the same export served 2011, then 2010, then 2009 within one afternoon. Two
timeframes measured minutes apart can be measuring different years. Pinning
the window to 2013 made all eight H4/D1 runs report zero bars; pinning to
2009 worked. Hence one market, one year, and an explicit statement that this
is not a widening of the Phase 19 study.

Three exporter defects were found and fixed on the way, each of which had
produced a silently wrong or misleading result:

- **`CopyRates` with `(start_time, stop_time)` returns 4401 in the tester**,
  for windows it demonstrably holds. The exporter now always uses the
  positional `(start_pos, count)` form and filters by timestamp itself.
- **The empty-window failure message asserted a cause it had not
  established.** It said "Check that the broker actually has history", which
  was wrong every time it fired. It now prints the span the agent actually
  offered, so an empty window and an empty cache are distinguishable from the
  output.
- **A matching log line is not a fresh log line.** The agent log accumulates
  every run of the day, so selecting the first `"bars from"` match returned an
  earlier run's range. An early sweep reported eight identical "results" -
  1,546 bars, 2011 dates, for D1 as well as H4 - that were one stale line read
  eight times. Match on the `PabEventExport (SYMBOL,PERIOD)` tag and take the
  last match.

## The headline finding

319,650 events across EURUSD, GBPUSD, USDCHF and USDJPY at M5 and H1, all
eight market/timeframe combinations, roughly 33,000 resolved outcomes each.
Pooled gross expectancy **+0.017R**. Walk-forward degradation **-0.00R**.

The question Phase 18 could not answer was what is left of that after costs.
The answer is: nothing that survives.

- **EURUSD M5, the best M5 market: the entire gross edge is worth 0.0003% of
  price in round-trip cost.** That is roughly a third of a pip of spread,
  slippage and commission combined. No retail FX market trades at that cost.
- The largest break-even in the whole study is 0.0019% of price (GBPUSD H1),
  and that market's gross edge is +0.020R on a 0.00148 average stop.
- **Re-priced at a thousandth of a percent of price, the whole 319,650-event
  sample goes from +0.017R to -0.045R.** The best spread available on these
  markets is several times larger.

| Assumed round-trip spread | Net expectancy |
| --- | --- |
| 0.000% of price | +0.017R |
| 0.001% of price | -0.045R |
| 0.005% of price | -0.294R |
| 0.020% of price | -1.228R |

Phase 18 said the study "cannot say whether the net figure is small-positive
or clearly negative." It can now: **not small-positive.** The remaining
uncertainty is the size of a cost that is comfortably larger than the thing
it is subtracted from.

**This is not a profitability result in either direction, and it is not a
refutation of the Al Brooks material the indicator is based on.** It is a
statement about this engine's output on one broker's feed.

**Do not tune parameters to improve these numbers.** The gross edge is a
thousandth of a percent of price wide. Any tuning that moves it to a
realistic cost is fitting noise, and one broker's demo feed cannot support
tuning.

## Why the study does not carry a measured spread

The exporter now measures per-bar spread where it can and labels what it
cannot. On this run every cost field came back blank:

```
PabEventExport: CopyBuffer copied -1 of 73752 spread values - error 4807
PabEventExport: costs ASSUMED (iSpread unavailable)
```

**The MT5 Strategy Tester exposes no historical spread buffer.** `iSpread`'s
`CopyBuffer` fails there with error 4807 and returns no values. So a
per-bar spread cannot be measured in this harness at all, and this is a
property of the tester rather than a bug in the code.

The first build wrote `0.0` into those columns. That would have handed the
research layer 73,751 rows asserting that trading was free, and published a
"net" expectancy that was really the gross one wearing a net label. The
exporter now writes **blanks**, the loader reads a blank as "no cost data",
and every report says GROSS in those words. This is the most important
single decision in the phase.

That is also why the study reports **break-even cost** and **assumed-spread
re-pricing** instead. Break-even is a property of the sample, so no cost
guess can influence it. The scenario table labels every figure as an
assumption in its own header.

## What Phase 19 changed

**One place decides what a trade costs.** `TradingCost.mqh` holds
`RoundTripCostPrice`, `CostInR`, and the commission-to-price-distance
conversion, plus `ReadSymbolCostFacts`. Both the chart exporter and the
replay EA call it, and the regression harness asserts the same formulas, so
there is one implementation rather than three that agree until one is edited.

**Costs are stored as a price distance, not as currency.** Expectancy is in R
and R is defined by the stop distance, which is a price quantity. Converting
a currency commission needs the broker's tick value, and that conversion is
where a commission divided by a price distance produces a number with no
units. A missing tick value yields `0.0` and a logged reason rather than an
infinite cost.

**Deliberately conservative.** The full spread is charged once per round trip
and slippage on **both** sides. Half-spread mid-price convention would halve
the cost and flatter the result; the entry fill is an ask while the levels
were drawn on a bid chart, so the trader pays the whole thing.

**Gross, cost, and net are separate columns.** `grossR` is unchanged in
meaning. `costR` is the average drag. `netR` is gross minus cost. A group
whose export lacks a cost column prints `n/a` for both, never the gross
figure twice.

**`net_expectancy_r` is withheld unless every resolved outcome in the group
was costed.** Averaging a cost over part of a group and dividing by the whole
group would compare two different denominators.

**Cost is charged on resolved outcomes only.** An expired event never reached
an exit, so it never paid a round-trip cost. Charging one would deflate
expectancy with a cost that was not incurred.

**The research layer recomputes rather than trusts.** `expected_cost_r`
re-derives the cost from the exported price components instead of reading the
exported `cost_r`. When the two disagree by more than rounding, the
recomputed value is used and the row is counted as a mismatch and reported.
One bad row should not hide a 320,000-row study, but it must never be
averaged in silently.

**Cost is charged per row, not per run.** A NO TRADE row carries a *known*
zero, because it has no levels and therefore no cost. Only an unmeasured
spread is blank. Conflating those two would lose a real distinction.

**Slippage and commission are inputs, labelled as assumptions.** Neither is
observable from a bar series by construction, so the `cost_model` label on
every row says which numbers were measured and which were chosen.

## Conventions that matter

- **Series order.** Analyzers expect index 0 to be the newest bar. Build
  fixtures oldest-first and displacement, net move, and overlap direction are
  silently inverted.
- **Series indexes are not stable.** They shift on every new bar and restart
  on a history reload. Anything that must survive across bars — slopes,
  pattern spans, fold boundaries — keys off timestamps.
- **Compare like with like.** A raw price quantity is not comparable across
  symbols or timeframes. Normalize to a fraction or ratio first. This applies
  to costs too, which is why break-even is reported as a percentage of price:
  a 0.0020 stop on EURUSD and a 6.18 stop on gold are the same trade, and
  their break-even costs differ by three orders of magnitude.
- **Closed bars only.** Index 0 is forming and cannot produce a decision.
- **A NO TRADE row carries nothing.** No direction, no levels.
- **No unverifiable claims.** No assertion passes without a log. No win rate
  without a real export. **A missing cost is not a zero cost**, and a cost that
  hides its own provenance is not evidence.

## Honest gaps

- **No measured spread on a historical study, and headlessly it is
  impossible.** Established, not assumed: see the probe section above.
  Slippage and commission remain assumptions everywhere.
- **The harness does not reach the chart lifecycle.** No runtime coverage of
  `OnCalculate` or the renderer. Duplicate ticks and history reload are
  still untested. This is now the most actionable remaining gap, because it
  does not depend on broker data.
- **The swing study is one market, one year.** EURUSD 2009 only. GBPUSD,
  USDCHF and USDJPY were not run at H4 or D1, so "H4 is negative" is a
  statement about EURUSD H4 in 2009, not about H4.
- **2009 and 2013 are not poolable.** The swing study is not a widening of
  the Phase 19 study and no figure from one should be compared with a figure
  from the other as though the period were held constant.
- **D1 rests on 122 resolved outcomes.** Reported above precisely so its
  +0.115R cannot be mistaken for a result.
- **One broker, one year per study.** An **Epic Pips MT5 Terminal** is
  installed and unused, which is the ready feed for the second broker.
- **The tester's history window is not selectable and drifts.** Two
  timeframes measured minutes apart can cover different years. Always read
  the range the run printed.
- Higher-timeframe and session context are not implemented.
- NinjaTrader is never compiled, is not at parity, and its slope math still
  hardcodes adjacent x coordinates.
- Tester inputs cannot be set from the command line, so a replay's date
  range is compiled-in. **The archived Phase 19 run requested 2014 and
  replayed 2013-01-01 to 2013-12-31.** Always read the range the run actually
  reported, never the range requested.
- Single export launches took 760 s to 1008 s on 2026-09-30 after the agent
  had been churning, against 13 s to 400 s previously. A 16-run sweep was
  not completable in one session. A run that stalls is usually downloading,
  but a timeout is not a hang either.

## Next steps

`ROADMAP.md` holds the authoritative list. In order:

1. **Indicator lifecycle integration tests.** Promoted above the spread work
   because it is the one remaining gap that does not depend on broker data.
   The harness does not reach `CPabEngine`, `OnCalculate`, or the renderer.
2. **Widen the swing study** past one market. Blocked on which years the
   tester agent can serve per timeframe, not on code.
3. **A measured spread**, which now needs terminal UI interaction rather than
   anything that can be scripted.
4. **Repeat across a second year and a second broker feed.** One broker, one
   year. Epic Pips is installed and unused.
5. Re-examine the H1 claim in `ROADMAP.md` item 5, which Phase 20 found does
   not reproduce. Record what a 24-34 bar H1 sample would have to be.
6. Higher-timeframe context using closed HTF bars.
7. Session/prior-day/overnight levels with broker-time assumptions.
8. NinjaTrader: apply the normalized slope and compile it.

## Environment notes

- Local repo: `E:\price-action-bar-by-bar`, remote
  `git@github.com:ybagheri/price-action-bar-by-bar.git`, default branch `main`.
- MT5 for this project is `C:\Users\bagheri\AppData\Roaming\Alpari MT5_3`, data
  folder `...\MetaQuotes\Terminal\0BCB0986AE04DC375BC47CA5AA358455`. The
  terminal is installed under `AppData\Roaming`, NOT `Program Files`, and the
  account is `bagheri`, not `BazikadeStore`; both were wrong here until Phase
  20. Several other Alpari terminals (`Alpari MT5`, `_2`, `_4`, `_5`) and an
  Epic Pips terminal are installed for unrelated projects, so process checks
  must match the executable path, not the process name.
- Compile check:
  `& "C:\Users\bagheri\AppData\Roaming\Alpari MT5_3\MetaEditor64.exe" /compile:"<file>.mq5" /log:"<log>"`
  MetaEditor writes UTF-16 logs; confirm `0 errors, 0 warnings` from the log
  text, not the process exit code, which is **1 even on success**. It also
  holds the log open briefly after exiting. The indicator includes
  `../Include/...`, so it must be compiled from inside the terminal data
  folder. Copy the sources across on every MQL5 change: a stale copy there
  silently tests old code.
- The headless replay recipe, including the `.set`-file trap and the agent
  output folder, is in `TESTING.md`. Every trap there produces a silently
  wrong result rather than an error. The Phase 20 additions are the ones
  about the tester's date range not bounding the replay, `CopyRates`
  `(start_time, stop_time)` failing with 4401, and stale log lines.
- Python runs from `research/` after `python -m pip install -e .`.
- A 320,000-event study takes a few minutes of pure Python once the CSVs
  exist. Concatenating the eight per-symbol exports needs a de-duplicated
  header, or row 2 of the merged file is a header and every later row shifts.
- The repo has no `.gitattributes`. On this machine the checkout left CRLF in
  the worktree, which showed up as all 59 tracked files modified with
  13,499 insertions against 13,499 deletions and zero real changes. Local
  `core.autocrlf` is now `true` and the tree is clean. If a whole-file diff
  appears for no reason, check this before concluding that anything changed.

# Handoff Summary - 2026-09-29

State of the repository after Phase 19. The blocking gap from Phase 18 is
closed, and it closes against the project: the measured edge does not
survive execution costs.

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
| MQL5 harness compile | 0 errors, 0 warnings | MetaEditor log, 2026-09-29 |
| MQL5 export EA compile | 0 errors, 0 warnings | MetaEditor log, 2026-09-29 |
| MQL5 unit-test Script compile | 0 errors, 0 warnings | MetaEditor log, 2026-09-29 |
| MQL5 harness runtime, **headless** | **84 passed, 0 failed** | `research/test_artifacts/mql5_harness_20260929_cost.txt` |
| Costed multi-market study | 319,650 events, 4 markets, 2 timeframes, 8 combinations | `research/test_artifacts/study_costed_multi_market_2013.txt` |
| Python tests | 124 passed | `pytest` and `unittest` both agree |
| Python `compileall` | clean | `research/` |

**What the harness does not cover.** It exercises the analyzer classes, not
`CPabEngine`, not `OnCalculate`, and not the chart renderer. The chart path is
compile-verified and replay-verified but not lifecycle-verified: duplicate
ticks and history reload remain untested. That is the main remaining gap.

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

- **No measured spread on a historical study.** See above. The chart path reads
  it correctly; the tester does not expose it. Slippage and commission remain
  assumptions everywhere.
- **The harness does not reach the chart lifecycle.** No runtime coverage of
  `OnCalculate` or the renderer.
- M5 and H1 only. Nothing says whether the rules do anything on H4 or D1.
- One broker's demo feed, one year. No second broker, no second year.
- Higher-timeframe and session context are not implemented.
- NinjaTrader is never compiled, is not at parity, and its slope math still
  hardcodes adjacent x coordinates.
- Tester inputs cannot be set from the command line, so a replay's date range
  is compiled-in, and which history is cached varies between runs. **The
  archived Phase 19 run requested 2014 and replayed 2013-01-01 to
  2013-12-31.** Always read the range the run actually reported.
- Each of the eight study runs took 13 to 400 seconds depending on how much
  history needed downloading, so a run that stalls is usually downloading, not
  hung.

## Next steps

`ROADMAP.md` holds the authoritative list. In order:

1. **Obtain a measured spread.** Live forward collection or exported tick
   data. Until then every cost figure is an assumption, however clearly it is
   labelled.
2. Widen to H4 and D1.
3. Repeat across a second year and a second broker feed.
4. Indicator lifecycle integration tests.
5. Review the H1 setup construction: 24-34 bars to exit with slightly negative
   expectancy suggests the stop and target logic is not doing anything there.
6. Higher-timeframe context using closed HTF bars.
7. Session/prior-day/overnight levels with broker-time assumptions.
8. NinjaTrader: apply the normalized slope and compile it.

## Environment notes

- Local repo: `D:\Projects\price-action-bar-by-bar`, remote
  `git@github.com:ybagheri/price-action-bar-by-bar.git`, default branch `main`.
- MT5 for this project is `C:\Program Files\Alpari MT5_3`, data folder
  `C:\Users\BazikadeStore\AppData\Roaming\MetaQuotes\Terminal\AB546F93664BD7249969F5973868F430`.
  Several other Alpari terminals run concurrently for unrelated projects, so
  process checks must match the executable path, not the process name. On this
  machine that means `C:\Program Files\Alpari MT5_3\terminal64.exe` exactly;
  MT5_2, MT5_4, and MT5_5 are all in use for other work.
- Compile check:
  `& "C:\Program Files\Alpari MT5_3\MetaEditor64.exe" /compile:"<file>.mq5" /log:"<log>"`
  MetaEditor writes UTF-16 logs; confirm `0 errors, 0 warnings` from the log
  text, not the process exit code. The indicator includes `../Include/...`,
  so it must be compiled from inside the terminal data folder. Copy the
  sources across on every MQL5 change: a stale copy there silently tests old
  code.
- The headless replay recipe, including the `.set`-file trap and the agent
  output folder, is in `TESTING.md`. Every trap there produces a silently
  wrong result rather than an error.
- Python runs from `research/` after `python -m pip install -e .`.
- A 319,650-event study takes a few minutes of pure Python once the CSVs
  exist. Concatenating the eight per-symbol exports needs a de-duplicated
  header, or row 2 of the merged file is a header and every later row shifts.

# Project Audit

Audit date: 2026-09-24

## Executive summary

The repository has a useful MQL5 prototype and a NinjaTrader 8 port, but it is not yet a reliable, explainable, no-lookahead Price Action decision-support system. The core risk is not the overall class decomposition; it is event timing and state integrity in the MT5 orchestrator.

The recommended direction is to retain MQL5 as the canonical real-time and historical analysis engine, correct closed-bar processing and chart lifecycle behavior, define a versioned event record, and add Python only for offline validation, outcome metrics, and research. A live Python/MT5 bridge is not justified.

## Repository inventory

| Area | Current state |
|---|---|
| MQL5 indicator | `MQL5/Indicators/PriceActionBarByBar.mq5` |
| MQL5 analysis modules | 10 headers under `MQL5/Include/PriceActionBarByBar/` |
| MQL5 tests | One synthetic script with eight groups: `MQL5/Scripts/PAB_UnitTests.mq5` |
| NinjaTrader port | One 1,019-line C# indicator: `NinjaTrader/PriceActionBarByBar.cs` |
| Documentation | Persian `README.md`, `ROADMAP.md`, `CHANGELOG.md`, `NinjaTrader/README.md` |
| Python | None |
| CI/build automation | None |
| Ignore/environment policy | None |
| Automated execution | None |
| Trading secrets | None found in tracked files |

## Current architecture

### MQL5

`OnCalculate` currently runs this pipeline:

1. Copy ATR history.
2. Reset analyzers on initial load.
3. Replay bars through `CBarClassifier`, `CSwingDetector`, and `CTradingRangeDetector`.
4. Analyze accumulated swings with `CPatternDetector` and `CMeasuredMoveDetector`.
5. Evaluate `CAlwaysInTracker` using the current close and latest confirmed swings.
6. Render labels, markers, range, pattern, measured move, and state panel through `CChartRenderer`.

The classes are separated logically, but the orchestrator is hard-coded. `IAnalyzer` is therefore mostly nominal. `CPatternDetector`, `CAlwaysInTracker`, and `CMeasuredMoveDetector` implement no-op `Update` methods only to satisfy it.

### NinjaTrader 8

The C# file mirrors the MQL5 classes in one NinjaScript file and uses `Calculate.OnBarClose`. This gives cleaner bar timing than the current MQL5 path, but the port is uncompiled, untested, and not fully equivalent.

## Current capabilities

- Bull/bear trend, doji, inside, and outside bar classification.
- H1/H2/H3+ and L1/L2/L3+ stateful pullback labels.
- A simple CLV and prior-pullback-extreme signal-quality proxy.
- Delayed N-bar fractal swing highs and lows.
- Coarse trading-range/trend classification based on overlap, displacement, and optional ATR.
- A sticky Always-In proxy.
- Simple double-top, double-bottom, HH/HL, LH/LL, triangle, and three-push wedge classifiers.
- A minimal equal-leg measured-move projection.
- Basic MT5 and NinjaTrader object rendering.

These are useful heuristics. They are not a complete implementation of Al Brooks methodology.

## Verified baseline

The repository was inspected on a clean `main` branch synchronized with `origin/main`.

MetaEditor from `C:\Program Files\Alpari MT5_2\metaeditor64.exe` was used to compile an isolated copy of the unchanged MQL5 tree:

| Target | Result |
|---|---|
| `PriceActionBarByBar.mq5` | 0 errors, 0 warnings |
| `PAB_UnitTests.mq5` | 0 errors, 0 warnings |

The indicator uses angle-bracket includes, so MetaEditor resolved them from the Alpari terminal data directory. All ten installed headers were compared with repository headers and were identical after line-ending normalization, so the clean result was not caused by stale include content.

The MQL5 test script was compiled but not executed. No claim is made that its assertions currently pass at runtime.

NinjaTrader compilation and runtime tests were not possible because no NinjaTrader 8 SDK is available.

GitHub issues could not be queried because the GitHub CLI is not installed and no authenticated issue API workflow is available locally.

## Git history

| Commit | Summary |
|---|---|
| `ae90ee8` | Initial placeholder |
| `b7b2437` | MQL5 OOP framework and initial modules |
| `e21be2f` | ATR, quality, buffers, tests, Always-In, breakout/climax, measured move, rendering |
| `e33336f` | Removed the obsolete root-level indicator |
| `89a5c50` | Added the NinjaTrader port |

The history is linear, with no tags or release branches. Commit subjects use terse phase labels. Future work should use smaller, independently testable phase commits.

## Strengths

- Analysis and chart drawing are separated in both platform ports.
- MQL5 logic is isolated from chart API calls in the analyzer headers.
- Swing confirmation is delayed by the configured right-side bars, avoiding direct classic future-bar access.
- Synthetic MQL5 tests already cover the main prototype classes.
- Inputs expose several important thresholds.
- No order execution, broker credentials, or secret files are present.
- The project has a small codebase that can be corrected without a full rewrite.

## Critical findings

### P0: MQL5 reprocessing corrupts analyzer state

On a tick with no new bar, `rates_total - prev_calculated` is zero. The current code can nevertheless replay index 1 and index 0. The ring buffers only push and do not deduplicate or replace by timestamp.

Consequences include duplicated bars, repeated swings, changed pullback counters, incorrect ring-buffer index alignment, and incorrect rendering. This must be fixed before feature expansion.

Reference: `MQL5/Indicators/PriceActionBarByBar.mq5:227`

### P0: forming-bar signals can repaint

The current bar is analyzed and rendered on every tick. Breakout, climax, pullback, regime, and Always-In values can appear and then change before close. No explicit closed-bar/live-preview contract exists.

Reference: `MQL5/Indicators/PriceActionBarByBar.mq5:252`

### P0: chart objects are not reconciled with current state

Render methods return when a feature is absent or disabled, but do not remove an object created by an earlier state. Provisional markers and labels can remain after invalidation. Dynamic range, pattern, and measured-move objects are especially vulnerable.

Reference: `MQL5/Include/PriceActionBarByBar/ChartRenderer.mqh:92`

### P0: an intentional label is not valid if that label is not explicitly rendered

A marker is not confirmed merely because it has a label. The first design must state when an object is created, when it is confirmed, and when it is removed. If the label is intended to show a provisional value, that state must be rendered visibly as provisional.

## High-priority findings

### Range state can remain stale

After a trading range, `STATE_TRANSITION` does not clear `m_currentRange.active`, so the old range rectangle can remain active.

Reference: `MQL5/Include/PriceActionBarByBar/TradingRangeDetector.mqh:118`

### Pattern slope and cross-platform parity are incorrect

MQL5 stores mutable series indexes in swing points. NT does not store bar positions and hardcodes adjacent x coordinates for slope, which is dimensionally wrong when highs or lows are separated by different numbers of bars.

References:

- `MQL5/Include/PriceActionBarByBar/PAB_Types.mqh:94`
- `MQL5/Include/PriceActionBarByBar/PatternDetector.mqh:131`
- `NinjaTrader/PriceActionBarByBar.cs:596`

### ATR is copied on every tick

The full ATR series is copied every calculation. Copy success is only checked as `copied > 0`, not against the requested count. ATR failures are silent and the current bar remains provisional.

Reference: `MQL5/Indicators/PriceActionBarByBar.mq5:216`

### Input validation is incomplete

Some values are clamped inside constructors, but thresholds and relationships are not validated centrally. Invalid or contradictory settings can silently disable or distort analysis.

Reference: `MQL5/Indicators/PriceActionBarByBar.mq5:109`

### Indicator instances collide

All MT5 instances use chart ID `0` and prefix `PAB`. `ClearAll` can delete objects belonging to another instance on the same chart.

References:

- `MQL5/Indicators/PriceActionBarByBar.mq5:123`
- `MQL5/Include/PriceActionBarByBar/ChartRenderer.mqh:256`

### No explicit event timing model

A fractal records the candidate swing time but not its confirmation time. A future research export cannot safely distinguish the bar that formed a swing from the later bar where it became known.

Reference: `MQL5/Include/PriceActionBarByBar/SwingDetector.mqh:56`

## Medium-priority findings

- The one-bar pullback state machine is not context-aware enough for H2/L2 setup decisions.
- Pullback quality is a coarse label, not a documented confidence model.
- Pattern detection uses the latest same-type swings without validating alternation, separation, age, ATR distance, or location.
- Measured move has no invalidation, expiry, target-hit state, or confidence.
- Always-In stores a reference extreme but does not use it for decisions.
- `IAnalyzer` does not represent the real update model of swing-dependent services.
- The MQL5 test harness contains an intended inside-bar case that is not inside (`MQL5/Scripts/PAB_UnitTests.mq5:84`).
- The success path writes a chart comment, contradicting the “no chart output” claim.
- The test script covers neither runtime orchestration nor object lifecycle.
- There is no CI, lint, formatting, coverage, or static-analysis configuration.
- There is no `.gitignore`, editor policy, generated-file policy, or secret-scan workflow.
- The README is Persian-only and does not explain a new contributor's setup in English.
- Documentation calls the NT port 1:1 even though known logic differences exist.
- Changelog versions have no corresponding Git tags.
- No screenshots, validated example charts, or execution evidence are committed.

## No-look-ahead assessment

No direct classic future-bar access was identified in the core MQL5 analyzer formulas. Fractal confirmation is correctly delayed.

The project nevertheless does not yet guarantee a research-safe real-time contract because:

- the forming bar is repeatedly analyzed;
- analyzer updates are not idempotent;
- swing anchor time and confirmation time are not both recorded;
- provisional and confirmed objects are not separated;
- no historical outcome evaluator is present.

The target rule should be: a decision at bar close may use only bars closed no later than that close, plus explicitly delayed confirmation events whose `confirmedAt` is no later than the decision time.

## Security and operational assessment

- No credentials or secret-bearing files were found.
- The project does not place trades.
- The indicator should remain analysis and decision support only.
- Any future CSV exporter must use MT5 sandboxed file access and configurable paths.
- Any future Python tool should operate offline and should not require broker credentials.

## Recommended immediate order

1. Fix MQL5 incremental processing and enforce closed-bar decisions.
2. Add timestamp-safe, idempotent history and explicit confirmation metadata.
3. Reconcile and namespace chart objects.
4. Correct range state and swing-time pattern calculations.
5. Expand deterministic MQL5 tests for timing, duplicates, transitions, and no-lookahead fixtures.
6. Refactor the orchestrator and validation foundation.
7. Build bar features, context, setup, risk, and explanation layers.
8. Add versioned event export and offline Python outcome analysis.
9. Validate NinjaTrader separately only after shared fixtures exist.
10. Expand documentation using demonstrated behavior only.

## Audit conclusion

The prototype should be evolved, not discarded. Its class-level structure is a reasonable base, but the MT5 event model, object lifecycle, tests, and documentation must be corrected before adding more visual signals. Broad Brooks-style concepts should be added only when they can be expressed as explicit, testable heuristics with a documented status such as formal rule, heuristic approximation, statistical feature, or visual aid.

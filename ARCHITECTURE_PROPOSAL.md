# Architecture Proposal

Date: 2026-09-24

## Decision

Adopt **Option D: MQL5 primary engine with Python offline research and validation tools**.

MQL5 remains the canonical implementation for real-time closed-bar analysis, historical replay, explanations, and chart visualization. Python is used only for offline event validation, outcome measurement, MAE/MFE analysis, statistics, and research tooling. Do not add a live Python/MT5 bridge.

A second, long-term direction may be a Python engine with an MT5 bridge, but it is not justified by the current repository or performance requirements.

## Options considered

| Option | Advantages | Disadvantages | Decision |
|---|---|---|---|
| A. Pure MQL5 | Native MT5 access, low latency, no IPC, easy distribution, direct chart objects | MQL5 test and research tooling are less productive; no rich offline statistics without exports | Rejected as the complete long-term plan |
| B. Python research + MQL5 visualization | Productive testing and statistics | Risks two implementations diverging; requires a stable export contract | Accepted as part of Option D only |
| C. Python engine + MT5 bridge | One rich language and flexible research | Process management, serialization, latency, failure recovery, packaging, and synchronization complexity | Rejected |
| D. MQL5 primary + Python research | Canonical MT5 behavior, deterministic bar timing, no live IPC, versioned offline research | Some research requires export/replay; NT parity needs fixtures | Selected |

## Architectural principles

1. MQL5 and Python must not independently decide whether a setup exists.
2. MQL5 is the source of analytical events and explanations.
3. Python consumes immutable event records and measures outcomes.
4. No future bar may affect a decision timestamp.
5. A feature requiring later bars is retrospective unless a real-time confirmation event is emitted at the actual confirmation time.
6. Detection, risk/reward, confidence, decision, explanation, and rendering remain separate.
7. Heuristics must be labelled as heuristics, not deterministic market knowledge.
8. The default product is analysis and decision support; it never places trades.

## Target runtime layers

```text
MT5 Market Data
    ↓
BarStream / closed-bar gate
    ↓
BarFeatureAnalyzer
    ↓
StructureAnalyzer
    ↓
ContextAnalyzer
    ↓
ConceptAnalyzer
    ↓
SetupDetector
    ↓
RiskRewardAnalyzer
    ↓
ConfidenceEngine
    ↓
DecisionSupport
    ↓
ExplanationBuilder
    ↓
MT5 Visualization
```

### 1. Market data and bar stream

Responsibilities:

- Convert MQL5 series arrays into an explicit chronological frame.
- Distinguish current forming bars from completed bars.
- Make updates idempotent by timestamp.
- Process each bar exactly once unless a fixed closed-bar is explicitly replaced.
- Copy ATR only for required history and validate the returned count.

Output:

- `SBarFrame` containing bar open time, close time, OHLC, range features, ATR, and sequence number.

### 2. Bar feature analyzer

Responsibilities:

- Bar direction and quality features.
- Body, range, upper/lower wick, CLV, body ratio, and tail ratios.
- Inside/outside relationships.
- Large/small range classification relative to configurable recent volatility.
- Consecutive bull/bear counts.
- Follow-through and failed-follow-through features using only already closed bars.

No context or trade decision is made in this layer.

### 3. Structure analyzer

Responsibilities:

- Delayed swing high/low confirmation.
- Pullback attempt numbering and leg direction.
- Support/resistance candidates from confirmed swings.
- Range boundaries and structural breaks.
- Stable timestamps and explicit confirmation timestamps for every structure event.

Series indexes may be used internally for calculations, but persisted or exported events use timestamps.

### 4. Context analyzer

Responsibilities:

- Short-term micro trend over configurable 3–10 bars.
- Medium-term trend/range/channel classification.
- Context strength, overlap, displacement, and failure characteristics.
- Multi-timeframe context when configured.
- Session and prior-session/day context when data is available.

The output is a context snapshot, not a trade signal.

### 5. Concept analyzer

Reliably formalized concepts may include:

- trend and micro trend;
- trading range and range tests;
- breakout attempt and confirmation;
- failed breakout/test;
- High 1/2/3+ and Low 1/2/3+ pullback attempts;
- first/second entry structure;
- signal-bar features;
- double top/bottom, wedge, channel, and three-push approximations;
- measured-move projections;
- climax/exhaustion features.

Each concept must declare one of:

- `FORMAL_RULE` — deterministic implementation of the documented rule;
- `HEURISTIC` — contextual approximation;
- `STATISTICAL_FEATURE` — measurable feature without a binary claim;
- `VISUAL_AID` — chart annotation requiring human interpretation;
- `MANUAL_ONLY` — intentionally not automated.

### 6. Setup detector

A setup is a composition of context, location, structure, and signal evidence. Candidate types may include:

- pullback in trend;
- second entry;
- reversal at range extreme;
- failed breakout;
- breakout with follow-through;
- wedge/channel reversal.

The detector must be able to output `NO_TRADE`, `WEAK`, `POSSIBLE`, `PROBABLE`, and `CONFIRMED`. “Confirmed” describes the evidence state at decision time, not certainty about the future.

### 7. Risk/reward analyzer

For candidate setups, calculate only from information available at the decision bar:

- reference entry, preferably next-bar or closed-bar reference rather than an assumed fill;
- structural invalidation;
- first target;
- measured-move target;
- approximate reward/risk;
- nearby support/resistance obstacles;
- spread/size caveat where relevant.

The system remains analytical and must not place orders.

### 8. Confidence engine

Use an additive, auditable score rather than a black-box probability. Each component records:

- feature value;
- direction;
- points awarded or deducted;
- reason text;
- cap and range;
- configuration version.

Initial categories are context, signal bar, location, trend alignment, follow-through, room to target, and opposing pressure. Weights must be conservative defaults with explicit documentation and tests, not optimized claims.

The score is “setup evidence strength,” not predicted win probability.

### 9. Explanation and decision support

A traceable explanation contains:

- decision timestamp;
- market state;
- setup type and status;
- supporting reasons;
- opposing reasons;
- invalidation and target context;
- score components;
- no-trade conditions;
- engine version and parameter fingerprint.

### 10. Visualization

The renderer consumes a stable snapshot. It must:

- use an instance-specific object namespace;
- create, update, hide, and delete objects deterministically;
- distinguish provisional and confirmed output;
- avoid rendering the current forming bar as a confirmed setup;
- support feature-level visibility toggles;
- avoid accumulating stale pattern and range objects;
- render compact explanations rather than every internal calculation.

## Event and timing contract

Every analytical event should contain at least:

```text
event_id
event_type
bar_open_time
bar_close_time
confirmed_at
anchor_time
symbol
timeframe
direction
status
score
reference_price
invalidation_price
target_price
reason_codes
engine_version
parameter_version
```

Definitions:

- `bar_open_time`: open time of the bar that originated the event.
- `bar_close_time`: time the originating bar became complete.
- `anchor_time`: time of the swing, level, or pattern coordinate on the chart.
- `confirmed_at`: earliest time the event was available to the engine.
- `decision_time`: time a candidate could be acted upon or analyzed.

A historical candidate is valid only if `confirmed_at <= decision_time`. Bars after `decision_time` may be used solely to evaluate retrospective outcomes.

## Historical and research architecture

### MQL5 responsibilities

- Replay bars in chronological order using the same analyzer code as the live closed-bar path.
- Emit versioned CSV or another documented event format.
- Record setup, risk/reward, explanation, and decision state.
- Ensure historical and live outputs use the same analysis functions.

### Python responsibilities

- Validate event schema and ordering.
- Reject future leakage in fixture tests.
- Evaluate target hit, invalidation hit, time-to-event, MFE, and MAE.
- Produce setup-specific counts, rates, expectancy, and distributions.
- Compare versions and detect parameter fingerprint changes.
- Provide plots and reports without entering the live decision path.

Python must not silently recalculate a different setup engine. If a future research-only feature is added in Python, it must be clearly labelled as a research experiment and not reported as MT5 output.

## NinjaTrader decision

Treat NinjaTrader as a secondary platform adapter, not an equal-priority implementation.

Before expanding it:

1. Define shared versioned fixtures for bar, swing, regime, pattern, setup, and explanation outputs.
2. Add explicit swing anchor positions or normalized slopes.
3. Compile in real NinjaTrader 8.
4. Add an NT unit harness or Strategy Analyzer validation.
5. Correct object lifecycle parity.

Do not claim algorithmic parity before these checks pass.

## Multi-timeframe and sessions

These features belong in the context layer after single-timeframe timing is correct.

- Timeframes are configurable; defaults are not hardcoded business rules.
- Higher-timeframe analysis uses the last fully closed higher-timeframe bar.
- Session boundaries and previous day/session values must use broker time and documented symbol assumptions.
- Missing session data produces `UNAVAILABLE`, not a fabricated neutral value.
- Session logic is advisory context and must not be fitted to one instrument without broad validation.

## Testing strategy

### MQL5

- MetaEditor compile of indicator, scripts, and test harnesses.
- Deterministic unit scenarios for each analyzer.
- Orchestrator tests for duplicate calls, no new bar, one new bar, history reload, and forming bars.
- No-lookahead fixtures where a later bar must not alter an earlier decision.
- Chart lifecycle tests where practical in MT5.
- Strategy Tester and visual checks where relevant.

### Python

- `pytest` for CSV schema, ordering, leakage guards, and outcome metrics.
- Golden fixtures generated by a documented MQL5 version.
- Property-based tests for timestamp ordering and target/invalidation ambiguity.
- Statistical reporting without automated parameter optimization.

### NT8

- Real compilation.
- Shared fixture parity tests.
- Closed-bar visual/replay checks.

## Performance model

- Recompute the full analysis only on initialization, timeframe/history rebuild, or explicit reset.
- On ordinary ticks, update only provisional market state when explicitly enabled.
- Create candidate events only when a closed bar completes.
- Copy only the ATR range required by analyzers.
- Reuse bar and structure snapshots.
- Recompute structure-derived concepts only when a new swing or bar changes their inputs.
- Reconcile chart objects by stable keys rather than repeatedly deleting all objects.
- Cap historical object counts and export/debug history with explicit inputs.

## Delivery phases

1. Foundation: closed-bar contract, input validation, instance namespace, event types, logging, object reconciliation.
2. Bar engine: full wick/body/overlap/consecutive/follow-through features and tests.
3. Context engine: micro/medium structure, ranges, levels, failed tests/breakouts, context snapshots.
4. Brooks concepts: formalize only reliable rules and document automation boundaries.
5. Setup detector: composed candidates and explicit `NO_TRADE` reasons.
6. Risk/reward and confidence: transparent components, caps, tests, and parameter versioning.
7. Visualization: setup markers, levels, compact explanation, debug mode, lifecycle tests.
8. Historical analysis: MQL5 event export and Python outcome/MAE/MFE tooling.
9. Documentation: installation, configuration, interpretation, testing, backtesting, limitations.
10. QA: compile, runtime tests, historical fixtures, performance and Git review.

## Acceptance criteria

A phase is stable only when:

- MetaEditor compilation succeeds with no warnings for changed MQL5 files;
- deterministic tests pass in a real MT5 runtime;
- no duplicate analyzer updates occur on unchanged ticks;
- all decision events are closed-bar and timestamp ordered;
- no export contains `confirmed_at > decision_time`;
- chart objects match the current snapshot;
- configuration is validated and fingerprinted;
- documentation matches demonstrated behavior;
- commit scope and test evidence are explicit.

## Final recommendation

Build a disciplined MQL5-native decision-support engine first. Add Python as an offline research and validation layer only after a versioned event export exists. Preserve NinjaTrader as a secondary, explicitly unverified adapter until shared fixtures and real compilation are available. This approach minimizes duplication, avoids live IPC risk, and keeps the product focused on explainable chart reading rather than opaque signal generation.

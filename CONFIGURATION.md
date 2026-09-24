# Configuration

## Bar classification

| Input | Default | Meaning |
|---|---:|---|
| `InpDojiBodyRatio` | 0.30 | Body/range below this is a doji |
| `InpClvFavorableMin` | 0.15 | Minimum favorable close location for pullback quality |
| `InpFeatureLookback` | 20 | Prior bars used for relative range |
| `InpLargeRangeMult` | 1.50 | Large-range multiplier |
| `InpSmallRangeMult` | 0.70 | Small-range multiplier |
| `InpStrongBodyRatio` | 0.60 | Strong body ratio with favorable close |

## Structure and context

| Input | Default | Meaning |
|---|---:|---|
| `InpFractalLegs` | 2 | Bars required on each side of a swing |
| `InpRegimeLookback` | 20 | Rolling range/trend window |
| `InpOverlapThreshold` | 0.55 | High overlap indicates range |
| `InpDisplaceThreshold` | 3.0 | Normalized displacement indicates trend |
| `InpUseRealATR` | true | Use MT5 ATR for regime normalization |
| `InpATRPeriod` | 14 | ATR period |

## Patterns and breakouts

| Input | Default | Meaning |
|---|---:|---|
| `InpSwingSimilarityPct` | 0.15 | Equal-swing tolerance in percent |
| `InpConvergenceMin` | 0.15 | Heuristic convergence threshold |
| `InpBreakoutLookback` | 10 | Fresh-extreme window |
| `InpBreakoutClvMin` | 0.50 | Breakout close-location threshold |
| `InpClimaxLookback` | 20 | Climax baseline window |
| `InpClimaxRangeMult` | 2.0 | Climax range multiplier |
| `InpClimaxBodyRatioMax` | 0.35 | Weak-body threshold for climax |

## Decision support

| Input | Default | Meaning |
|---|---:|---|
| `InpMinimumQuality` | 55 | Minimum 0–100 evidence score |
| `InpMinimumRiskReward` | 1.50 | Minimum analytical reward/risk |
| `InpExportEvents` | false | Write closed-bar events to CSV |
| `InpEventFile` | `pab_events.csv` | Sandbox-relative CSV name |

Invalid values cause `INIT_PARAMETERS_INCORRECT` and a Journal message rather than silent reconfiguration.

## Tuning guidance

Change one conceptual group at a time. Avoid optimizing on one symbol, timeframe, or date range. Record engine and parameter versions for every exported dataset.

//+------------------------------------------------------------------+
//|                                                  PabTests.mqh   |
//|                 Price Action Bar-by-Bar - Regression Harness   |
//|                                                                    |
//| PHASE 17. The test body lives here so that two entry points can  |
//| run exactly the same assertions:                                  |
//|                                                                    |
//|   Scripts/PAB_UnitTests.mq5  - run by hand from the Navigator.    |
//|   Experts/PAB_HarnessEA.mq5  - run headlessly in the Strategy     |
//|                                Tester, so evidence does not depend |
//|                                on a human being present.            |
//|                                                                    |
//| Keeping the assertions in one place is the point. Two copies of a |
//| test suite drift, and a suite that only runs when someone remembers|
//| is not a regression suite.                                       |
//|                                                                    |
//| Phase 21 added the lifecycle groups: TestEnginePipeline drives    |
//| CPabEngine end-to-end (closed-bar gate, duplicate ticks, history  |
//| reload determinism) and TestRendererLifecycle drives the chart    |
//| object lifecycle. What remains uncovered is the indicator's own   |
//| OnCalculate bookkeeping and the export EA's file writing; those   |
//| are MT5-lifecycle code paths, listed as gaps in HANDOFF.md.      |
//+------------------------------------------------------------------+
#property strict

#include "PAB_Types.mqh"
#include "PAB_Utils.mqh"
#include "TradingCost.mqh"
#include "BarClassifier.mqh"
#include "SwingDetector.mqh"
#include "TradingRangeDetector.mqh"
#include "PatternDetector.mqh"
#include "AlwaysInTracker.mqh"
#include "MeasuredMoveDetector.mqh"
#include "ContextAnalyzer.mqh"
#include "DecisionEngine.mqh"
// Phase 21: the lifecycle groups drive the pipeline as a whole and
// the chart object lifecycle, so they need the orchestrator and the
// renderer. Both headers only define their own class and include the
// analyzer headers already listed above, so nothing is pulled in twice.
#include "PabEngine.mqh"
#include "ChartRenderer.mqh"

int g_pass = 0;
int g_fail = 0;

// Names of failing assertions, so a headless run can emit a machine-readable
// summary. Without this an automated run reports only a count, and a failure
// has to be reconstructed by hand from the journal.
string g_failures[];
#define PAB_MAX_RECORDED_FAILURES 64

//+------------------------------------------------------------------+
void ResetFailureLog()
  {
   ArrayResize(g_failures, 0);
  }

//+------------------------------------------------------------------+
void RecordFailure(const string testName)
  {
   if(ArraySize(g_failures) < PAB_MAX_RECORDED_FAILURES)
     {
      int n = ArraySize(g_failures);
      ArrayResize(g_failures, n + 1);
      g_failures[n] = testName;
     }
  }

//+------------------------------------------------------------------+
void Check(const bool condition, const string testName)
  {
   if(condition)
     {
      g_pass++;
      Print("  [PASS] ", testName);
     }
   else
     {
      g_fail++;
      RecordFailure(testName);
      Print("  [FAIL] ", testName);
     }
  }

//+------------------------------------------------------------------+
//| Builds a synthetic OHLC series, OLDEST FIRST in the arrays passed |
//| in, then reverses them into series order (index 0 = newest) the   |
//| same way MT5 hands bars to OnCalculate.                          |
//+------------------------------------------------------------------+
void BuildSeries(const double &o[], const double &h[], const double &l[], const double &c[],
                  datetime &time[], double &open[], double &high[], double &low[], double &close[])
  {
   int n = ArraySize(o);
   ArrayResize(time, n); ArrayResize(open, n); ArrayResize(high, n);
   ArrayResize(low, n);  ArrayResize(close, n);

   datetime t0 = D'2026.01.01 00:00';
   for(int i = 0; i < n; i++)
     {
      // reverse: array position 0 (series, newest) = last element of o[]/h[]/...
      int src = n - 1 - i;
      time[i]  = t0 + (n - i) * 3600;
      open[i]  = o[src];
      high[i]  = h[src];
      low[i]   = l[src];
      close[i] = c[src];
     }
  }

//+------------------------------------------------------------------+
//| Test 1: Bar classification — trend bar, doji, inside, outside    |
//+------------------------------------------------------------------+
void TestBarClassification()
  {
   Print("--- TestBarClassification ---");

   // Oldest-first design values (index 0 = oldest bar in this array).
   double o[] = {1.1000, 1.1010, 1.1015, 1.1013, 1.0995};
   double h[] = {1.1012, 1.1030, 1.1017, 1.1016, 1.1000};
   double l[] = {1.0998, 1.1008, 1.1005, 1.1006, 1.0980};
   double c[] = {1.1010, 1.1012, 1.1006, 1.1014, 1.0985};
   // bar0: bull trend bar (close near high)
   // bar1: bull trend bar, sets a new high
   // bar2: doji-ish (small body vs range)
   // bar3: inside bar
   // bar4: bear trend bar, breaks lower

   datetime time[]; double open[], high[], low[], close[];
   BuildSeries(o, h, l, c, time, open, high, low, close);
   int n = ArraySize(open);

   CBarClassifier bc(0.30, 100, 0.15);
   for(int i = n - 1; i >= 0; i--)
      bc.Update(i, time, open, high, low, close, n);

   SBarInfo newest;
   bc.GetBar(0, newest); // corresponds to source index 4 (bear trend bar)
   Check(newest.barType == BAR_BEAR_TREND, "Last bar (strong bearish close) classified as BEAR_TREND");

   SBarInfo secondNewest;
   bc.GetBar(1, secondNewest); // source index 3
   Check(secondNewest.barType == BAR_INSIDE, "Synthetic inside bar is classified correctly");
   Check(secondNewest.range > 0.0, "Bar has non-zero range");
   Check(newest.upperWick >= 0.0 && newest.lowerWick >= 0.0, "Upper and lower wick geometry is non-negative");
   Check(newest.overlapPrev >= 0.0 && newest.overlapPrev <= 1.0, "Previous-bar overlap is normalized to 0..1");
   Check(newest.strength == STRENGTH_WEAK || newest.strength == STRENGTH_MODERATE || newest.strength == STRENGTH_STRONG,
         "Bar strength is assigned a defined classification");
   Check(newest.bearRun == 1, "Consecutive bear run is tracked");

   Check(bc.Count() == n, "Classifier stored all " + IntegerToString(n) + " bars");
  }

//+------------------------------------------------------------------+
//| Test 2: Pullback sequence numbering (H1/H2) in a clean bull leg  |
//+------------------------------------------------------------------+
void TestPullbackSequence()
  {
   Print("--- TestPullbackSequence ---");

   // Oldest-first: strong up, up, up (new high), pullback down (H1),
   // pullback down again but shallower (H2), then breakout up again.
   double o[] = {1.1000, 1.1020, 1.1040, 1.1055, 1.1050, 1.1052, 1.1070};
   double h[] = {1.1022, 1.1042, 1.1057, 1.1058, 1.1053, 1.1055, 1.1090};
   double l[] = {1.0998, 1.1018, 1.1038, 1.1045, 1.1044, 1.1048, 1.1069};
   double c[] = {1.1020, 1.1040, 1.1055, 1.1046, 1.1052, 1.1054, 1.1088};

   datetime time[]; double open[], high[], low[], close[];
   BuildSeries(o, h, l, c, time, open, high, low, close);
   int n = ArraySize(open);

   CBarClassifier bc(0.30, 100, 0.15);
   for(int i = n - 1; i >= 0; i--)
      bc.Update(i, time, open, high, low, close, n);

   // source index 3 (1.1058) still exceeds the 1.1057 high, so it resets the
   // leg extreme and is NOT a pullback bar -> series pos n-1-3 = 3
   SBarInfo extremeBar; bc.GetBar(3, extremeBar);
   Check(extremeBar.pullbackType == PB_NONE, "Bar that sets a marginal new leg high is not a pullback bar");

   // source index 4 (first bar that stays below the 1.1058 high) -> series pos n-1-4 = 2
   SBarInfo h1bar; bc.GetBar(2, h1bar);
   Check(h1bar.pullbackType == PB_H1, "First pullback bar after new high labeled H1");

   // source index 5 (second pullback bar) -> series pos n-1-5 = 1
   SBarInfo h2bar; bc.GetBar(1, h2bar);
   Check(h2bar.pullbackType == PB_H2, "Second consecutive pullback bar labeled H2");
   Check(h2bar.low > h1bar.low, "H2 low is shallower (higher) than H1 low in this synthetic leg");

   // source index 6 (new high, breaks 1.1058) -> series pos 0
   SBarInfo breakoutBar; bc.GetBar(0, breakoutBar);
   Check(breakoutBar.pullbackType == PB_NONE, "Bar that makes a fresh new high resets pullback state to NONE");
  }

//+------------------------------------------------------------------+
//| Test 3: Swing detection with a 1-bar fractal (fast to satisfy)   |
//+------------------------------------------------------------------+
void TestSwingDetection()
  {
   Print("--- TestSwingDetection ---");

   // Oldest-first: rises to a peak at index 2, then falls to a trough at index 4.
   double o[] = {1.1000, 1.1010, 1.1030, 1.1020, 1.1000, 1.1010};
   double h[] = {1.1012, 1.1032, 1.1040, 1.1022, 1.1002, 1.1015};
   double l[] = {1.0998, 1.1008, 1.1025, 1.0999, 1.0990, 1.1005};
   double c[] = {1.1010, 1.1028, 1.1035, 1.1001, 1.0995, 1.1012};

   datetime time[]; double open[], high[], low[], close[];
   BuildSeries(o, h, l, c, time, open, high, low, close);
   int n = ArraySize(open);

   CSwingDetector sd(1, 50); // 1-bar fractal so the small synthetic series is enough
   for(int i = n - 1; i >= 0; i--)
      sd.Update(i, time, open, high, low, close, n);

   SSwingPoint highSwing;
   bool foundHigh = sd.LatestOfType(SWING_HIGH, highSwing);
   Check(foundHigh, "A swing high was detected in the synthetic peak");
   if(foundHigh)
      Check(MathAbs(highSwing.price - 1.1040) < 0.00001, "Swing high price matches the synthetic peak (1.1040)");

   SSwingPoint lowSwing;
   bool foundLow = sd.LatestOfType(SWING_LOW, lowSwing);
   Check(foundLow, "A swing low was detected in the synthetic trough");
  }

//+------------------------------------------------------------------+
//| Test 4: Trading range detector flags a choppy, overlapping series|
//+------------------------------------------------------------------+
void TestTradingRangeDetection()
  {
   Print("--- TestTradingRangeDetection ---");

   // 25 heavily overlapping bars synthesized around a flat price —
   // should score as STATE_TRADING_RANGE with default thresholds.
   int n = 25;
   datetime time[]; double open[], high[], low[], close[];
   ArrayResize(time, n); ArrayResize(open, n); ArrayResize(high, n);
   ArrayResize(low, n);  ArrayResize(close, n);
   datetime t0 = D'2026.01.01 00:00';
   for(int i = 0; i < n; i++)
     {
      double wobble = (i % 2 == 0) ? 0.0003 : -0.0003;
      time[i]  = t0 + (n - i) * 3600;
      open[i]  = 1.1000 + wobble;
      close[i] = 1.1000 - wobble;
      high[i]  = 1.1000 + MathAbs(wobble) + 0.0001;
      low[i]   = 1.1000 - MathAbs(wobble) - 0.0001;
     }

   CTradingRangeDetector trd(20, 0.55, 3.0);
   for(int i = n - 1; i >= 0; i--)
      trd.Update(i, time, open, high, low, close, n);

   Check(trd.State() == STATE_TRADING_RANGE, "Choppy overlapping series scored as STATE_TRADING_RANGE");

   STradingRangeInfo ri;
   bool active = trd.GetRange(ri);
   Check(active, "Trading range info reports active=true");
  }

//+------------------------------------------------------------------+
//| Test 5: Pattern detector — Double Top on two near-equal swing highs|
//+------------------------------------------------------------------+
void TestPatternDetection()
  {
   Print("--- TestPatternDetection ---");

   SSwingPoint swings[4];
   // index 0 = most recent, per CSwingDetector's convention.
   swings[0].type = SWING_LOW;  swings[0].price = 1.0980; swings[0].barIndex = 0; swings[0].time = 0;
   swings[1].type = SWING_HIGH; swings[1].price = 1.1050; swings[1].barIndex = 2; swings[1].time = 0; // ~equal to swings[3]
   swings[2].type = SWING_LOW;  swings[2].price = 1.0985; swings[2].barIndex = 4; swings[2].time = 0;
   swings[3].type = SWING_HIGH; swings[3].price = 1.1052; swings[3].barIndex = 6; swings[3].time = 0;

   CPatternDetector pd(0.0015, 0.00020, 300);
   bool found = pd.AnalyzeSwings(swings, 4);
   Check(found, "Pattern detector finds a pattern in near-equal swing highs");

   SPatternInfo p = pd.LastPattern();
   Check(p.type == PATTERN_DOUBLE_TOP, "Near-equal consecutive swing highs classified as PATTERN_DOUBLE_TOP");
  }

//+------------------------------------------------------------------+
//| Test 5b: Pattern slopes are normalized and stable               |
//|                                                                  |
//| The triangle branch used to compare a raw price-per-bar-index    |
//| slope against a 0.15 threshold. On a 1.10 instrument that slope  |
//| is ~0.0025, so the branch was unreachable and PATTERN_TRIANGLE   |
//| could never be produced. These cases pin the replacement:        |
//| convergence is measured as a fraction of price per bar, keyed   |
//| off swing TIMESTAMPS.                                            |
//+------------------------------------------------------------------+
void TestNormalizedPatternSlopes()
  {
   Print("--- TestNormalizedPatternSlopes ---");

   const int SECS_PER_BAR = 300;   // M5
   const double CONVERGENCE_MIN = 0.00020;

   // --- the helper itself -------------------------------------------
   datetime tOld = D'2026.01.01 00:00';
   datetime tNew = tOld + 10 * SECS_PER_BAR;

   double rising = CPabUtils::NormalizedSlopePerBar(tOld, 1.1000, tNew, 1.1100, SECS_PER_BAR);
   Check(rising > 0.0, "Normalized slope is positive when price rose over time");

   double falling = CPabUtils::NormalizedSlopePerBar(tOld, 1.1000, tNew, 1.0900, SECS_PER_BAR);
   Check(falling < 0.0, "Normalized slope is negative when price fell over time");

   Check(MathAbs(rising + falling) < 1e-12,
         "A symmetric move up and down produces equal-magnitude slopes");

   // Fraction of price per bar: 0.0100 off a 1.1000 reference is +0.9091%
   // spread over 10 bars, so the expected slope is 0.00090909...
   Check(MathAbs(rising - (0.0100 / 1.1000) / 10.0) < 1e-12,
         "Slope equals price fraction divided by bars elapsed");

   // The same +0.9091% move at a 3400 reference, so the geometry really is
   // identical once prices are expressed as a fraction of their own scale.
   double scaled = CPabUtils::NormalizedSlopePerBar(tOld, 3400.0, tNew, 3400.0 * 1.1100 / 1.1000, SECS_PER_BAR);
   Check(MathAbs(scaled - rising) < 1e-12,
         "Identical percentage geometry gives an identical slope at 1.10 and at 3400");

   Check(CPabUtils::NormalizedSlopePerBar(tOld, 1.1000, tOld, 1.1100, SECS_PER_BAR) == 0.0,
         "Two swings at the same timestamp have no measurable slope");
   Check(CPabUtils::NormalizedSlopePerBar(tOld, 1.1000, tOld + 60, 1.1100, SECS_PER_BAR) == 0.0,
         "Two swings less than one bar apart have no measurable slope");
   Check(CPabUtils::NormalizedSlopePerBar(tOld, 1.1000, tNew, 1.1100, 0) == 0.0,
         "A zero bar length yields no slope instead of a division by zero");
   Check(CPabUtils::NormalizedSlopePerBar(tOld, 0.0, tNew, 1.1100, SECS_PER_BAR) == 0.0,
         "A non-positive reference price yields no slope");

   // --- a converging structure on EURUSD-scale prices ---------------
   // highs fall, lows rise, and neither pair is close enough to be a
   // double top/bottom, so the only reachable verdict is a triangle.
   datetime t0 = D'2026.01.01 12:00';
   SSwingPoint eurusd[4];
   eurusd[0].type = SWING_HIGH; eurusd[0].price = 1.1020; eurusd[0].barIndex = 0; eurusd[0].time = t0;
   eurusd[1].type = SWING_LOW;  eurusd[1].price = 1.1010; eurusd[1].barIndex = 1; eurusd[1].time = t0 + 60;
   eurusd[2].type = SWING_HIGH; eurusd[2].price = 1.1060; eurusd[2].barIndex = 9; eurusd[2].time = t0 - 2940;
   eurusd[3].type = SWING_LOW;  eurusd[3].price = 1.0980; eurusd[3].barIndex = 10; eurusd[3].time = t0 - 3000;

   CPatternDetector tri(0.0015, CONVERGENCE_MIN, SECS_PER_BAR);
   tri.AnalyzeSwings(eurusd, 4);
   SPatternInfo triPattern = tri.LastPattern();
   Check(triPattern.type == PATTERN_TRIANGLE,
         "Converging highs and lows are now classified as PATTERN_TRIANGLE");

   // --- the same percentage geometry at gold-scale prices ------------
   const double K = 3400.0 / 1.10;
   SSwingPoint gold[4];
   gold[0].type = eurusd[0].type; gold[0].price = 1.1020 * K; gold[0].barIndex = 0; gold[0].time = t0;
   gold[1].type = eurusd[1].type; gold[1].price = 1.1010 * K; gold[1].barIndex = 1; gold[1].time = t0 + 60;
   gold[2].type = eurusd[2].type; gold[2].price = 1.1060 * K; gold[2].barIndex = 9; gold[2].time = t0 - 2940;
   gold[3].type = eurusd[3].type; gold[3].price = 1.0980 * K; gold[3].barIndex = 10; gold[3].time = t0 - 3000;

   CPatternDetector triGold(0.0015, CONVERGENCE_MIN, SECS_PER_BAR);
   triGold.AnalyzeSwings(gold, 4);
   Check(triGold.LastPattern().type == PATTERN_TRIANGLE,
         "The same convergence is detected at 3400-scale prices, so the threshold is scale-free");

   // --- diverging structure must NOT be called a triangle -----------
   SSwingPoint diverging[4];
   diverging[0].type = SWING_HIGH; diverging[0].price = 1.1100; diverging[0].barIndex = 0; diverging[0].time = t0;
   diverging[1].type = SWING_LOW;  diverging[1].price = 1.0940; diverging[1].barIndex = 1; diverging[1].time = t0 + 60;
   diverging[2].type = SWING_HIGH; diverging[2].price = 1.1060; diverging[2].barIndex = 9; diverging[2].time = t0 - 2940;
   diverging[3].type = SWING_LOW;  diverging[3].price = 1.0980; diverging[3].barIndex = 10; diverging[3].time = t0 - 3000;

   CPatternDetector div(0.0015, CONVERGENCE_MIN, SECS_PER_BAR);
   bool divFound = div.AnalyzeSwings(diverging, 4);
   Check(!divFound || div.LastPattern().type != PATTERN_TRIANGLE,
         "Widening structure is not reported as a converging triangle");

   // --- swings with no time separation cannot claim convergence ------
   SSwingPoint noTime[4];
   noTime[0].type = SWING_HIGH; noTime[0].price = 1.1020; noTime[0].barIndex = 0; noTime[0].time = 0;
   noTime[1].type = SWING_LOW;  noTime[1].price = 1.1010; noTime[1].barIndex = 1; noTime[1].time = 0;
   noTime[2].type = SWING_HIGH; noTime[2].price = 1.1060; noTime[2].barIndex = 9; noTime[2].time = 0;
   noTime[3].type = SWING_LOW;  noTime[3].price = 1.0980; noTime[3].barIndex = 10; noTime[3].time = 0;

   CPatternDetector untimed(0.0015, CONVERGENCE_MIN, SECS_PER_BAR);
   bool untimedFound = untimed.AnalyzeSwings(noTime, 4);
   Check(!untimedFound || untimed.LastPattern().type != PATTERN_TRIANGLE,
         "Swings with no time separation are not reported as converging");
  }

//+------------------------------------------------------------------+
//| Test 6: Breakout bar and Climax/exhaustion bar detection (Phase 3)|
//+------------------------------------------------------------------+
void TestBreakoutAndClimax()
  {
   Print("--- TestBreakoutAndClimax ---");

   // Oldest-first: five modest, similar-range up bars (baseline average
   // range), then a strong breakout bar making a fresh high with a close
   // near its top (favorable CLV) — should flag isBreakoutBar.
   double o[] = {1.1000, 1.1010, 1.1020, 1.1030, 1.1040, 1.1050};
   double h[] = {1.1012, 1.1022, 1.1032, 1.1042, 1.1052, 1.1090};
   double l[] = {1.0999, 1.1009, 1.1019, 1.1029, 1.1039, 1.1049};
   double c[] = {1.1011, 1.1021, 1.1031, 1.1041, 1.1051, 1.1088};

   datetime time[]; double open[], high[], low[], close[];
   BuildSeries(o, h, l, c, time, open, high, low, close);
   int n = ArraySize(open);

   // breakoutLookback=5 so the whole synthetic history counts as "recent".
   CBarClassifier bc(0.30, 100, 0.15, 5, 0.5, 20, 2.0, 0.35);
   for(int i = n - 1; i >= 0; i--)
      bc.Update(i, time, open, high, low, close, n);

   SBarInfo newest; bc.GetBar(0, newest);
   Check(newest.isBreakoutBar, "Strong fresh-high bar with favorable close flagged as breakout bar");

   // --- separate series for the climax check: baseline small-range bars,
   //     then one unusually large-range bar with a weak/indecisive close.
   double co[] = {1.1000, 1.1005, 1.1002, 1.1006, 1.1003, 1.1020};
   double ch[] = {1.1006, 1.1011, 1.1008, 1.1012, 1.1009, 1.1080};
   double cl[] = {1.0996, 1.1001, 1.0998, 1.1002, 1.0999, 1.1010};
   double cc[] = {1.1004, 1.1003, 1.1006, 1.1004, 1.1005, 1.1045}; // last bar closes mid-range (weak)

   datetime ctime[]; double copen[], chigh[], clow[], cclose[];
   BuildSeries(co, ch, cl, cc, ctime, copen, chigh, clow, cclose);
   int cn = ArraySize(copen);

   CBarClassifier bc2(0.30, 100, 0.15, 5, 0.5, 5, 2.0, 0.60);
   for(int i = cn - 1; i >= 0; i--)
      bc2.Update(i, ctime, copen, chigh, clow, cclose, cn);

   SBarInfo climaxBar; bc2.GetBar(0, climaxBar);
   Check(climaxBar.isClimax, "Unusually large-range bar with a weak close flagged as climax/exhaustion");
  }

//+------------------------------------------------------------------+
//| Test 7: Always-In tracker flips on a structural swing break      |
//+------------------------------------------------------------------+
void TestAlwaysIn()
  {
   Print("--- TestAlwaysIn ---");

   CAlwaysInTracker ai;
   Check(ai.State() == ALWAYS_IN_NONE, "Always-In starts at NONE with no structure yet");

   // Bootstrap long: close breaks above the only known swing high.
   ai.Evaluate(1.1100, true, 1.1050, false, 0.0, D'2026.01.01 01:00');
   Check(ai.State() == ALWAYS_IN_LONG, "Close above the known swing high bootstraps ALWAYS_IN_LONG");

   // Now flip short: close breaks below a known swing low.
   ai.Evaluate(1.0900, true, 1.1150, true, 1.0950, D'2026.01.01 02:00');
   Check(ai.State() == ALWAYS_IN_SHORT, "Close below the known swing low flips state to ALWAYS_IN_SHORT");

   // A close that does NOT break the opposite swing should hold the state.
   ai.Evaluate(1.0960, true, 1.1150, true, 1.0950, D'2026.01.01 03:00');
   Check(ai.State() == ALWAYS_IN_SHORT, "State holds ALWAYS_IN_SHORT when no structural break occurs");
  }

//+------------------------------------------------------------------+
//| Test 8: Measured Move projection from three alternating swings   |
//+------------------------------------------------------------------+
void TestMeasuredMove()
  {
   Print("--- TestMeasuredMove ---");

   SSwingPoint swings[3];
   // index 0 = most recent (the pivot to project FROM).
   swings[0].type = SWING_LOW;  swings[0].price = 1.1000; swings[0].time = D'2026.01.01 03:00'; // pivot
   swings[1].type = SWING_HIGH; swings[1].price = 1.1100; swings[1].time = D'2026.01.01 02:00'; // leg1 end
   swings[2].type = SWING_LOW;  swings[2].price = 1.1020; swings[2].time = D'2026.01.01 01:00'; // leg1 start

   CMeasuredMoveDetector mmd;
   bool found = mmd.AnalyzeSwings(swings, 3);
   Check(found, "Measured move detector finds a projection from a clean 3-swing sequence");

   SMeasuredMoveInfo mm = mmd.Current();
   double expectedLeg = MathAbs(1.1100 - 1.1020); // 0.0080
   double expectedTarget = 1.1000 + expectedLeg;   // bullish leg1 -> project up from the pivot low
   Check(mm.isBullish, "Rising leg1 (low->high) projects a bullish measured move");
   Check(MathAbs(mm.targetPrice - expectedTarget) < 0.00001,
         "Target price equals pivot + leg1 size (" + DoubleToString(expectedTarget, 5) + ")");
  }

void TestIdempotentUpdates()
  {
   Print("--- TestIdempotentUpdates ---");

   double o[] = {1.1000, 1.1020, 1.1010};
   double h[] = {1.1010, 1.1030, 1.1020};
   double l[] = {1.0990, 1.1010, 1.1000};
   double c[] = {1.1005, 1.1025, 1.1015};

   datetime time[]; double open[], high[], low[], close[];
   BuildSeries(o, h, l, c, time, open, high, low, close);
   int n = ArraySize(open);

   CBarClassifier bc;
   bc.Update(0, time, open, high, low, close, n);
   bc.Update(0, time, open, high, low, close, n);
   Check(bc.Count() == 1, "Duplicate classifier update does not duplicate the bar");

   CSwingDetector sd(1);
   sd.Update(0, time, open, high, low, close, n);
   sd.Update(0, time, open, high, low, close, n);
   Check(sd.Count() == 1, "Duplicate swing update does not duplicate the confirmed swing");
  }

void TestRangeTransitionClearsRange()
  {
   Print("--- TestRangeTransitionClearsRange ---");

   int n = 40;
   datetime time[]; double open[], high[], low[], close[];
   ArrayResize(time, n); ArrayResize(open, n); ArrayResize(high, n);
   ArrayResize(low, n); ArrayResize(close, n);
   datetime t0 = D'2026.01.01 00:00';

   for(int i = 0; i < n; i++)
     {
      time[i] = t0 + (n - i) * 3600;
      if(i < 20)
        {
         double price = 1.1000 + (19 - i) * 0.00004;
         open[i] = price - 0.00001;
         high[i] = price + 0.00001;
         low[i] = price - 0.00002;
         close[i] = price;
        }
      else
        {
         double wobble = (i % 2 == 0) ? 0.0003 : -0.0003;
         open[i] = 1.1000 + wobble;
         high[i] = 1.1000 + MathAbs(wobble) + 0.0001;
         low[i] = 1.1000 - MathAbs(wobble) - 0.0001;
         close[i] = 1.1000 - wobble;
        }
     }

   CTradingRangeDetector trd(20, 0.55, 30.0);
   for(int i = n - 1; i >= 0; i--)
      trd.Update(i, time, open, high, low, close, n);

   STradingRangeInfo ri;
   Check(trd.State() == STATE_TRANSITION, "Low-displacement non-overlapping bars scored as STATE_TRANSITION");
   Check(!trd.GetRange(ri), "Transition state clears stale trading-range data");
  }

void TestContextAndDecision()
  {
   Print("--- TestContextAndDecision ---");

   // ContextAnalyzer consumes SERIES order: index 0 is the newest closed bar.
   SBarInfo bars[3];
   for(int i = 0; i < 3; i++)
     {
      bars[i].Clear();
      bars[i].time = D'2026.01.01 05:00' - i * 3600;
      bars[i].open = 1.1020 - i * 0.0010;
      bars[i].high = bars[i].open + 0.0010;
      bars[i].low = bars[i].open - 0.0002;
      bars[i].close = bars[i].open + 0.0008;
      bars[i].range = 0.0012;
      bars[i].bodyRatio = 0.66;
      bars[i].clv = 0.83;
      bars[i].isBullish = true;
      bars[i].barType = BAR_BULL_TREND;
      bars[i].strength = STRENGTH_STRONG;
      bars[i].overlapPrev = 0.25;
     }

   SContextInfo context;
   SSwingPoint swings[1];
   CContextAnalyzer analyzer;
   analyzer.Analyze(bars, 3, swings, 0, STATE_BULL_TREND, ALWAYS_IN_LONG, context);
   Check(context.valid, "Context analyzer produces a valid closed-bar snapshot");
   Check(context.microState == STATE_BULL_TREND, "Bullish micro context is classified from displacement");
   Check(context.bullPressure > context.bearPressure, "Bull pressure exceeds bear pressure in bull context");

   bars[0].pullbackType = PB_H2;
   bars[0].signalQuality = QUALITY_STRONG;
   bars[0].hasFollowThrough = true;
   context.nearSupport = true;
   context.support = bars[0].low - 0.0002;
   context.resistance = 0.0;

   SPatternInfo pattern;
   pattern.type = PATTERN_NONE;
   SMeasuredMoveInfo measuredMove;
   measuredMove.active = false;
   SSetupCandidate candidate;
   CDecisionEngine engine(55, 1.5);
   engine.Analyze(bars[0], context, pattern, measuredMove, candidate);
   Check(candidate.direction == SETUP_LONG, "Bullish H2 context produces a long candidate");
   Check(candidate.type == SETUP_SECOND_ENTRY, "H2 is classified as a second-entry setup");
   Check(candidate.stopPrice < candidate.entryPrice && candidate.targetPrice > candidate.entryPrice,
         "Long candidate exposes logical invalidation and target levels");
   Check(candidate.qualityScore >= 55 && candidate.status != STATUS_NO_TRADE,
         "Strong composed context passes configured quality and risk/reward gates");

   SBarInfo noTradeBar;
   noTradeBar.Clear();
   noTradeBar.time = bars[0].time + 3600;
   noTradeBar.open = 1.1000;
   noTradeBar.high = 1.1005;
   noTradeBar.low = 1.0995;
   noTradeBar.close = 1.1000;
   noTradeBar.range = 0.0010;
   noTradeBar.barType = BAR_DOJI;
   noTradeBar.pullbackType = PB_NONE;
   engine.Analyze(noTradeBar, context, pattern, measuredMove, candidate);
   Check(candidate.status == STATUS_NO_TRADE, "Isolated doji without composed setup returns NO TRADE");
  }

//+------------------------------------------------------------------+
//| Test 12: Target must lie beyond entry, and NO TRADE must not      |
//|          carry a direction or levels (Phase 16)                  |
//|                                                                  |
//| Found by replaying a real year of EURUSD M5 and reading the      |
//| export, not by a failing test:                                    |
//|   - 6,025 of 72,188 rows had the target on the wrong side of     |
//|     entry, because a measured-move projection was adopted on     |
//|     direction alignment alone. reward/risk then took an absolute |
//|     value, so an unreachable target scored a healthy R:R.        |
//|   - The resistance clamp could leave a target a hair beyond      |
//|     entry, which exports as the same printed price as entry.     |
//|   - Rejected setups kept direction=long and stale price levels,  |
//|     so status=no_trade rows contradicted the export schema.      |
//+------------------------------------------------------------------+
void TestTargetAndNoTradeContract()
  {
   Print("--- TestTargetAndNoTradeContract ---");

   SBarInfo bar;
   bar.Clear();
   bar.time = D'2026.01.01 05:00';
   bar.open = 1.1000;
   bar.high = 1.1010;
   bar.low = 1.0990;
   bar.close = 1.1005;
   bar.range = 0.0020;
   bar.bodyRatio = 0.25;
   bar.clv = 0.75;
   bar.isBullish = true;
   bar.barType = BAR_BULL_TREND;
   bar.strength = STRENGTH_STRONG;
   bar.pullbackType = PB_H1;
   bar.signalQuality = QUALITY_STRONG;
   bar.hasFollowThrough = true;

   SContextInfo context;
   ZeroMemory(context);
   context.valid = true;
   context.microState = STATE_BULL_TREND;
   context.mediumState = STATE_BULL_TREND;
   context.bullPressure = 0.70;
   context.bearPressure = 0.30;
   context.nearSupport = true;
   context.support = 1.0990;
   context.resistance = 0.0;

   SPatternInfo pattern;
   ZeroMemory(pattern);
   pattern.type = PATTERN_NONE;
   SSetupCandidate candidate;
   CDecisionEngine engine(55, 1.5);

   // --- a measured move pointing the wrong way must be ignored ------
   SMeasuredMoveInfo wrongWay;
   ZeroMemory(wrongWay);
   wrongWay.active = true;
   wrongWay.isBullish = false;        // bearish projection on a long
   wrongWay.targetPrice = 1.0900;     // far BELOW entry
   engine.Analyze(bar, context, pattern, wrongWay, candidate);
   Check(candidate.status != STATUS_NO_TRADE &&
         candidate.targetPrice > candidate.entryPrice + _Point,
         "A measured move on the wrong side of a long cannot set the target");

   // --- a correctly-directed move that lands short of entry ---------
   // Right direction, but only half a point beyond entry. The engine must
   // IGNORE this projection and keep the baseline target, not adopt it and
   // then reject the whole setup as NO TRADE. Getting that wrong is what
   // the first headless run of this suite caught.
   SMeasuredMoveInfo tooClose;
   ZeroMemory(tooClose);
   tooClose.active = true;
   tooClose.isBullish = true;                        // right direction...
   tooClose.targetPrice = bar.close + 0.5 * _Point;  // ...but far too near
   engine.Analyze(bar, context, pattern, tooClose, candidate);
   Check(candidate.status != STATUS_NO_TRADE,
         "A near-miss measured move does not turn a usable setup into NO TRADE");
   Check(candidate.targetPrice > candidate.entryPrice + _Point,
         "A near-miss measured move is ignored and the baseline target is kept");

   // --- resistance a hair above entry must not clamp onto entry -----
   context.resistance = candidate.entryPrice + 0.000001;
   engine.Analyze(bar, context, pattern, wrongWay, candidate);
   Check(candidate.status == STATUS_NO_TRADE ||
         candidate.targetPrice > candidate.entryPrice + _Point,
         "Resistance a hair above entry does not pull the target onto entry");
   context.resistance = 0.0;

   // --- a healthy long setup keeps valid levels ---------------------
   engine.Analyze(bar, context, pattern, wrongWay, candidate);
   Check(candidate.status != STATUS_NO_TRADE, "A composed long setup is not rejected");
   Check(candidate.direction == SETUP_LONG, "The composed setup is a long");
   Check(candidate.stopPrice < candidate.entryPrice && candidate.targetPrice > candidate.entryPrice,
         "Long levels are strictly ordered invalidation < entry < target");

   // --- a rejected setup must not leak direction or levels ----------
   SBarInfo doji;
   doji.Clear();
   doji.time = D'2026.01.01 06:00';
   doji.open = 1.1000;
   doji.high = 1.1005;
   doji.low = 1.0995;
   doji.close = 1.1000;
   doji.range = 0.0010;
   doji.barType = BAR_DOJI;
   doji.pullbackType = PB_NONE;

   SContextInfo empty;
   ZeroMemory(empty);
   empty.valid = false;
   engine.Analyze(doji, empty, pattern, wrongWay, candidate);
   Check(candidate.status == STATUS_NO_TRADE, "Insufficient context is a NO TRADE");
   Check(candidate.direction == SETUP_NONE,
         "A NO TRADE carries direction none, never a leftover direction");
   Check(candidate.entryPrice == 0.0 && candidate.stopPrice == 0.0 &&
         candidate.targetPrice == 0.0 && candidate.riskReward == 0.0,
         "A NO TRADE carries no price levels, so it cannot be read as a proposal");
  }

//+------------------------------------------------------------------+
//| Test 13: A failed breakout requires that a breakout happened    |
//|                                                                  |
//| The old test only asked whether the current bar was below the    |
//| swing high, which is true for nearly every bar that has not     |
//| broken out. A real replay classified 53,329 of 72,188 events as  |
//| SETUP_FAILED_BREAKOUT, 74 percent of the sample, which made     |
//| every aggregate figure a restatement of one over-triggered rule. |
//+------------------------------------------------------------------+
void TestFailedBreakoutRequiresAnActualBreakout()
  {
   Print("--- TestFailedBreakoutRequiresAnActualBreakout ---");

   // One confirmed swing high at 1.1050, and one swing low at 1.0980.
   SSwingPoint swings[2];
   swings[0].type = SWING_LOW;  swings[0].price = 1.0980;
   swings[0].barIndex = 8;      swings[0].time = D'2026.01.01 04:40';
   swings[1].type = SWING_HIGH; swings[1].price = 1.1050;
   swings[1].barIndex = 4;      swings[1].time = D'2026.01.01 04:20';

   SBarInfo bars[3];
   for(int i = 0; i < 3; i++)
     {
      bars[i].Clear();
      bars[i].time = D'2026.01.01 05:00' - i * 300;
      bars[i].open = 1.1010;
      bars[i].high = 1.1020;
      bars[i].low = 1.1000;
      bars[i].close = 1.1015;
      bars[i].range = 0.0020;
      bars[i].bodyRatio = 0.25;
      bars[i].isBullish = true;
      bars[i].clv = 0.75;
      bars[i].overlapPrev = 0.2;
     }

   CContextAnalyzer analyzer;
   SContextInfo context;

   // Case A: nothing ever traded above the swing high. The current bar is
   // bullish and below resistance, which the OLD rule called a failed
   // breakout. It is not one.
   analyzer.Analyze(bars, 3, swings, 2, STATE_TRADING_RANGE, ALWAYS_IN_NONE, context);
   Check(!context.failedBullBreakout,
         "A bullish bar under resistance is not a failed breakout");

   // Case B: an earlier bar poked above 1.1050 and the current bar closed
   // back below it. That IS a failed breakout.
   bars[1].high = 1.1055;
   bars[1].close = 1.1052;
   bars[1].isBullish = true;
   analyzer.Analyze(bars, 3, swings, 2, STATE_TRADING_RANGE, ALWAYS_IN_NONE, context);
   Check(context.failedBullBreakout,
         "A bar that poked above resistance and closed back below is a failed breakout");

   // Case C: a poke on the current bar itself, rejected immediately.
   bars[1].high = 1.1020;
   bars[1].close = 1.1015;
   bars[0].high = 1.1056;
   bars[0].close = 1.1012;
   analyzer.Analyze(bars, 3, swings, 2, STATE_TRADING_RANGE, ALWAYS_IN_NONE, context);
   Check(context.failedBullBreakout,
         "A single-bar poke above resistance rejected in the same bar counts");

   // Case D: the mirror image on the downside.
   SSwingPoint lows[2];
   lows[0].type = SWING_HIGH; lows[0].price = 1.1050;
   lows[0].barIndex = 8;      lows[0].time = D'2026.01.01 04:40';
   lows[1].type = SWING_LOW;  lows[1].price = 1.0980;
   lows[1].barIndex = 4;      lows[1].time = D'2026.01.01 04:20';

   for(int i = 0; i < 3; i++)
     {
      bars[i].high = 1.1010;
      bars[i].low = 1.1000;
      bars[i].open = 1.1005;
      bars[i].close = 1.1002;
      bars[i].isBullish = false;
     }
   analyzer.Analyze(bars, 3, lows, 2, STATE_TRADING_RANGE, ALWAYS_IN_NONE, context);
   Check(!context.failedBearBreakout,
         "A bearish bar above support is not a failed breakdown");

   bars[1].low = 1.0975;
   bars[1].close = 1.0978;
   analyzer.Analyze(bars, 3, lows, 2, STATE_TRADING_RANGE, ALWAYS_IN_NONE, context);
   Check(context.failedBearBreakout,
         "A bar that poked below support and closed back above is a failed breakdown");
  }


//+------------------------------------------------------------------+
//| Test 14: Execution costs convert cleanly into R (Phase 19)       |
//|                                                                  |
//| Everything measured before Phase 19 was gross. The measured     |
//| edge was around +0.02R and realistic costs on EURUSD are a     |
//| couple of tenths of an R, so the sign of the net figure was     |
//| never established. These assertions pin the arithmetic that     |
//| turns a broker spread plus an assumed slippage and commission   |
//| into an R figure, because a silent error here does not produce  |
//| a crash, it produces a plausible wrong number.                   |
//+------------------------------------------------------------------+
void TestTradingCost()
  {
   Print("--- TestTradingCost ---");

   SCostModel free;
   free.spreadPrice = 0.0;  free.spreadPoints = 0.0;  free.spreadMeasured = true;
   free.slippagePrice = 0.0; free.slippagePoints = 0.0; free.commissionPrice = 0.0;
   Check(MathAbs(CTradingCost::RoundTripCostPrice(free)) < 1e-12,
         "A zero cost model costs nothing");
   Check(CTradingCost::CostInR(free, 1.1000, 1.0980) == 0.0,
         "A zero cost model is 0.0R at any stop distance");

   // --- spread alone, on a 20-point stop -----------------------------
   // 0.00020 spread over a 0.00200 stop is a tenth of an R. This is the
   // single most important ratio in the file: it is why a +0.02R gross
   // edge cannot survive contact with a real spread.
   SCostModel spread;
   spread.spreadPrice = 0.00020; spread.spreadPoints = 20.0; spread.spreadMeasured = true;
   spread.slippagePrice = 0.0; spread.slippagePoints = 0.0; spread.commissionPrice = 0.0;
   Check(MathAbs(CTradingCost::CostInR(spread, 1.1000, 1.0980) - 0.10) < 1e-9,
         "A 0.00020 spread against a 0.00200 stop is 0.10R");

   // The same spread against a much wider stop is proportionally cheaper.
   Check(MathAbs(CTradingCost::CostInR(spread, 1.1000, 1.0900) - 0.02) < 1e-9,
         "Cost in R falls when the stop distance widens, holding spread fixed");

   // --- slippage is charged on BOTH sides -----------------------------
   SCostModel slipped = spread;
   slipped.slippagePrice = 0.00005;  // 5 points per side
   slipped.slippagePoints = 5.0;
   Check(MathAbs(CTradingCost::RoundTripCostPrice(slipped) - 0.00030) < 1e-12,
         "A 0.00005 per-side slippage costs 0.00010 round trip on top of a 0.00020 spread");
   Check(MathAbs(CTradingCost::CostInR(slipped, 1.1000, 1.0980) - 0.15) < 1e-9,
         "Spread plus two-sided slippage is 0.15R against a 0.00200 stop");

   // --- commission converts from currency to a price distance ---------
   // A USD account on EURUSD: one 0.00001 point move is worth $1.00 per
   // lot, so $7.00 round trip per lot is a 0.00007 price distance.
   double commissionPrice = CTradingCost::CommissionPriceFromPerLot(7.0, 1.0, 1.0, 0.00001);
   Check(MathAbs(commissionPrice - 0.00007) < 1e-12,
         "A $7.00 per-lot round-trip commission is a 0.00007 price distance at $1/tick/lot");

   // A larger position costs proportionally more of the same price move.
   double commission10 = CTradingCost::CommissionPriceFromPerLot(7.0, 10.0, 1.0, 0.00001);
   Check(MathAbs(commission10 - 0.000007) < 1e-12,
         "Commission price distance scales inversely with lot size");

   // Unavailable broker facts must not become a free or infinite cost.
   Check(CTradingCost::CommissionPriceFromPerLot(7.0, 1.0, 0.0, 0.00001) == 0.0,
         "An unavailable tick value yields 0.0 rather than a division by zero");
   Check(CTradingCost::CommissionPriceFromPerLot(7.0, 0.0, 1.0, 0.00001) == 0.0,
         "A zero lot size yields 0.0 rather than a division by zero");
   Check(CTradingCost::CommissionPriceFromPerLot(0.0, 1.0, 1.0, 0.00001) == 0.0,
         "A zero commission is 0.0 price distance");

   // --- a NO TRADE row has no stop, so its cost in R is 0.0 ----------
   Check(CTradingCost::CostInR(spread, 0.0, 0.0) == 0.0,
         "A row with no levels yields 0.0R instead of dividing by zero");

   // --- the label must disclose what was assumed ----------------------
   SCostModel assumed = spread;
   assumed.spreadMeasured = false;
   Check(StringFind(assumed.Model(), "assumed") >= 0,
         "A configured fallback spread is labelled as assumed, not measured");
   Check(StringFind(spread.Model(), "assumed") < 0,
         "A measured spread with no other assumption is not labelled as assumed");
   Check(StringFind(slipped.Model(), "assumed") >= 0,
         "An assumed slippage is labelled as assumed");
  }


//+------------------------------------------------------------------+
//| PHASE 21. The engine configuration the harness uses. The values  |
//| mirror BuildEngineConfig() in PriceActionBarByBar.mq5, spelled   |
//| out because a test has no inputs. BuildSeries spaces its bars    |
//| one hour apart, so secondsPerBar is 3600: the pattern slopes the |
//| engine computes inside a pipeline run are only meaningful if the |
//| seconds-per-bar matches the fixture's real spacing.              |
//+------------------------------------------------------------------+
void DefaultEngineConfig(SEngineConfig &cfg)
  {
   cfg.dojiBodyRatio      = 0.30;
   cfg.clvFavorableMin    = 0.15;
   cfg.featureLookback    = 20;
   cfg.largeRangeMult     = 1.50;
   cfg.smallRangeMult     = 0.70;
   cfg.strongBodyRatio    = 0.60;
   cfg.historyCapacity    = 2000;
   cfg.breakoutLookback   = 10;
   cfg.breakoutClvMin     = 0.50;
   cfg.climaxLookback     = 20;
   cfg.climaxRangeMult    = 2.0;
   cfg.climaxBodyRatioMax = 0.35;
   cfg.fractalLegs        = 2;
   cfg.swingCapacity      = 500;
   cfg.regimeLookback     = 20;
   cfg.overlapThreshold   = 0.55;
   cfg.displaceThreshold  = 3.0;
   // No ATR series is injected in this harness, so the range
   // detector's internal average is the normalizer under test.
   // useRealAtr only matters once RefreshAtr() is called, which
   // needs a live iATR handle and is deliberately not exercised
   // here.
   cfg.useRealAtr         = false;
   cfg.atrPeriod          = 14;
   cfg.swingSimilarityPct = 0.0015;  // 0.15 percent
   cfg.convergenceMin     = 0.00020;
   cfg.secondsPerBar      = 3600;
   cfg.minimumQuality     = 55;
   cfg.minimumRiskReward  = 1.50;
   cfg.contextBars        = 10;
  }

//+------------------------------------------------------------------+
//| PHASE 21. The pipeline as a whole: ProcessBar feeds bars in,   |
//| Evaluate turns accumulated state into a decision. This is the    |
//| layer the chart indicator and the historical replay share, so    |
//| its lifecycle contracts are the ones a real run depends on:      |
//|                                                                    |
//|   - index 0 (the forming bar) never enters the pipeline       |
//|   - a decision is stamped with the newest CLOSED bar            |
//|   - re-processing a bar (a duplicate tick) is a no-op          |
//|   - the same bars always produce the same decision, so a        |
//|     history reload cannot change what the chart already drew     |
//+------------------------------------------------------------------+
void TestEnginePipeline()
  {
   Print("--- TestEnginePipeline ---");

   // A clean bull leg with an H2 pullback, OLDEST FIRST, routed
   // through BuildSeries so the arrays land in series order
   // (index 0 = newest) exactly as OnCalculate receives them.
   double o[] = {1.1000, 1.1020, 1.1040, 1.1055, 1.1050, 1.1052, 1.1070};
   double h[] = {1.1022, 1.1042, 1.1057, 1.1058, 1.1053, 1.1055, 1.1090};
   double l[] = {1.0998, 1.1018, 1.1038, 1.1045, 1.1044, 1.1048, 1.1069};
   double c[] = {1.1020, 1.1040, 1.1055, 1.1046, 1.1052, 1.1054, 1.1088};

   datetime time[]; double open[], high[], low[], close[];
   BuildSeries(o, h, l, c, time, open, high, low, close);
   int n = ArraySize(open);

   CPabEngine *engine = new CPabEngine();
   SEngineConfig cfg;
   DefaultEngineConfig(cfg);
   Check(engine.Init(cfg, "EURUSD", PERIOD_H1),
         "CPabEngine.Init allocates the whole analyzer pipeline");

   //--- an engine that has processed nothing has nothing to decide ---
   SSetupCandidate candidate;
   Check(!engine.Evaluate(0.0, 0, candidate),
         "Evaluate on an engine with no processed bar returns false");

   //--- feed CLOSED bars only: index 0 is forming and must never
   //    enter the pipeline, which is the indicator's closed-bar gate
   for(int i = n - 1; i >= 1; i--)
      engine.ProcessBar(i, time, open, high, low, close, n);

   Check(engine.BarCount() == n - 1,
         "ProcessBar stores every closed bar it is given");

   Check(engine.Evaluate(close[1], time[1], candidate),
         "Evaluate succeeds once at least one closed bar is processed");
   Check(candidate.barTime == time[1],
         "The decision is stamped with the newest CLOSED bar, never the forming bar");
   Check(engine.Context().valid,
         "The engine produces a valid context snapshot");

   //--- the levels contract: any live setup keeps its levels strictly
   //    ordered, whichever direction it points in
   if(candidate.active && candidate.direction != SETUP_NONE)
     {
      if(candidate.direction == SETUP_LONG)
         Check(candidate.stopPrice < candidate.entryPrice &&
               candidate.targetPrice > candidate.entryPrice,
               "A live long setup keeps invalidation < entry < target");
      else
         Check(candidate.targetPrice < candidate.entryPrice &&
               candidate.stopPrice > candidate.entryPrice,
               "A live short setup keeps target < entry < invalidation");
     }

   //--- duplicate tick: re-processing the bar that was just processed
   //    must be a no-op, not a second copy of the same bar
   int barsBefore = engine.BarCount();
   engine.ProcessBar(1, time, open, high, low, close, n);
   Check(engine.BarCount() == barsBefore,
         "Re-processing the same bar (a duplicate tick) does not duplicate state");

   SSetupCandidate again;
   engine.Evaluate(close[1], time[1], again);
   Check(again.entryPrice == candidate.entryPrice &&
         again.stopPrice == candidate.stopPrice &&
         again.targetPrice == candidate.targetPrice &&
         again.qualityScore == candidate.qualityScore &&
         again.status == candidate.status &&
         again.type == candidate.type,
         "A duplicate tick does not change the decision");

   //--- history reload: a second engine built from scratch and fed
   //    the same bars must produce the same decision, because nothing
   //    in the pipeline may depend on hidden or run-order state
   CPabEngine *reloaded = new CPabEngine();
   Check(reloaded.Init(cfg, "EURUSD", PERIOD_H1),
         "A second engine inits identically");
   for(int i = n - 1; i >= 1; i--)
      reloaded.ProcessBar(i, time, open, high, low, close, n);

   SSetupCandidate reloadedCandidate;
   Check(reloaded.Evaluate(close[1], time[1], reloadedCandidate),
         "The reloaded engine evaluates the same bars");
   Check(reloadedCandidate.entryPrice == candidate.entryPrice &&
         reloadedCandidate.stopPrice == candidate.stopPrice &&
         reloadedCandidate.targetPrice == candidate.targetPrice &&
         reloadedCandidate.qualityScore == candidate.qualityScore &&
         reloadedCandidate.status == candidate.status &&
         reloadedCandidate.type == candidate.type &&
         reloadedCandidate.direction == candidate.direction,
         "A history reload reproduces the same decision from the same bars");

   delete reloaded;
   delete engine;
  }

//+------------------------------------------------------------------+
//| PHASE 21. The renderer is the only module allowed to touch chart |
//| objects, so its lifecycle contract is testable on its own: an    |
//| object is created under a stable key, redrawn by MOVING that     |
//| key (never by creating a second object), removed when it goes    |
//| inactive, and ClearAll removes everything on shutdown. The       |
//| Strategy Tester creates and counts chart objects exactly like a  |
//| live chart does, which makes this testable headlessly.           |
//+------------------------------------------------------------------+
void TestRendererLifecycle()
  {
   Print("--- TestRendererLifecycle ---");

   CChartRenderer *renderer = new CChartRenderer(0, "PABTEST");
   int baseline = ObjectsTotal(0, 0, -1);

   SBarInfo bar;
   bar.Clear();
   bar.time = D'2026.01.01 05:00';
   bar.open = 1.1000;
   bar.high = 1.1010;
   bar.low = 1.0990;
   bar.close = 1.1005;
   bar.range = 0.0020;
   bar.bodyRatio = 0.25;
   bar.clv = 0.75;
   bar.isBullish = true;
   bar.barType = BAR_BULL_TREND;
   bar.strength = STRENGTH_STRONG;
   bar.pullbackType = PB_H2;
   bar.signalQuality = QUALITY_STRONG;
   bar.isBreakoutBar = true;
   bar.isClimax = true;

   //--- with every visibility flag off, drawing must leave no trace
   renderer.SetVisibility(false, false, false, false, false, false, false);
   renderer.DrawBarLabel(bar, 1);
   renderer.DrawBreakoutMarker(bar);
   renderer.DrawClimaxMarker(bar);
   Check(ObjectsTotal(0, 0, -1) == baseline,
         "Drawing with all visibility off creates no objects");
   Check(ObjectFind(0, "PABTEST_LBL_" + (string)bar.time) < 0,
         "A hidden pullback label is not created");
   Check(ObjectFind(0, "PABTEST_BRK_" + (string)bar.time) < 0,
         "A hidden breakout marker is not created");

   //--- turning visibility back on creates the objects under stable keys
   renderer.SetVisibility(true, true, true, true, true, true, true);
   renderer.DrawBarLabel(bar, 1);
   renderer.DrawBreakoutMarker(bar);
   renderer.DrawClimaxMarker(bar);
   Check(ObjectsTotal(0, 0, -1) > baseline,
         "Visible drawing creates chart objects");
   Check(ObjectFind(0, "PABTEST_LBL_" + (string)bar.time) >= 0,
         "A visible pullback label is created under its stable key");
   Check(ObjectFind(0, "PABTEST_BRK_" + (string)bar.time) >= 0,
         "A visible breakout marker is created under its stable key");
   Check(ObjectFind(0, "PABTEST_CLX_" + (string)bar.time) >= 0,
         "A visible climax marker is created under its stable key");

   //--- drawing the same bar again must MOVE the existing objects,
   //    not add a second copy of them
   renderer.DrawBarLabel(bar, 1);
   renderer.DrawBreakoutMarker(bar);
   renderer.DrawClimaxMarker(bar);
   Check(ObjectsTotal(0, 0, -1) - baseline == 3,
         "Redrawing the same bar reuses its objects instead of duplicating them");

   //--- a NO TRADE decision still draws its marker, but must not leak
   //    entry, stop, or target lines that do not exist
   SSetupCandidate candidate;
   ZeroMemory(candidate);
   candidate.barTime = bar.time;
   candidate.direction = SETUP_NONE;
   candidate.status = STATUS_NO_TRADE;
   renderer.DrawSetup(candidate, true, true, false);
   Check(ObjectFind(0, "PABTEST_SETUP_marker") >= 0,
         "A NO TRADE decision still draws its marker");
   Check(ObjectFind(0, "PABTEST_SETUP_entry") < 0 &&
         ObjectFind(0, "PABTEST_SETUP_stop") < 0 &&
         ObjectFind(0, "PABTEST_SETUP_target") < 0,
         "A NO TRADE decision draws no entry, stop, or target lines");

   //--- ClearAll removes every object this renderer created
   renderer.ClearAll();
   Check(ObjectsTotal(0, 0, -1) == baseline,
         "ClearAll removes every object the renderer created");

   delete renderer;
  }

//+------------------------------------------------------------------+
//| Runs every group. Entry points call this and then report the    |
//| counters; they must not run the groups individually, or a new    |
//| group added here would silently never execute.                   |
//+------------------------------------------------------------------+
void RunAllPabTests()
  {
   g_pass = 0;
   g_fail = 0;
   ResetFailureLog();

   TestBarClassification();
   TestPullbackSequence();
   TestSwingDetection();
   TestTradingRangeDetection();
   TestPatternDetection();
   TestNormalizedPatternSlopes();
   TestBreakoutAndClimax();
   TestAlwaysIn();
   TestMeasuredMove();
   TestIdempotentUpdates();
   TestRangeTransitionClearsRange();
   TestContextAndDecision();
   TestTargetAndNoTradeContract();
   TestFailedBreakoutRequiresAnActualBreakout();
   TestTradingCost();
   TestEnginePipeline();
   TestRendererLifecycle();
  }


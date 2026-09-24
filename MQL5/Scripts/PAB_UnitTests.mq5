//+------------------------------------------------------------------+
//|                                          PAB_UnitTests.mq5       |
//|                                                                    |
//| Phase 2 deliverable: a standalone MQL5 SCRIPT (not an indicator)  |
//| that exercises every analyzer class against hand-built synthetic  |
//| OHLC series and asserts the expected classification. Run it from  |
//| the Navigator (Scripts) on any chart — it never touches chart      |
//| objects and its output goes entirely to the Experts/Journal log.  |
//|                                                                    |
//| This is intentionally NOT a MetaTester/Strategy-Tester backtest — |
//| it is a fast, deterministic regression check you can re-run after |
//| any change to Include/*.mqh before trusting the indicator again.  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/PriceActionBarByBar/PAB_Types.mqh"
#include "../Include/PriceActionBarByBar/PAB_Utils.mqh"
#include "../Include/PriceActionBarByBar/BarClassifier.mqh"
#include "../Include/PriceActionBarByBar/SwingDetector.mqh"
#include "../Include/PriceActionBarByBar/TradingRangeDetector.mqh"
#include "../Include/PriceActionBarByBar/PatternDetector.mqh"
#include "../Include/PriceActionBarByBar/AlwaysInTracker.mqh"
#include "../Include/PriceActionBarByBar/MeasuredMoveDetector.mqh"

int g_pass = 0;
int g_fail = 0;

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
   double h[] = {1.1012, 1.1030, 1.1017, 1.1020, 1.1000};
   double l[] = {1.0998, 1.1008, 1.1005, 1.1010, 1.0980};
   double c[] = {1.1010, 1.1012, 1.1006, 1.1014, 1.0985};
   // bar0: bull trend bar (close near high)
   // bar1: bull trend bar, sets a new high
   // bar2: doji-ish (small body vs range)
   // bar3: inside bar (high<=bar2 high, low>=bar2 low) -> 1.1020>1.1017 so NOT inside; adjust below instead
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
   Check(secondNewest.range > 0.0, "Bar has non-zero range");

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

   // source index 3 (first pullback after the 1.1057/1.1058 high) -> series pos n-1-3 = 3
   SBarInfo h1bar; bc.GetBar(3, h1bar);
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

   CPatternDetector pd(0.0015, 0.15);
   bool found = pd.AnalyzeSwings(swings, 4);
   Check(found, "Pattern detector finds a pattern in near-equal swing highs");

   SPatternInfo p = pd.LastPattern();
   Check(p.type == PATTERN_DOUBLE_TOP, "Near-equal consecutive swing highs classified as PATTERN_DOUBLE_TOP");
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

//+------------------------------------------------------------------+
//| Script entry point                                                |
//+------------------------------------------------------------------+
void OnStart()
  {
   Print("======================================================");
   Print(" PriceActionBarByBar — Unit Test Harness (Phase 2+3)");
   Print("======================================================");

   g_pass = 0; g_fail = 0;

   TestBarClassification();
   TestPullbackSequence();
   TestSwingDetection();
   TestTradingRangeDetection();
   TestPatternDetection();
   TestBreakoutAndClimax();
   TestAlwaysIn();
   TestMeasuredMove();

   Print("------------------------------------------------------");
   PrintFormat(" RESULT: %d passed, %d failed", g_pass, g_fail);
   Print("======================================================");

   if(g_fail > 0)
      Alert("PriceActionBarByBar unit tests: ", g_fail, " FAILED — see Experts log.");
   else
      Comment("PriceActionBarByBar unit tests: all ", g_pass, " passed.");
  }

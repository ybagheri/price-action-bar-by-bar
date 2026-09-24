//+------------------------------------------------------------------+
//|                                        PriceActionBarByBar.mq5   |
//|                        Price Action Bar-by-Bar Analyzer          |
//|          OOP MQL5 indicator inspired by Al Brooks'                |
//|          "Reading Price Charts Bar by Bar"                       |
//|                                                                    |
//| ARCHITECTURE (see README.md for the full class diagram):          |
//|                                                                    |
//|   OnCalculate() ──▶ COrchestrator.Run()                           |
//|                        │                                          |
//|                        ├─▶ CBarClassifier   (bar type + pullbacks +|
//|                        │                     breakout/climax)     |
//|                        ├─▶ CSwingDetector    (swing highs/lows)   |
//|                        ├─▶ CTradingRangeDetector (regime state)   |
//|                        ├─▶ CPatternDetector  (swing-based patterns)|
//|                        ├─▶ CAlwaysInTracker  (sticky bull/bear)   |
//|                        ├─▶ CMeasuredMoveDetector (swing-based MM) |
//|                        └─▶ CChartRenderer    (all drawing)        |
//|                                                                    |
//| Each analyzer is independent and swappable (implements IAnalyzer  |
//| where its update model is bar-driven). The orchestrator is the    |
//| only place that knows the pipeline order.                        |
//+------------------------------------------------------------------+
#property copyright "ybagheri"
#property link      "https://github.com/ybagheri/price-action-bar-by-bar"
#property version   "1.20"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

#include "../Include/PriceActionBarByBar/PAB_Types.mqh"
#include "../Include/PriceActionBarByBar/PAB_Utils.mqh"
#include "../Include/PriceActionBarByBar/BarClassifier.mqh"
#include "../Include/PriceActionBarByBar/SwingDetector.mqh"
#include "../Include/PriceActionBarByBar/TradingRangeDetector.mqh"
#include "../Include/PriceActionBarByBar/PatternDetector.mqh"
#include "../Include/PriceActionBarByBar/AlwaysInTracker.mqh"
#include "../Include/PriceActionBarByBar/MeasuredMoveDetector.mqh"
#include "../Include/PriceActionBarByBar/ChartRenderer.mqh"

//====================================================================
// INPUTS
//====================================================================
input group "=== Bar Classification ==="
input double InpDojiBodyRatio      = 0.30;   // Body/Range ratio below which a bar is a Doji
input double InpClvFavorableMin    = 0.15;   // Min |Close Location Value| for a pullback bar to score a quality point
input int    InpFeatureLookback    = 20;
input double InpLargeRangeMult     = 1.50;
input double InpSmallRangeMult     = 0.70;
input double InpStrongBodyRatio    = 0.60;

input group "=== Swing Detection ==="
input int    InpFractalLegs        = 2;      // Bars required on each side of a swing (2 = 5-bar fractal)

input group "=== Trading Range / Trend State ==="
input int    InpRegimeLookback     = 20;     // Bars used to score trend vs range
input double InpOverlapThreshold   = 0.55;   // Avg overlap ratio above which market = ranging
input double InpDisplaceThreshold  = 3.0;    // Net move / avg range above which market = trending
input bool   InpUseRealATR         = true;   // Normalize displacement using MT5's real ATR instead of a simple average
input int    InpATRPeriod          = 14;     // ATR period (only used when InpUseRealATR = true)

input group "=== Pattern Detection ==="
input double InpSwingSimilarityPct = 0.15;   // % tolerance for "equal" swing highs/lows (double top/bottom)
input double InpConvergenceMin     = 0.15;   // Minimum slope convergence to flag triangle/wedge

input group "=== Breakout / Climax (Phase 3) ==="
input int    InpBreakoutLookback   = 10;     // Bars to check for a fresh extreme to qualify as a breakout bar
input double InpBreakoutClvMin     = 0.50;   // Min |CLV| for a breakout bar's close
input int    InpClimaxLookback     = 20;     // Bars used for the climax average-range baseline
input double InpClimaxRangeMult    = 2.0;    // Range must be >= this x the average range to flag a climax bar
input double InpClimaxBodyRatioMax = 0.35;   // Body/range must be <= this (weak close) to flag a climax bar

input group "=== Display ==="
input bool   InpShowPullbackLabels = true;   // Show H1/H2/H3+/L1/L2/L3+ labels
input bool   InpShowSwings         = true;   // Show swing-high/low arrows
input bool   InpShowRange          = true;   // Show trading-range rectangle
input bool   InpShowPatterns       = true;   // Show detected pattern annotations
input bool   InpShowBreakouts      = true;   // Show breakout-bar markers
input bool   InpShowClimax         = true;   // Show climax/exhaustion-bar markers
input bool   InpShowMeasuredMove   = true;   // Show the measured-move target line
input bool   InpShowStatePanel     = true;   // Show top-left market-state panel
input color  InpColorBull          = clrDodgerBlue;
input color  InpColorBear          = clrCrimson;
input color  InpColorDoji          = clrSilver;
input color  InpColorSwingHigh     = clrOrange;
input color  InpColorSwingLow      = clrLime;
input color  InpColorRange         = clrKhaki;
input color  InpColorPattern       = clrMagenta;
input color  InpColorBreakout      = clrYellow;
input color  InpColorClimax        = clrRed;
input color  InpColorMeasuredMove  = clrAqua;

//====================================================================
// GLOBAL STATE (single instance of each analyzer — orchestrator role)
//====================================================================
double              g_dummyBuffer[];   // required by indicator_buffers, unused for drawing

CBarClassifier      *g_classifier   = NULL;
CSwingDetector      *g_swings       = NULL;
CTradingRangeDetector *g_range      = NULL;
CPatternDetector    *g_patterns     = NULL;
CAlwaysInTracker    *g_alwaysIn     = NULL;
CMeasuredMoveDetector *g_measuredMove = NULL;
CChartRenderer      *g_renderer     = NULL;
string              g_objectPrefix = "";

int                 g_atrHandle     = INVALID_HANDLE;   // Phase 2: real ATR, owned by the orchestrator
double              g_atrBuf[];                          // scratch buffer, refilled every OnCalculate call

bool ValidateInputs()
  {
   if(      InpDojiBodyRatio <= 0.0 || InpDojiBodyRatio > 1.0 ||
      InpClvFavorableMin < 0.0 || InpClvFavorableMin > 1.0 ||
      InpFeatureLookback < 2 || InpFeatureLookback > 500 ||
      InpLargeRangeMult <= 0.0 || InpLargeRangeMult < InpSmallRangeMult ||
      InpSmallRangeMult <= 0.0 || InpSmallRangeMult > 1.0 ||
      InpStrongBodyRatio <= 0.0 || InpStrongBodyRatio > 1.0 ||
      InpFractalLegs < 1 || InpFractalLegs > 50 ||
      InpRegimeLookback < 5 || InpRegimeLookback > 500 ||
      InpOverlapThreshold < 0.0 || InpOverlapThreshold > 1.0 ||
      InpDisplaceThreshold <= 0.0 ||
      InpATRPeriod < 1 || InpATRPeriod > 1000 ||
      InpSwingSimilarityPct < 0.0 || InpSwingSimilarityPct > 100.0 ||
      InpConvergenceMin <= 0.0 ||
      InpBreakoutLookback < 1 || InpBreakoutLookback > 500 ||
      InpBreakoutClvMin < 0.0 || InpBreakoutClvMin > 1.0 ||
      InpClimaxLookback < 2 || InpClimaxLookback > 500 ||
      InpClimaxRangeMult <= 0.0 ||
      InpClimaxBodyRatioMax < 0.0 || InpClimaxBodyRatioMax > 1.0)
     {
      Print("PriceActionBarByBar: invalid input parameters");
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Custom indicator initialization function                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);

   g_objectPrefix = StringFormat("PAB_%I64d", (long)GetMicrosecondCount());

   SetIndexBuffer(0, g_dummyBuffer, INDICATOR_DATA);
   ArraySetAsSeries(g_dummyBuffer, true);
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);

   g_classifier = new CBarClassifier(InpDojiBodyRatio, 2000, InpClvFavorableMin,
                                       InpBreakoutLookback, InpBreakoutClvMin,
                                       InpClimaxLookback, InpClimaxRangeMult, InpClimaxBodyRatioMax,
                                       InpFeatureLookback, InpLargeRangeMult, InpSmallRangeMult, InpStrongBodyRatio);
   g_swings     = new CSwingDetector(InpFractalLegs);
   g_range      = new CTradingRangeDetector(InpRegimeLookback, InpOverlapThreshold, InpDisplaceThreshold);
   g_patterns   = new CPatternDetector(InpSwingSimilarityPct / 100.0, InpConvergenceMin);
   g_alwaysIn   = new CAlwaysInTracker();
   g_measuredMove = new CMeasuredMoveDetector();
   g_renderer   = new CChartRenderer(ChartID(), g_objectPrefix);

   if(g_classifier == NULL || g_swings == NULL || g_range == NULL || g_patterns == NULL ||
      g_alwaysIn == NULL || g_measuredMove == NULL || g_renderer == NULL)
     {
      Print("PriceActionBarByBar: analyzer allocation failed");
      return(INIT_FAILED);
     }

   if(InpUseRealATR)
     {
      g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
      if(g_atrHandle == INVALID_HANDLE)
         Print("PriceActionBarByBar: iATR() failed, falling back to the internal simple average — error ", GetLastError());
     }

   g_renderer.SetColors(InpColorBull, InpColorBear, InpColorDoji,
                         InpColorSwingHigh, InpColorSwingLow,
                         InpColorRange, InpColorPattern,
                         InpColorBreakout, InpColorClimax, InpColorMeasuredMove);
   g_renderer.SetVisibility(InpShowPullbackLabels, InpShowSwings, InpShowRange, InpShowPatterns,
                             InpShowBreakouts, InpShowClimax, InpShowMeasuredMove);

   IndicatorSetString(INDICATOR_SHORTNAME, "PriceActionBarByBar");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_renderer != NULL)
      g_renderer.ClearAll();

   if(g_atrHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
     }

   if(g_classifier != NULL) { delete g_classifier; g_classifier = NULL; }
   if(g_swings     != NULL) { delete g_swings;     g_swings     = NULL; }
   if(g_range      != NULL) { delete g_range;      g_range      = NULL; }
   if(g_patterns   != NULL) { delete g_patterns;   g_patterns   = NULL; }
   if(g_alwaysIn   != NULL) { delete g_alwaysIn;   g_alwaysIn   = NULL; }
   if(g_measuredMove != NULL) { delete g_measuredMove; g_measuredMove = NULL; }
   if(g_renderer   != NULL) { delete g_renderer;   g_renderer   = NULL; }
  }

//+------------------------------------------------------------------+
//| Human-readable label for the market-state panel                 |
//+------------------------------------------------------------------+
string StateLabel(const ENUM_MARKET_STATE s)
  {
   switch(s)
     {
      case STATE_BULL_TREND:    return("Bull Trend");
      case STATE_BEAR_TREND:    return("Bear Trend");
      case STATE_TRADING_RANGE: return("Trading Range");
      case STATE_TRANSITION:    return("Transition");
     }
   return("Unknown");
  }

string AlwaysInLabel(const ENUM_ALWAYS_IN_STATE s)
  {
   switch(s)
     {
      case ALWAYS_IN_LONG:  return("Long");
      case ALWAYS_IN_SHORT: return("Short");
     }
   return("None");
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                             |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                 const int prev_calculated,
                 const datetime &time[],
                 const double &open[],
                 const double &high[],
                 const double &low[],
                 const double &close[],
                 const long &tick_volume[],
                 const long &volume[],
                 const int &spread[])
  {
   if(rates_total < 10)
      return(0);

   // Work with series-style indexing (0 = current bar) to match the
   // analyzer classes' expectations.
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int start;
   if(prev_calculated <= 0)
     {
      g_classifier.Reset();
      g_swings.Reset();
      g_range.Reset();
      g_patterns.Reset();
      g_alwaysIn.Reset();
      g_measuredMove.Reset();
      g_renderer.ClearAll();
      start = rates_total - 1;
     }
   else
     {
      int newBars = MathMax(0, rates_total - prev_calculated);
      start = MathMin(rates_total - 1, newBars);
     }

   bool processedClosedBar = (start >= 1);
   bool haveFreshAtr = false;
   if(processedClosedBar && g_atrHandle != INVALID_HANDLE)
     {
      ArraySetAsSeries(g_atrBuf, true);
      int copied = CopyBuffer(g_atrHandle, 0, 0, rates_total, g_atrBuf);
      haveFreshAtr = (copied == rates_total);
      if(!haveFreshAtr)
         PrintFormat("PriceActionBarByBar: CopyBuffer copied %d of %d ATR values, error %d",
                     copied, rates_total, GetLastError());
     }

   if(haveFreshAtr)
      g_range.SetATRSeries(g_atrBuf);

   for(int i = start; i >= 1; i--)
     {
      g_classifier.Update(i, time, open, high, low, close, rates_total);
      g_swings.Update(i, time, open, high, low, close, rates_total);
      g_range.Update(i, time, open, high, low, close, rates_total);
     }

   int swingCount = g_swings.Count();
   SSwingPoint swingArr[];
   if(processedClosedBar && swingCount > 0)
     {
      ArrayResize(swingArr, swingCount);
      for(int i = 0; i < swingCount; i++)
         g_swings.GetSwing(i, swingArr[i]);
      g_patterns.AnalyzeSwings(swingArr, swingCount);
      g_measuredMove.AnalyzeSwings(swingArr, swingCount);
     }

   if(processedClosedBar)
     {
      SSwingPoint latestHigh, latestLow;
      bool haveHigh = g_swings.LatestOfType(SWING_HIGH, latestHigh);
      bool haveLow  = g_swings.LatestOfType(SWING_LOW, latestLow);
      g_alwaysIn.Evaluate(close[1], haveHigh, haveHigh ? latestHigh.price : 0.0,
                           haveLow, haveLow ? latestLow.price : 0.0, time[1]);
     }

   int renderCount = MathMin(g_classifier.Count(), start + 1);
   for(int i = 0; i < renderCount; i++)
     {
      SBarInfo bar;
      if(g_classifier.GetBar(i, bar))
        {
         g_renderer.DrawBarLabel(bar, i);
         g_renderer.DrawBreakoutMarker(bar);
         g_renderer.DrawClimaxMarker(bar);
        }
     }

   for(int i = 0; i < swingCount; i++)
     {
      SSwingPoint sp;
      g_swings.GetSwing(i, sp);
      g_renderer.DrawSwing(sp);
     }

   STradingRangeInfo ri;
   if(g_range.GetRange(ri))
      g_renderer.DrawTradingRange(ri, time);
   else
      g_renderer.HideTradingRange();

   SPatternInfo pi = g_patterns.LastPattern();
   if(pi.type != PATTERN_NONE)
      g_renderer.DrawPattern(pi, high[1]);
   else
      g_renderer.HidePattern();

   SMeasuredMoveInfo mm = g_measuredMove.Current();
   if(mm.active)
      g_renderer.DrawMeasuredMove(mm, time[1]);
   else
      g_renderer.HideMeasuredMove();

   if(InpShowStatePanel)
     {
      string panel = StringFormat("PriceActionBarByBar\nState: %s | Always-In: %s\nSwings: %d",
                                   StateLabel(g_range.State()), AlwaysInLabel(g_alwaysIn.State()), swingCount);
      g_renderer.DrawStatePanel(panel);
     }
   else
      g_renderer.HideStatePanel();

   return(rates_total);
  }
//+------------------------------------------------------------------+

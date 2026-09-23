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
//|                        ├─▶ CBarClassifier   (bar type + pullbacks)|
//|                        ├─▶ CSwingDetector    (swing highs/lows)   |
//|                        ├─▶ CTradingRangeDetector (regime state)   |
//|                        ├─▶ CPatternDetector  (swing-based patterns)|
//|                        └─▶ CChartRenderer    (all drawing)        |
//|                                                                    |
//| Each analyzer is independent and swappable (implements IAnalyzer  |
//| where its update model is bar-driven). The orchestrator is the    |
//| only place that knows the pipeline order.                        |
//+------------------------------------------------------------------+
#property copyright "ybagheri"
#property link      "https://github.com/ybagheri/price-action-bar-by-bar"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

#include "Include/PAB_Types.mqh"
#include "Include/PAB_IAnalyzer.mqh"
#include "Include/PAB_Utils.mqh"
#include "Include/BarClassifier.mqh"
#include "Include/SwingDetector.mqh"
#include "Include/TradingRangeDetector.mqh"
#include "Include/PatternDetector.mqh"
#include "Include/ChartRenderer.mqh"

//====================================================================
// INPUTS
//====================================================================
input group "=== Bar Classification ==="
input double InpDojiBodyRatio      = 0.30;   // Body/Range ratio below which a bar is a Doji

input group "=== Swing Detection ==="
input int    InpFractalLegs        = 2;      // Bars required on each side of a swing (2 = 5-bar fractal)

input group "=== Trading Range / Trend State ==="
input int    InpRegimeLookback     = 20;     // Bars used to score trend vs range
input double InpOverlapThreshold   = 0.55;   // Avg overlap ratio above which market = ranging
input double InpDisplaceThreshold  = 3.0;    // Net move / avg range above which market = trending

input group "=== Pattern Detection ==="
input double InpSwingSimilarityPct = 0.15;   // % tolerance for "equal" swing highs/lows (double top/bottom)
input double InpConvergenceMin     = 0.15;   // Minimum slope convergence to flag triangle/wedge

input group "=== Display ==="
input bool   InpShowPullbackLabels = true;   // Show H1/H2/H3+/L1/L2/L3+ labels
input bool   InpShowSwings         = true;   // Show swing-high/low arrows
input bool   InpShowRange          = true;   // Show trading-range rectangle
input bool   InpShowPatterns       = true;   // Show detected pattern annotations
input bool   InpShowStatePanel     = true;   // Show top-left market-state panel
input color  InpColorBull          = clrDodgerBlue;
input color  InpColorBear          = clrCrimson;
input color  InpColorDoji          = clrSilver;
input color  InpColorSwingHigh     = clrOrange;
input color  InpColorSwingLow      = clrLime;
input color  InpColorRange         = clrKhaki;
input color  InpColorPattern       = clrMagenta;

//====================================================================
// GLOBAL STATE (single instance of each analyzer — orchestrator role)
//====================================================================
double              g_dummyBuffer[];   // required by indicator_buffers, unused for drawing

CBarClassifier      *g_classifier   = NULL;
CSwingDetector      *g_swings       = NULL;
CTradingRangeDetector *g_range      = NULL;
CPatternDetector    *g_patterns     = NULL;
CChartRenderer      *g_renderer     = NULL;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, g_dummyBuffer, INDICATOR_DATA);
   ArraySetAsSeries(g_dummyBuffer, true);
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);

   g_classifier = new CBarClassifier(InpDojiBodyRatio);
   g_swings     = new CSwingDetector(InpFractalLegs);
   g_range      = new CTradingRangeDetector(InpRegimeLookback, InpOverlapThreshold, InpDisplaceThreshold);
   g_patterns   = new CPatternDetector(InpSwingSimilarityPct / 100.0, InpConvergenceMin);
   g_renderer   = new CChartRenderer(0, "PAB");

   g_renderer.SetColors(InpColorBull, InpColorBear, InpColorDoji,
                         InpColorSwingHigh, InpColorSwingLow,
                         InpColorRange, InpColorPattern);
   g_renderer.SetVisibility(InpShowPullbackLabels, InpShowSwings, InpShowRange, InpShowPatterns);

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

   if(g_classifier != NULL) { delete g_classifier; g_classifier = NULL; }
   if(g_swings     != NULL) { delete g_swings;     g_swings     = NULL; }
   if(g_range      != NULL) { delete g_range;      g_range      = NULL; }
   if(g_patterns   != NULL) { delete g_patterns;   g_patterns   = NULL; }
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

   // On the very first run (or after a history reload) re-process
   // everything; otherwise only process bars that are new since the
   // last call. We always reprocess the still-forming bar (index 0)
   // plus one bar of safety margin because it can repaint until close.
   int start;
   if(prev_calculated <= 0)
     {
      g_classifier.Reset();
      g_swings.Reset();
      g_range.Reset();
      g_patterns.Reset();
      g_renderer.ClearAll();
      start = rates_total - 1;   // oldest bar first
     }
   else
     {
      int newBars = rates_total - prev_calculated;
      start = MathMin(rates_total - 1, newBars + 1); // +1 safety margin for the reforming bar
     }

   // ----- oldest-to-newest pipeline pass ---------------------------------
   for(int i = start; i >= 0; i--)
     {
      g_classifier.Update(i, time, open, high, low, close, rates_total);
      g_swings.Update(i, time, open, high, low, close, rates_total);
      g_range.Update(i, time, open, high, low, close, rates_total);
     }

   // ----- pattern detection runs off the swing list, once per call ------
   int swingCount = g_swings.Count();
   if(swingCount > 0)
     {
      SSwingPoint swingArr[];
      ArrayResize(swingArr, swingCount);
      for(int i = 0; i < swingCount; i++)
         g_swings.GetSwing(i, swingArr[i]);
      g_patterns.AnalyzeSwings(swingArr, swingCount);
     }

   // ----- rendering: draw the freshly (re)processed bars -----------------
   // CBarClassifier's ring buffer is aligned 1:1 with series index i for
   // every bar that has been through Update() at least once, so i doubles
   // as both the series index and the classifier buffer index here.
   for(int i = 0; i <= start; i++)
     {
      SBarInfo bar;
      if(g_classifier.GetBar(i, bar))
         g_renderer.DrawBarLabel(bar, i);
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

   SPatternInfo pi = g_patterns.LastPattern();
   if(pi.type != PATTERN_NONE)
      g_renderer.DrawPattern(pi, time, high[0]);

   if(InpShowStatePanel)
     {
      string panel = StringFormat("PriceActionBarByBar\nState: %s\nSwings: %d",
                                   StateLabel(g_range.State()), swingCount);
      g_renderer.DrawStatePanel(panel);
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                        PriceActionBarByBar.mq5   |
//|                        Price Action Bar-by-Bar Analyzer          |
//|          OOP MQL5 indicator inspired by Al Brooks'                |
//|          "Reading Price Charts Bar by Bar"                       |
//|                                                                    |
//| ARCHITECTURE (see ARCHITECTURE.md for the full description):      |
//|                                                                    |
//|   OnCalculate() ──▶ CPabEngine                                   |
//|                        │                                          |
//|                        ├─▶ CBarClassifier   (bar type, pullbacks, |
//|                        │                     breakout, climax)    |
//|                        ├─▶ CSwingDetector    (swing highs/lows)   |
//|                        ├─▶ CTradingRangeDetector (regime state)   |
//|                        ├─▶ CPatternDetector  (swing patterns)     |
//|                        ├─▶ CAlwaysInTracker  (sticky bull/bear)   |
//|                        ├─▶ CMeasuredMoveDetector (swing MM)      |
//|                        ├─▶ CContextAnalyzer  (micro/medium)       |
//|                        └─▶ CDecisionEngine   (setup, risk, why)  |
//|                                                                    |
//                        CChartRenderer  (all drawing, this file)    |
//|                                                                    |
//| The engine is shared verbatim with the historical replay in        |
//| MQL5/Experts/PabEventExport.mq5, so an exported event and a chart  |
//| setup are the same computation rather than two implementations    |
//| that agree until one of them is edited.                           |
//+------------------------------------------------------------------+
#property copyright "ybagheri"
#property link      "https://github.com/ybagheri/price-action-bar-by-bar"
#property version   "1.50"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

#include "../Include/PriceActionBarByBar/PAB_Types.mqh"
#include "../Include/PriceActionBarByBar/PAB_Utils.mqh"
#include "../Include/PriceActionBarByBar/TradingCost.mqh"
#include "../Include/PriceActionBarByBar/PabEngine.mqh"
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
input double InpConvergenceMin     = 0.00020; // Min convergence, as a FRACTION OF PRICE PER BAR (0.00020 = 0.020%/bar)

input group "=== Decision Support ==="
input int    InpMinimumQuality     = 55;
input double InpMinimumRiskReward  = 1.50;
input bool   InpExportEvents       = false;
input string InpEventFile          = "pab_events.csv";

input group "=== Execution Costs (Phase 19) ==="
// Spread is MEASURED from the per-bar spread array MT5 hands OnCalculate.
// These two are ASSUMED: neither is observable from a bar series, so they
// are inputs, and every exported row labels them "assumed".
input double InpSlippagePoints     = 0.0;   // Assumed, per side. 0 = none.
input double InpCommissionPerLot   = 0.0;   // Assumed, account currency, round trip, per lot
input double InpLotSize            = 1.0;   // Lot size the commission is quoted for

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
input bool   InpShowSetups          = true;
input bool   InpShowExplanations    = true;
input bool   InpShowDebug           = false;
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
// GLOBAL STATE
//====================================================================
// Phase 16: the analyzers now live inside CPabEngine, which owns the
// pipeline. The orchestrator below is only the MT5 lifecycle: closed-bar
// gate, ATR injection, and drawing. The historical replay in
// MQL5/Experts/PabEventExport.mq5 drives the same engine, so a setup on
// a chart and a setup in an exported event are the same computation.
double              g_dummyBuffer[];   // required by indicator_buffers, unused for drawing

CPabEngine         *g_engine      = NULL;
CChartRenderer     *g_renderer    = NULL;
SContextInfo        g_contextInfo;
SSetupCandidate     g_candidate;
string              g_objectPrefix = "";

int                 g_eventFileHandle = INVALID_HANDLE;

// Broker facts for the cost model, read once in OnInit.
double              g_point      = 0.0;
double              g_tickValue  = 0.0;
double              g_tickSize   = 0.0;

bool BuildEngineConfig(SEngineConfig &cfg)
  {
   cfg.dojiBodyRatio      = InpDojiBodyRatio;
   cfg.clvFavorableMin    = InpClvFavorableMin;
   cfg.featureLookback    = InpFeatureLookback;
   cfg.largeRangeMult     = InpLargeRangeMult;
   cfg.smallRangeMult     = InpSmallRangeMult;
   cfg.strongBodyRatio    = InpStrongBodyRatio;
   cfg.historyCapacity    = 2000;
   cfg.breakoutLookback   = InpBreakoutLookback;
   cfg.breakoutClvMin     = InpBreakoutClvMin;
   cfg.climaxLookback     = InpClimaxLookback;
   cfg.climaxRangeMult    = InpClimaxRangeMult;
   cfg.climaxBodyRatioMax = InpClimaxBodyRatioMax;
   cfg.fractalLegs        = InpFractalLegs;
   cfg.swingCapacity      = 500;
   cfg.regimeLookback     = InpRegimeLookback;
   cfg.overlapThreshold   = InpOverlapThreshold;
   cfg.displaceThreshold  = InpDisplaceThreshold;
   cfg.useRealAtr         = InpUseRealATR;
   cfg.atrPeriod          = InpATRPeriod;
   cfg.swingSimilarityPct = InpSwingSimilarityPct / 100.0;
   cfg.convergenceMin     = InpConvergenceMin;
   cfg.secondsPerBar      = (int)PeriodSeconds(_Period);
   cfg.minimumQuality     = InpMinimumQuality;
   cfg.minimumRiskReward  = InpMinimumRiskReward;
   cfg.contextBars        = 10;
   return(true);
  }

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
      InpMinimumQuality < 0 || InpMinimumQuality > 100 ||
      InpMinimumRiskReward < 0.1 ||
      InpBreakoutLookback < 1 || InpBreakoutLookback > 500 ||
      InpBreakoutClvMin < 0.0 || InpBreakoutClvMin > 1.0 ||
      InpClimaxLookback < 2 || InpClimaxLookback > 500 ||
      InpClimaxRangeMult <= 0.0 ||
       InpClimaxBodyRatioMax < 0.0 || InpClimaxBodyRatioMax > 1.0 ||
       InpSlippagePoints < 0.0 ||
       InpCommissionPerLot < 0.0 ||
       InpLotSize <= 0.0)
      {
      Print("PriceActionBarByBar: invalid input parameters");
      return(false);
      }

   // A currency commission is meaningless without the broker's tick value.
   // Failing here beats exporting cost_r = 0 and letting a reader assume
   // trading was free.
   string costReason = "";
   if(!ReadSymbolCostFacts(_Symbol, g_point, g_tickValue, g_tickSize, costReason))
      PrintFormat("PriceActionBarByBar: %s. Any commission will export as 0.0 and be "
                  "labelled, so a cost-free export cannot be mistaken for a free one.",
                  costReason);
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

   SEngineConfig cfg;
   BuildEngineConfig(cfg);

   g_engine   = new CPabEngine();
   g_renderer = new CChartRenderer(ChartID(), g_objectPrefix);

   if(g_engine == NULL || g_renderer == NULL ||
      !g_engine.Init(cfg, _Symbol, _Period))
     {
      Print("PriceActionBarByBar: engine allocation failed");
      return(INIT_FAILED);
     }

   if(InpExportEvents)
     {
      g_eventFileHandle = FileOpen(InpEventFile,
                                   FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ);
      if(g_eventFileHandle == INVALID_HANDLE)
        {
         PrintFormat("PriceActionBarByBar: event export open failed for %s, error %d",
                     InpEventFile, GetLastError());
         return(INIT_FAILED);
        }
       if(FileSize(g_eventFileHandle) == 0)
          FileWrite(g_eventFileHandle,
                    "event_id", "direction", "setup_type", "status",
                    "bar_open_time", "bar_close_time", "confirmed_at", "decision_time",
                    "entry", "invalidation", "target", "risk_reward", "quality",
                    "engine_version", "parameter_version",
                    "symbol", "period",
                    "spread_points", "cost_spread_price", "cost_slippage_price",
                    "cost_commission_price", "cost_r", "cost_model");
      else
         FileSeek(g_eventFileHandle, 0, SEEK_END);
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
   if(g_eventFileHandle != INVALID_HANDLE)
     {
      FileClose(g_eventFileHandle);
      g_eventFileHandle = INVALID_HANDLE;
     }

   if(g_renderer != NULL)
      g_renderer.ClearAll();

   if(g_engine != NULL) { g_engine.ReleaseAtr(); }
   if(g_engine   != NULL) { delete g_engine;   g_engine   = NULL; }
   if(g_renderer != NULL) { delete g_renderer; g_renderer = NULL; }
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

string SetupDirectionLabel(const ENUM_SETUP_DIRECTION direction)
  {
   if(direction == SETUP_LONG) return("long");
   if(direction == SETUP_SHORT) return("short");
   return("none");
  }

string SetupStatusLabel(const ENUM_SETUP_STATUS status)
  {
   if(status == STATUS_CONFIRMED) return("confirmed");
   if(status == STATUS_PROBABLE) return("probable");
   if(status == STATUS_POSSIBLE) return("possible");
   if(status == STATUS_WEAK) return("weak");
   return("no_trade");
  }

string SetupTypeLabel(const ENUM_SETUP_TYPE type)
  {
   if(type == SETUP_TREND_PULLBACK) return("trend_pullback");
   if(type == SETUP_SECOND_ENTRY) return("second_entry");
   if(type == SETUP_RANGE_REVERSAL) return("range_reversal");
   if(type == SETUP_FAILED_BREAKOUT) return("failed_breakout");
   if(type == SETUP_BREAKOUT_FOLLOW_THROUGH) return("breakout_follow_through");
   if(type == SETUP_WEDGE_REVERSAL) return("wedge_reversal");
   return("no_trade");
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
      g_engine.Reset();
      g_contextInfo.valid = false;
      g_renderer.ClearAll();
      start = rates_total - 1;
     }
   else
     {
      int newBars = MathMax(0, rates_total - prev_calculated);
      start = MathMin(rates_total - 1, newBars);
     }

   bool processedClosedBar = (start >= 1);
   if(processedClosedBar)
     {
      bool atrOk = false;
      g_engine.RefreshAtr(rates_total, atrOk);
     }

   for(int i = start; i >= 1; i--)
      g_engine.ProcessBar(i, time, open, high, low, close, rates_total);

   int swingCount = g_engine.SwingCount();
   SSwingPoint swingArr[];
   if(processedClosedBar && swingCount > 0)
     {
      ArrayResize(swingArr, swingCount);
      for(int i = 0; i < swingCount; i++)
         g_engine.GetSwing(i, swingArr[i]);
     }

   if(processedClosedBar)
     {
      if(g_engine.Evaluate(close[1], time[1], g_candidate))
        {
         g_contextInfo = g_engine.Context();
         if(g_eventFileHandle != INVALID_HANDLE && g_candidate.barTime > 0)
           {
            // The candidate's barTime is the classified bar's open time,
            // so the close time is exactly one period later. Exported
            // decision_time equals bar_close_time, which is the invariant
            // the research layer enforces.
            datetime closeTime = g_candidate.barTime + PeriodSeconds(_Period);
             string parameterVersion = StringFormat("q%d|rr%.2f|f%d|l%.2f|s%.2f|b%d|c%.2f",
                                                  InpMinimumQuality, InpMinimumRiskReward,
                                                  InpFractalLegs, InpLargeRangeMult, InpSmallRangeMult,
                                                  InpBreakoutLookback, InpClimaxRangeMult);

             // PHASE 19. The chart is handed the broker's own spread array,
             // one value per bar, so the spread charged here is the spread
             // that actually applied on the bar the decision was taken on
             // rather than a run-wide average or a typed-in guess.
             // Index 1 is the same bar the decision is made from, matching
             // the rest of this function.
             //
             // If that array is somehow absent the cost is UNKNOWN, not
             // free, and every cost field is written blank so the research
             // layer reports the file as gross. Writing 0.0 instead would
             // be a fabricated claim that trading this market costs
             // nothing.
             bool spreadKnown = (ArraySize(spread) > 1);
             SCostModel rowCost;
             rowCost.spreadPoints     = spreadKnown ? (double)spread[1] : 0.0;
             rowCost.spreadPrice      = rowCost.spreadPoints * _Point;
             rowCost.spreadMeasured   = spreadKnown;
             rowCost.slippagePrice    = InpSlippagePoints * _Point;
             rowCost.slippagePoints   = InpSlippagePoints;
             rowCost.commissionPrice  = CTradingCost::CommissionPriceFromPerLot(
                                          InpCommissionPerLot, InpLotSize, g_tickValue, g_tickSize);
             if(g_candidate.status == STATUS_NO_TRADE)
               {
                rowCost.spreadPrice    = 0.0;
                rowCost.spreadPoints   = 0.0;
                rowCost.spreadMeasured = false;
               }

             // A NO TRADE row carries a KNOWN zero, because it has no
             // levels and so no cost. Only an unmeasured spread is blank.
             bool rowKnown = spreadKnown || g_candidate.status == STATUS_NO_TRADE;

             FileWrite(g_eventFileHandle,
                       StringFormat("%I64d-%d", (long)g_candidate.barTime, g_candidate.qualityScore),
                       SetupDirectionLabel(g_candidate.direction), SetupTypeLabel(g_candidate.type),
                       SetupStatusLabel(g_candidate.status),
                       IsoTimestamp(g_candidate.barTime),
                       IsoTimestamp(closeTime),
                       IsoTimestamp(closeTime),
                       IsoTimestamp(closeTime),
                       DoubleToString(g_candidate.entryPrice, _Digits),
                       DoubleToString(g_candidate.stopPrice, _Digits),
                       DoubleToString(g_candidate.targetPrice, _Digits),
                       DoubleToString(g_candidate.riskReward, 4),
                       g_candidate.qualityScore,
                       PAB_ENGINE_VERSION, parameterVersion,
                       _Symbol, PeriodLabel(_Period),
                       (rowKnown ? DoubleToString(rowCost.spreadPoints, 1) : ""),
                       (rowKnown ? DoubleToString(rowCost.spreadPrice, _Digits) : ""),
                       (rowKnown ? DoubleToString(rowCost.slippagePrice, _Digits) : ""),
                       (rowKnown ? DoubleToString(rowCost.commissionPrice, _Digits) : ""),
                       (rowKnown ? DoubleToString(CTradingCost::CostInR(rowCost,
                                            g_candidate.entryPrice, g_candidate.stopPrice), 4) : ""),
                       (rowKnown ? rowCost.Model()
                                 : "unknown: no per-bar spread was supplied for this bar"));
           }
        }
     }

   int renderCount = MathMin(g_engine.BarCount(), start + 1);
   for(int i = 0; i < renderCount; i++)
     {
      SBarInfo bar;
      if(g_engine.GetBar(i, bar))
        {
         g_renderer.DrawBarLabel(bar, i);
         g_renderer.DrawBreakoutMarker(bar);
         g_renderer.DrawClimaxMarker(bar);
        }
     }

   for(int i = 0; i < swingCount; i++)
     {
      SSwingPoint sp;
      g_engine.GetSwing(i, sp);
      g_renderer.DrawSwing(sp);
     }

   STradingRangeInfo ri;
   if(g_engine.GetTradingRange(ri))
      g_renderer.DrawTradingRange(ri, time);
   else
      g_renderer.HideTradingRange();

   SPatternInfo pi = g_engine.Pattern();
   if(pi.type != PATTERN_NONE)
      g_renderer.DrawPattern(pi, high[1]);
   else
      g_renderer.HidePattern();

   SMeasuredMoveInfo mm = g_engine.MeasuredMove();
   if(mm.active)
      g_renderer.DrawMeasuredMove(mm, time[1]);
   else
      g_renderer.HideMeasuredMove();

   g_renderer.DrawSetup(g_candidate, InpShowSetups, InpShowExplanations, InpShowDebug);

   if(InpShowStatePanel)
     {
      string panel = StringFormat("PriceActionBarByBar\nMedium: %s | Micro: %s\nAlways-In: %s | Swings: %d",
                                   StateLabel(g_engine.MediumState()), StateLabel(g_contextInfo.microState),
                                   AlwaysInLabel(g_engine.AlwaysInState()), swingCount);
      g_renderer.DrawStatePanel(panel);
     }
   else
      g_renderer.HideStatePanel();

   return(rates_total);
  }
//+------------------------------------------------------------------+

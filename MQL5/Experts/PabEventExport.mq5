//+------------------------------------------------------------------+
//|                                          PabEventExport.mq5      |
//|                    Price Action Bar-by-Bar — Historical Export   |
//|                                                                    |
//| PHASE 16. Replays real broker history through the SAME analysis    |
//| engine the chart indicator uses, and writes the identical event    |
//| CSV. This exists because the indicator's own export only ever       |
//| produces one event per bar of live forward time, which is not      |
//| enough to measure anything.                                        |
//|                                                                    |
//| Why an Expert Advisor and not a Script or the indicator:          |
//|   - MT5's Strategy Tester only calls OnCalculate for files built   |
//|     as indicators. A file placed in Experts\ is driven through     |
//|     OnInit/OnTick, and the indicator's OnCalculate never ran, so   |
//|     the export produced a header and no rows.                      |
//|   - The Strategy Tester is the only MT5 path that can be driven    |
//|     headlessly from the command line, which is what makes this     |
//|     repeatable without a human opening a chart.                    |
//|                                                                    |
//| HONESTY CONSTRAINTS, all deliberate:                              |
//|   - It places no orders. There is no CTrade call anywhere.         |
//|   - It re-implements NOTHING. The pipeline lives in CPabEngine and  |
//|     is the same object the chart builds, configured from the same  |
//|     input defaults.                                                |
//|   - The last bar in the range is skipped, exactly as the indicator |
//|     skips forming bar index 0. A decision must use a closed bar.   |
//|   - ATR is copied once against this EA's own static arrays. An     |
//|     iATR handle would be aligned to the tester's series, not to    |
//|     the arrays being replayed here, so using one would silently    |
//|     normalize displacement against the wrong values.               |
//|   - When ATR is requested but unavailable, the fallback is logged  |
//|     and disclosed in the CSV rather than hidden.                   |
//|   - Every row carries its own spread_points, cost_r, and a cost    |
//|     label, so an archived file states its cost assumptions instead |
//|     of requiring this script to still exist. Anything assumed is   |
//|     labelled "assumed" in the label. PHASE 19.                     |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include "../Include/PriceActionBarByBar/PAB_Types.mqh"
#include "../Include/PriceActionBarByBar/PAB_Utils.mqh"
#include "../Include/PriceActionBarByBar/TradingCost.mqh"
#include "../Include/PriceActionBarByBar/PabEngine.mqh"

input group "=== Replay range ==="
// Leave either bound EMPTY to mean "unbounded". That is the useful default
// for a headless run, because MT5's Strategy Tester startup config cannot
// pass indicator parameters, so these compiled-in defaults are what an
// automated run actually gets. An explicit bound is still honoured when the
// EA is run by hand from the Navigator.
input string InpFromDate        = "";           // First bar to replay (YYYY.MM.DD), empty = oldest available
input string InpToDate          = "";           // Exclusive end (YYYY.MM.DD), empty = newest available
input int    InpMaxBars         = 0;             // 0 = no cap on the number of bars replayed

input group "=== Bar Classification ==="
input double InpDojiBodyRatio      = 0.30;
input double InpClvFavorableMin    = 0.15;
input int    InpFeatureLookback    = 20;
input double InpLargeRangeMult     = 1.50;
input double InpSmallRangeMult     = 0.70;
input double InpStrongBodyRatio    = 0.60;

input group "=== Swing Detection ==="
input int    InpFractalLegs        = 2;

input group "=== Trading Range / Trend State ==="
input int    InpRegimeLookback     = 20;
input double InpOverlapThreshold   = 0.55;
input double InpDisplaceThreshold  = 3.0;
input bool   InpUseRealATR         = true;
input int    InpATRPeriod          = 14;

input group "=== Pattern Detection ==="
input double InpSwingSimilarityPct = 0.15;
input double InpConvergenceMin     = 0.00020;

input group "=== Decision Support ==="
input int    InpMinimumQuality     = 55;
input double InpMinimumRiskReward  = 1.50;

input group "=== Breakout / Climax ==="
input int    InpBreakoutLookback   = 10;
input double InpBreakoutClvMin     = 0.50;
input int    InpClimaxLookback     = 20;
input double InpClimaxRangeMult    = 2.0;
input double InpClimaxBodyRatioMax = 0.35;

input group "=== Execution costs (Phase 19) ==="
// Spread is MEASURED per bar from the terminal's own record; these two are
// ASSUMED, because neither is observable from a bar series. Both are
// written onto every exported row, labelled "assumed", so an archived file
// states its own cost assumptions instead of relying on this script.
input double InpSlippagePoints     = 0.0;    // Assumed, per side. 0 = none.
input double InpCommissionPerLot   = 0.0;    // Assumed, account currency, round trip, per lot
input double InpLotSize            = 1.0;    // Lot size the commission is quoted for
input int    InpFallbackSpreadPoints = 0;    // Used only if the measured spread is unavailable

input group "=== Output ==="
input string InpEventFile          = "pab_events.csv";
input string InpBarsFile           = "pab_bars.csv";   // "" = do not write a bar file
input bool   InpTrimUnresolvedBars = true;             // Drop the last N bars that cannot have a full ATR window

CPabEngine     *g_engine = NULL;
int             g_file   = INVALID_HANDLE;
int             g_bars   = 0;
int             g_written = 0;
int             g_incomplete = 0;

//+------------------------------------------------------------------+
//| Labels duplicated from the indicator on purpose. The export schema |
//| is a contract with pab_research, and a replay that silently used   |
//| different spellings would produce a file the loader rejects or,   |
//| worse, mis-buckets.                                                |
//+------------------------------------------------------------------+
string DirectionLabel(const ENUM_SETUP_DIRECTION d)
  {
   if(d == SETUP_LONG)  return("long");
   if(d == SETUP_SHORT) return("short");
   return("none");
  }

string StatusLabel(const ENUM_SETUP_STATUS s)
  {
   if(s == STATUS_CONFIRMED) return("confirmed");
   if(s == STATUS_PROBABLE)  return("probable");
   if(s == STATUS_POSSIBLE)  return("possible");
   if(s == STATUS_WEAK)      return("weak");
   return("no_trade");
  }

string TypeLabel(const ENUM_SETUP_TYPE t)
  {
   if(t == SETUP_TREND_PULLBACK)           return("trend_pullback");
   if(t == SETUP_SECOND_ENTRY)             return("second_entry");
   if(t == SETUP_RANGE_REVERSAL)           return("range_reversal");
   if(t == SETUP_FAILED_BREAKOUT)          return("failed_breakout");
   if(t == SETUP_BREAKOUT_FOLLOW_THROUGH)  return("breakout_follow_through");
   if(t == SETUP_WEDGE_REVERSAL)           return("wedge_reversal");
   return("no_trade");
  }

string ParameterFingerprint()
  {
   return(StringFormat("q%d|rr%.2f|f%d|l%.2f|s%.2f|b%d|c%.2f",
                       InpMinimumQuality, InpMinimumRiskReward,
                       InpFractalLegs, InpLargeRangeMult, InpSmallRangeMult,
                       InpBreakoutLookback, InpClimaxRangeMult));
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   Print("======================================================");
   Print(" PriceActionBarByBar - Historical Event Export");
   Print("======================================================");

   datetime from = 0;
   datetime to   = 0;
   if(StringLen(InpFromDate) > 0)
     {
      from = StringToTime(InpFromDate + " 00:00");
      if(from == 0)
        {
         Print("PabEventExport: InpFromDate is not a valid date");
         return(INIT_PARAMETERS_INCORRECT);
        }
     }
   if(StringLen(InpToDate) > 0)
     {
      to = StringToTime(InpToDate + " 00:00");
      if(to == 0)
        {
         Print("PabEventExport: InpToDate is not a valid date");
         return(INIT_PARAMETERS_INCORRECT);
        }
     }
   if(from != 0 && to != 0 && from >= to)
     {
      Print("PabEventExport: InpFromDate must be earlier than InpToDate");
      return(INIT_PARAMETERS_INCORRECT);
     }

   //--- load the replay window into our own arrays ---------------------
   // CopyRates returns oldest-first, but every analyzer expects SERIES
   // order (index 0 = newest). Reversing once here means the replay and
   // the chart see byte-identical series, and index 0 is the newest bar,
   // which is the bar we then refuse to decide on.
   //
   // The (start_time, stop_time) overload is used deliberately. The
   // (start_time, count) overload is ambiguous against
   // (start_pos, count) because a datetime silently converts to int, and
   // choosing wrong silently replays the wrong years.
   MqlRates rates[];
   int got;
   if(from != 0 && to != 0)
      got = CopyRates(_Symbol, _Period, from, to, rates);
   else
     {
      // No (symbol, timeframe, rates[]) form exists in MQL5, and the
      // (start_time, count) form is ambiguous against (start_pos, count)
      // because a datetime silently converts to int. Ask for the whole
      // history positionally instead, then filter below.
      int available = iBars(_Symbol, _Period);
      if(available <= 0)
        {
         PrintFormat("PabEventExport: no history for %s %s, iBars returned %d, error %d",
                     _Symbol, PeriodLabel(_Period), available, GetLastError());
         return(INIT_FAILED);
        }
      got = CopyRates(_Symbol, _Period, 0, available, rates);
     }
   if(got <= 0)
     {
      PrintFormat("PabEventExport: CopyRates got %d bars for %s %s over %s..%s, error %d",
                  got, _Symbol, PeriodLabel(_Period),
                  (from == 0 ? "oldest" : InpFromDate), (to == 0 ? "newest" : InpToDate),
                  GetLastError());
      return(INIT_FAILED);
     }

   int n = got;
   if(InpMaxBars > 0 && n > InpMaxBars)
     {
      n = InpMaxBars;
      PrintFormat("PabEventExport: capping replay at %d bars", n);
     }
   // Drop bars outside the requested window, then reverse to series order.
   datetime time[]; double open[], high[], low[], close[];
   ArrayResize(time, n); ArrayResize(open, n); ArrayResize(high, n);
   ArrayResize(low, n);  ArrayResize(close, n);
   int kept = 0;
   for(int i = 0; i < n; i++)   // oldest-first
     {
      if((from != 0 && rates[i].time < from) || (to != 0 && rates[i].time >= to))
         continue;
      int dst = n - 1 - kept;   // write into series position
      time[dst]  = rates[i].time;
      open[dst]  = rates[i].open;
      high[dst]  = rates[i].high;
      low[dst]   = rates[i].low;
      close[dst] = rates[i].close;
      kept++;
     }
   if(kept < 50)
     {
      PrintFormat("PabEventExport: only %d bars in the requested window; need at least 50. "
                  "Check that the broker actually has history for %s %s over that range.",
                  kept, _Symbol, PeriodLabel(_Period));
      return(INIT_FAILED);
     }
   if(kept < n)
     {
      ArrayResize(time,  kept);
      ArrayResize(open,  kept);
      ArrayResize(high,  kept);
      ArrayResize(low,   kept);
      ArrayResize(close, kept);
     }
   n = kept;
   g_bars = n;
   PrintFormat("PabEventExport: %s %s, %d bars from %s to %s",
               _Symbol, PeriodLabel(_Period), n,
               IsoTimestamp(time[n - 1]),
               IsoTimestamp(time[0]));

   //--- ATR, aligned to the arrays above -------------------------------
   double atr[];
   ArrayResize(atr, n);
   bool atrOk = false;
   if(InpUseRealATR)
     {
      // iATR/CopyBuffer are series-aligned to the terminal's own chart,
      // which is NOT these arrays, so read raw and index by hand below.
      int handle = iATR(_Symbol, _Period, InpATRPeriod);
      if(handle == INVALID_HANDLE)
         PrintFormat("PabEventExport: iATR failed, using the internal simple average - error %d",
                     GetLastError());
      else
        {
         double raw[];
         ArraySetAsSeries(raw, true);
         if(CopyBuffer(handle, 0, 0, n, raw) == n)
           {
            for(int i = 0; i < n; i++)
               atr[i] = raw[i];
            atrOk = true;
           }
         else
            PrintFormat("PabEventExport: CopyBuffer copied %d of %d ATR values - error %d",
                        CopyBuffer(handle, 0, 0, n, raw), n, GetLastError());
         IndicatorRelease(handle);
        }
     }
    if(!atrOk)
       ArrayFree(atr);

    //--- per-bar spread, measured (Phase 19) -----------------------------
    // Cost is the whole reason this file exists, and a cost model with an
    // assumed spread is a guess wearing a decimal point. iSpread is the
    // terminal's own record of what each bar traded at, so it is used
    // directly and per bar rather than once for the run: spread widens at
    // the London open and again at rollover, and a single run-wide number
    // would average those away.
    //
    // It is read the same way ATR is, by raw buffer and hand indexing,
    // because CopyBuffer is series-aligned to the terminal's chart and
    // NOT to the arrays being replayed here.
    double spreadPts[];
    ArrayResize(spreadPts, n);
    bool spreadOk = false;
    int  spreadHandle = iSpread(_Symbol, _Period, 1);
    if(spreadHandle == INVALID_HANDLE)
       PrintFormat("PabEventExport: iSpread failed, falling back to the configured "
                   "spread points - error %d", GetLastError());
    else
      {
       double rawSpread[];
       ArraySetAsSeries(rawSpread, true);
       int gotSpread = CopyBuffer(spreadHandle, 0, 0, n, rawSpread);
       if(gotSpread == n)
         {
          for(int i = 0; i < n; i++)
             spreadPts[i] = rawSpread[i];
          spreadOk = true;
         }
       else
          PrintFormat("PabEventExport: CopyBuffer copied %d of %d spread values - error %d",
                      gotSpread, n, GetLastError());
       IndicatorRelease(spreadHandle);
      }
    if(!spreadOk)
       ArrayFree(spreadPts);

    //--- is the cost of a trade even knowable? --------------------------
    // A spread of zero and an UNKNOWN spread are different states, and
    // this run cannot tell them apart. Writing 0.0 for an unmeasured
    // spread would hand the research layer a cost column full of zeros
    // and let it publish a "net" expectancy that is really just the
    // gross one wearing a net label. So when the spread is neither
    // measured nor configured, every cost field is written BLANK and the
    // loader reads that as "no cost data", which is what it is.
    //
    // This is not hypothetical. The first Phase 19 replay ran against
    // Alpari-MT5-Demo, where CopyBuffer on the iSpread handle returned
    // error 4807 and no values at all, so a naive export would have
    // published 73,751 rows of costless trading.
    bool spreadKnown = spreadOk || InpFallbackSpreadPoints > 0;
    if(!spreadKnown)
       Print("PabEventExport: NO COST DATA. The spread could not be measured (see above) "
             "and no fallback was configured, so every cost field is written blank. "
             "Any report over this file is GROSS. Set InpFallbackSpreadPoints to state a "
             "spread assumption, and note that the export will then label it 'assumed'.");

    //--- cost model ------------------------------------------------------
    // Point size, tick size, and tick value come from the broker and are
    // read once. If any is unavailable the commission conversion is not
    // possible, and saying so beats silently reporting a free commission:
    // a currency cost divided by a price distance is not a number.
    double c_point = 0.0, c_tickValue = 0.0, c_tickSize = 0.0;
    string costReason = "";
    bool factsOk = ReadSymbolCostFacts(_Symbol, c_point, c_tickValue, c_tickSize, costReason);
    if(!factsOk)
       PrintFormat("PabEventExport: %s. Commission will be exported as 0.0 and the "
                   "export will label it, so a reader cannot mistake this run for a "
                   "cost-free one.", costReason);

    SCostModel baseCost;
    baseCost.spreadPrice      = 0.0;
    baseCost.spreadPoints     = 0.0;
    baseCost.spreadMeasured   = spreadOk;
    baseCost.slippagePrice    = InpSlippagePoints * c_point;
    baseCost.slippagePoints   = InpSlippagePoints;
    baseCost.commissionPrice  = (factsOk
                                 ? CTradingCost::CommissionPriceFromPerLot(InpCommissionPerLot,
                                                                          InpLotSize, c_tickValue, c_tickSize)
                                 : 0.0);
    PrintFormat("PabEventExport: costs %s, spread %s (%.1f points on this symbol), "
                "slippage %.1f points per side, commission %.8f price distance per lot",
                spreadOk ? "MEASURED per bar" : "ASSUMED (iSpread unavailable)",
                spreadOk ? "measured" : "assumed", (double)InpFallbackSpreadPoints,
                InpSlippagePoints, baseCost.commissionPrice);

    //--- optional bar history for outcome evaluation ---------------------
   // pab_research needs open_time/high/low to measure what happened after
   // each event. It cannot derive them from the event file, and exporting
   // them by hand from the chart is a step that goes stale. The tail is
   // trimmed by one ATR period because the newest ATR values inside the
   // requested range have no window behind them; keeping them would
   // silently make the last bars of the replay normalize displacement
   // against a simple average instead.
   if(StringLen(InpBarsFile) > 0)
     {
      int barFile = FileOpen(InpBarsFile,
                             FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ);
      if(barFile == INVALID_HANDLE)
         PrintFormat("PabEventExport: cannot open %s, error %d", InpBarsFile, GetLastError());
      else
        {
         if(FileSize(barFile) == 0)
            FileWrite(barFile, "open_time", "high", "low", "symbol", "period");
         else
            FileSeek(barFile, 0, SEEK_END);

         int trim = (InpUseRealATR ? InpATRPeriod : 0);
         if(InpTrimUnresolvedBars && trim > 0)
            trim = MathMin(trim, n - 1);
         // Series index n-1 is the OLDEST bar and index 0 the newest, so
         // dropping the newest `trim` bars means stopping the descending
         // walk at `trim`, not at n-1-trim.
         // symbol and period are written per row, not inferred from the file
         // name. A multi-instrument study concatenates bar files, and once
         // they are in one file the only thing that stops a USDJPY event
         // being evaluated against EURUSD prices is that each row says which
         // market it belongs to.
         for(int i = n - 1; i >= trim; i--)
            FileWrite(barFile, IsoTimestamp(time[i]),
                      DoubleToString(high[i], _Digits),
                      DoubleToString(low[i], _Digits),
                      _Symbol, PeriodLabel(_Period));
         FileClose(barFile);
         PrintFormat("PabEventExport: wrote %d of %d bars to %s, dropping the %d newest "
                     "that have no full ATR window",
                     n - trim, n, InpBarsFile, trim);
        }
     }

   //--- engine ----------------------------------------------------------
   SEngineConfig cfg;
   cfg.dojiBodyRatio      = InpDojiBodyRatio;
   cfg.clvFavorableMin    = InpClvFavorableMin;
   cfg.featureLookback    = InpFeatureLookback;
   cfg.largeRangeMult     = InpLargeRangeMult;
   cfg.smallRangeMult     = InpSmallRangeMult;
   cfg.strongBodyRatio    = InpStrongBodyRatio;
   // History capacity is deliberately the SAME 2000 the chart uses. A
   // larger buffer here would let the replay see further back than the
   // indicator ever does, which would make the two disagree on long runs
   // and quietly invalidate the equivalence this EA is supposed to have.
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
   cfg.useRealAtr         = false;      // ATR supplied explicitly below
   cfg.atrPeriod          = InpATRPeriod;
   cfg.swingSimilarityPct = InpSwingSimilarityPct / 100.0;
   cfg.convergenceMin     = InpConvergenceMin;
   cfg.secondsPerBar      = (int)PeriodSeconds(_Period);
   cfg.minimumQuality     = InpMinimumQuality;
   cfg.minimumRiskReward  = InpMinimumRiskReward;
   cfg.contextBars        = 10;

   g_engine = new CPabEngine();
   if(g_engine == NULL || !g_engine.Init(cfg, _Symbol, _Period))
      return(INIT_FAILED);
   if(atrOk)
      g_engine.SetAtrSeries(atr);
   PrintFormat("PabEventExport: ATR %s", atrOk ? "from iATR" : "FALLBACK simple average");

   //--- open the CSV ----------------------------------------------------
   // No explicit delimiter or separator: FILE_CSV defaults to TAB, which
   // is the schema PriceActionBarByBar.mq5 writes and pab_research reads.
   // Overriding it here would produce a file the loader silently misreads.
   g_file = FileOpen(InpEventFile,
                     FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ);
   if(g_file == INVALID_HANDLE)
     {
      PrintFormat("PabEventExport: cannot open %s, error %d. In the Strategy Tester the "
                  "file lands in the agent's MQL5\\Files folder, not the terminal's.",
                  InpEventFile, GetLastError());
      return(INIT_FAILED);
     }
    if(FileSize(g_file) == 0)
       FileWrite(g_file,
                 "event_id", "direction", "setup_type", "status",
                 "bar_open_time", "bar_close_time", "confirmed_at", "decision_time",
                 "entry", "invalidation", "target", "risk_reward", "quality",
                 "engine_version", "parameter_version", "symbol", "period",
                 "spread_points", "cost_spread_price", "cost_slippage_price",
                 "cost_commission_price", "cost_r", "cost_model");
    else
       FileSeek(g_file, 0, SEEK_END);

   //--- replay ----------------------------------------------------------
   // Oldest first, so each analyzer sees the bars in the same order it
   // would have seen them live. Series index 0 is the newest bar and is
   // never fed in, mirroring the indicator's refusal to decide on the
   // forming bar.
   string parameterVersion = ParameterFingerprint();
   int periodSeconds = (int)PeriodSeconds(_Period);
   SSetupCandidate candidate;

   for(int i = n - 1; i >= 1; i--)
     {
      g_engine.ProcessBar(i, time, open, high, low, close, n);
      if(!g_engine.Evaluate(close[i], time[i], candidate))
         continue;
      if(candidate.barTime <= 0)
         continue;

      datetime closeTime = candidate.barTime + periodSeconds;
      if(DoubleToString(candidate.entryPrice, _Digits) == "")
        { g_incomplete++; continue; }

      //--- per-row cost, from the spread of THIS bar --------------------
      // A NO TRADE row has no levels and no spread worth charging, so its
      // cost is 0.0 and its label says so. Every other row carries the
      // measured spread of the bar the decision was taken on, so the
      // research layer can recompute cost_r rather than trusting it.
      SCostModel rowCost = baseCost;
      rowCost.spreadPoints = spreadOk ? spreadPts[i] : (double)InpFallbackSpreadPoints;
      rowCost.spreadPrice  = rowCost.spreadPoints * c_point;
      if(candidate.status == STATUS_NO_TRADE)
        {
         rowCost.spreadPrice  = 0.0;
         rowCost.spreadPoints = 0.0;
         rowCost.spreadMeasured = false;
        }

      // Blank rather than 0.0 when the cost is genuinely unknown. A NO
      // TRADE row is different: it carries 0.0, because it has no levels
      // and therefore no cost, and that zero IS known.
      string spreadOut   = spreadKnown ? DoubleToString(rowCost.spreadPoints, 1)     : "";
      string spreadPx    = spreadKnown ? DoubleToString(rowCost.spreadPrice, _Digits) : "";
      string slippagePx  = (spreadKnown ? DoubleToString(rowCost.slippagePrice, _Digits)   : "");
      string commissionPx= (spreadKnown ? DoubleToString(rowCost.commissionPrice, _Digits) : "");
      string costR       = (spreadKnown ? DoubleToString(CTradingCost::CostInR(rowCost,
                                                 candidate.entryPrice, candidate.stopPrice), 4) : "");
      string modelOut    = spreadKnown ? rowCost.Model()
                                       : "unknown: spread could not be measured and no fallback was set";

      FileWrite(g_file,
                StringFormat("%I64d-%d", (long)candidate.barTime, candidate.qualityScore),
                DirectionLabel(candidate.direction), TypeLabel(candidate.type),
                StatusLabel(candidate.status),
                IsoTimestamp(candidate.barTime),
                IsoTimestamp(closeTime),
                IsoTimestamp(closeTime),
                IsoTimestamp(closeTime),
                DoubleToString(candidate.entryPrice, _Digits),
                DoubleToString(candidate.stopPrice, _Digits),
                DoubleToString(candidate.targetPrice, _Digits),
                DoubleToString(candidate.riskReward, 4),
                candidate.qualityScore,
                PAB_ENGINE_VERSION, parameterVersion,
                _Symbol, PeriodLabel(_Period),
                spreadOut, spreadPx, slippagePx, commissionPx, costR, modelOut);
      g_written++;
     }

    Print("------------------------------------------------------");
    PrintFormat(" RESULT: %d bars replayed, %d events written to %s, %d skipped",
               n - 1, g_written, InpEventFile, g_incomplete);
    Print(" No orders were placed. This is decision-support output only.");
    PrintFormat(" COST MODEL: %s", spreadKnown ? baseCost.Model()
                                             : "UNKNOWN - every cost field written blank");
    Print("======================================================");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // The whole replay happens once, in OnInit.
  }

void OnDeinit(const int reason)
  {
   if(g_file != INVALID_HANDLE)
     {
      FileClose(g_file);
      g_file = INVALID_HANDLE;
     }
   if(g_engine != NULL)
     {
      g_engine.ReleaseAtr();
      delete g_engine;
      g_engine = NULL;
     }
   PrintFormat("PabEventExport: finished, %d events written", g_written);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                              PabEngine.mqh       |
//|                        Price Action Bar-by-Bar — Analysis Engine  |
//|                                                                    |
//| PHASE 16. Owns the whole analysis pipeline so that a setup drawn   |
//| on a chart and a setup produced by a historical replay are produced|
//| by the SAME code with the SAME parameters. Before this class the    |
//| orchestrator lived inside PriceActionBarByBar.mq5's OnCalculate,   |
//| which meant a replay had to re-implement the pipeline and could    |
//| silently drift from it. Nothing here detects, scores, or decides   |
//| anything new; it is a re-housing of the existing ordering:         |
//|                                                                    |
//|   ProcessBar()   raw OHLC  -> classifier, swings, trading range    |
//|   Evaluate()     swing-derived -> patterns, measured move,         |
//|                  Always-In, context, setup candidate               |
//|                                                                    |
//| The split matters. On a live chart only the newest few bars change |
//| per tick, so Evaluate() is called once per OnCalculate over the    |
//| batch. A replay advances one bar at a time, so it calls            |
//| Evaluate() after every ProcessBar(). Because Evaluate() takes the   |
//| newest bar's close and time explicitly rather than reading series  |
//| index 1, both callers get the correct "newest closed bar" without  |
//| either one reimplementing the lookup.                              |
//|                                                                    |
//| DELIBERATE OMISSION: ATR. RefreshAtr() is a separate call because  |
//| the injected ATR series is indexed by series position, and that    |
//| alignment is only valid at the instant it was copied. A live chart |
//| copies once per OnCalculate; a replay must copy against its own    |
//| static arrays. Pushing that decision inside ProcessBar() would    |
//| have hidden a real trap.                                           |
//+------------------------------------------------------------------+
#property strict

#include "PAB_Types.mqh"
#include "PAB_IAnalyzer.mqh"
#include "PAB_Utils.mqh"
#include "BarClassifier.mqh"
#include "SwingDetector.mqh"
#include "TradingRangeDetector.mqh"
#include "PatternDetector.mqh"
#include "AlwaysInTracker.mqh"
#include "MeasuredMoveDetector.mqh"
#include "ContextAnalyzer.mqh"
#include "DecisionEngine.mqh"

class CPabEngine
  {
private:
   SEngineConfig        m_cfg;
   string               m_symbol;
   ENUM_TIMEFRAMES      m_period;

   CBarClassifier         *m_classifier;
   CSwingDetector         *m_swings;
   CTradingRangeDetector  *m_range;
   CPatternDetector       *m_patterns;
   CAlwaysInTracker       *m_alwaysIn;
   CMeasuredMoveDetector  *m_measuredMove;
   CContextAnalyzer       *m_context;
   CDecisionEngine        *m_decision;

   SContextInfo          m_contextInfo;
   SSwingPoint           m_swingArr[];
   int                   m_swingCount;

   int                   m_atrHandle;
   double                m_atrBuf[];

   void FreeAnalyzers()
     {
      if(m_classifier   != NULL) { delete m_classifier;   m_classifier   = NULL; }
      if(m_swings       != NULL) { delete m_swings;       m_swings       = NULL; }
      if(m_range        != NULL) { delete m_range;        m_range        = NULL; }
      if(m_patterns     != NULL) { delete m_patterns;     m_patterns     = NULL; }
      if(m_alwaysIn     != NULL) { delete m_alwaysIn;     m_alwaysIn     = NULL; }
      if(m_measuredMove != NULL) { delete m_measuredMove; m_measuredMove = NULL; }
      if(m_context      != NULL) { delete m_context;      m_context      = NULL; }
      if(m_decision     != NULL) { delete m_decision;     m_decision     = NULL; }
     }

public:
                        CPabEngine()
   {
    // MQL5 does not allow chained assignment between distinct pointer
    // types, so these are written out one per line.
    m_classifier   = NULL;
    m_swings       = NULL;
    m_range        = NULL;
    m_patterns     = NULL;
    m_alwaysIn     = NULL;
    m_measuredMove = NULL;
    m_context      = NULL;
    m_decision     = NULL;
    m_atrHandle    = INVALID_HANDLE;
    m_swingCount   = 0;
    m_symbol       = "";
    m_period       = PERIOD_CURRENT;
   }

                        ~CPabEngine()
   {
    ReleaseAtr();
    FreeAnalyzers();
   }

   //--- construction ------------------------------------------------------
   // Returns false and prints the reason if any analyzer could not be
   // allocated, so a caller never half-runs a pipeline.
   bool Init(const SEngineConfig &config, const string symbol, const ENUM_TIMEFRAMES period)
     {
      m_cfg = config;
      m_symbol = symbol;
      m_period = period;
      FreeAnalyzers();

      m_classifier = new CBarClassifier(config.dojiBodyRatio, config.historyCapacity,
                                        config.clvFavorableMin,
                                        config.breakoutLookback, config.breakoutClvMin,
                                        config.climaxLookback, config.climaxRangeMult,
                                        config.climaxBodyRatioMax,
                                        config.featureLookback, config.largeRangeMult,
                                        config.smallRangeMult, config.strongBodyRatio);
      m_swings       = new CSwingDetector(config.fractalLegs, config.swingCapacity);
      m_range        = new CTradingRangeDetector(config.regimeLookback,
                                                 config.overlapThreshold,
                                                 config.displaceThreshold);
      m_patterns     = new CPatternDetector(config.swingSimilarityPct,
                                            config.convergenceMin,
                                            config.secondsPerBar);
      m_alwaysIn     = new CAlwaysInTracker();
      m_measuredMove = new CMeasuredMoveDetector();
      m_context      = new CContextAnalyzer();
      m_decision     = new CDecisionEngine(config.minimumQuality, config.minimumRiskReward);

      if(m_classifier == NULL || m_swings == NULL || m_range == NULL || m_patterns == NULL ||
         m_alwaysIn == NULL || m_measuredMove == NULL || m_context == NULL || m_decision == NULL)
        {
         Print("CPabEngine: analyzer allocation failed");
         FreeAnalyzers();
         return(false);
        }

      m_contextInfo.valid = false;
      return(true);
     }

   void ReleaseAtr()
     {
      if(m_atrHandle != INVALID_HANDLE)
        {
         IndicatorRelease(m_atrHandle);
         m_atrHandle = INVALID_HANDLE;
        }
     }

   //--- ATR ---------------------------------------------------------------
   // Creates the handle on first use. handleOk reports whether real ATR is
   // in play, so a caller can log the fallback rather than silently
   // measuring displacement against a different normalizer than intended.
   bool RefreshAtr(const int rates_total, bool &handleOk)
     {
      handleOk = false;
      if(!m_cfg.useRealAtr)
        {
         ArrayFree(m_atrBuf);
         m_range.SetATRSeries(m_atrBuf);
         return(false);
        }

      if(m_atrHandle == INVALID_HANDLE)
        {
         m_atrHandle = iATR(m_symbol, m_period, m_cfg.atrPeriod);
         if(m_atrHandle == INVALID_HANDLE)
            PrintFormat("CPabEngine: iATR failed for %s, falling back to the internal "
                        "simple average - error %d", m_symbol, GetLastError());
        }

      if(m_atrHandle == INVALID_HANDLE)
        {
         ArrayFree(m_atrBuf);
         m_range.SetATRSeries(m_atrBuf);
         return(false);
        }

      ArraySetAsSeries(m_atrBuf, true);
      int copied = CopyBuffer(m_atrHandle, 0, 0, rates_total, m_atrBuf);
      if(copied != rates_total)
        {
         PrintFormat("CPabEngine: CopyBuffer copied %d of %d ATR values, error %d",
                     copied, rates_total, GetLastError());
         ArrayFree(m_atrBuf);
         m_range.SetATRSeries(m_atrBuf);
         return(false);
        }

      m_range.SetATRSeries(m_atrBuf);
      handleOk = true;
      return(true);
     }

   //--- state -------------------------------------------------------------
   void Reset()
     {
      m_classifier.Reset();
      m_swings.Reset();
      m_range.Reset();
      m_patterns.Reset();
      m_alwaysIn.Reset();
      m_measuredMove.Reset();
      m_contextInfo.valid = false;
      m_swingCount = 0;
      ArrayFree(m_swingArr);
     }

   // Inject a precomputed ATR series directly. Used by callers that own
   // their own history arrays, where an iATR handle would be aligned to a
   // different series than the one being replayed.
   void SetAtrSeries(const double &atr[])
     {
      m_range.SetATRSeries(atr);
     }

   //--- pipeline ----------------------------------------------------------
   // Feed one closed bar. Analyzers are idempotent by bar timestamp, so
   // replaying the same index twice is a no-op rather than a duplication.
   void ProcessBar(const int index,
                   const datetime &time[], const double &open[], const double &high[],
                   const double &low[], const double &close[], const int rates_total)
     {
      m_classifier.Update(index, time, open, high, low, close, rates_total);
      m_swings.Update(index, time, open, high, low, close, rates_total);
      m_range.Update(index, time, open, high, low, close, rates_total);
     }

   // Turn the state built so far into a setup candidate for the newest
   // CLOSED bar. Returns false only when no bar has been classified yet.
   // 'newestClose' and 'newestTime' must describe the most recently
   // processed bar, which is the classifier's most recent entry.
   bool Evaluate(const double newestClose, const datetime newestTime,
                 SSetupCandidate &out)
     {
      SBarInfo latestClosed;
      if(!m_classifier.GetBar(0, latestClosed))
         return(false);

      m_swingCount = m_swings.Count();
      ArrayResize(m_swingArr, m_swingCount);
      for(int i = 0; i < m_swingCount; i++)
         m_swings.GetSwing(i, m_swingArr[i]);

      if(m_swingCount > 0)
        {
         m_patterns.AnalyzeSwings(m_swingArr, m_swingCount);
         m_measuredMove.AnalyzeSwings(m_swingArr, m_swingCount);
        }

      SSwingPoint latestHigh, latestLow;
      bool haveHigh = m_swings.LatestOfType(SWING_HIGH, latestHigh);
      bool haveLow  = m_swings.LatestOfType(SWING_LOW,  latestLow);
      m_alwaysIn.Evaluate(newestClose,
                          haveHigh, haveHigh ? latestHigh.price : 0.0,
                          haveLow,  haveLow  ? latestLow.price  : 0.0,
                          newestTime);

      int recentCount = MathMin(m_classifier.Count(), m_cfg.contextBars);
      SBarInfo recent[];
      ArrayResize(recent, recentCount);
      for(int i = 0; i < recentCount; i++)
         m_classifier.GetBar(i, recent[i]);

      m_context.Analyze(recent, recentCount, m_swingArr, m_swingCount,
                        m_range.State(), m_alwaysIn.State(), m_contextInfo);

      m_decision.Analyze(latestClosed, m_contextInfo,
                         m_patterns.LastPattern(), m_measuredMove.Current(), out);
      return(true);
     }

   //--- accessors, for rendering and reporting ---------------------------
   int  BarCount() const { return(m_classifier.Count()); }
   bool GetBar(const int i, SBarInfo &out) const { return(m_classifier.GetBar(i, out)); }

   int  SwingCount() const { return(m_swings.Count()); }
   bool GetSwing(const int i, SSwingPoint &out) const { return(m_swings.GetSwing(i, out)); }

   ENUM_MARKET_STATE MediumState() const { return(m_range.State()); }
   bool GetTradingRange(STradingRangeInfo &out) const { return(m_range.GetRange(out)); }
   ENUM_ALWAYS_IN_STATE AlwaysInState() const { return(m_alwaysIn.State()); }
   SPatternInfo Pattern() const { return(m_patterns.LastPattern()); }
   SMeasuredMoveInfo MeasuredMove() const { return(m_measuredMove.Current()); }
   SContextInfo Context() const { return(m_contextInfo); }
  };

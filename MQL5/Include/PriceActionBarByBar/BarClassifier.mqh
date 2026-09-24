//+------------------------------------------------------------------+
//|                                              BarClassifier.mqh   |
//|                                                                    |
//| Classifies every bar per Al Brooks' bar-by-bar taxonomy:          |
//|   - Trend bar (bull/bear) vs Doji                                  |
//|   - Inside bar / Outside bar                                      |
//|   - Pullback sequence numbering (H1/H2/H3+, L1/L2/L3+)             |
//|   - Phase 2: objective signal-quality score for pullback bars      |
//|     (Close Location Value + "shallower-than-previous-pullback"    |
//|     check, the closest objective proxy to Brooks' qualitative     |
//|     "does this H2 look tradeable" judgment)                       |
//|                                                                    |
//| Single responsibility: this class ONLY classifies bars. It knows  |
//| nothing about swings, ranges, patterns or chart drawing — those   |
//| live in their own classes and consume SBarInfo[] as input.        |
//|                                                                    |
//| Storage: fixed-capacity CIRCULAR buffer (head/size, no memmove)   |
//| so push cost is O(1) regardless of history length — see           |
//| ROADMAP.md Phase 2 for why this replaced the earlier shift-based  |
//| version.                                                            |
//+------------------------------------------------------------------+
#property strict

#include "PAB_Types.mqh"
#include "PAB_IAnalyzer.mqh"
#include "PAB_Utils.mqh"

class CBarClassifier : public IAnalyzer
  {
private:
   double            m_dojiBodyRatio;     // body/range below this => Doji
   double            m_clvFavorableMin;   // |CLV| threshold above which a pullback bar's close is "favorable"

   // Phase 3: breakout / climax detection parameters.
   int               m_breakoutLookback;   // bars to look back for the "fresh extreme" check
   double            m_breakoutClvMin;     // |CLV| threshold for a breakout bar's close
   int               m_climaxLookback;     // bars used to compute the average range baseline
   double            m_climaxRangeMult;    // range must be >= this * average range to qualify as climax
   double            m_climaxBodyRatioMax; // body/range must be <= this (weak/indecisive close) to qualify as climax

   //--- circular buffer state -----------------------------------------------
   int               m_capacity;
   int               m_size;
   int               m_head;              // index of the most recent bar (logical position 0)
   datetime          m_lastProcessedTime;
   SBarInfo          m_bars[];

   // Pullback-sequence state machine. A "leg" starts when a trend bar
   // makes a new local extreme in one direction; every bar afterward
   // that fails to extend that extreme is numbered as a pullback bar
   // (H1, H2, H3+ in a bull leg; L1, L2, L3+ in a bear leg) until a
   // new trend bar re-extends the extreme, which resets the count.
   bool              m_haveLeg;
   bool              m_legIsBull;         // true = tracking a bull leg (H-pullbacks)
   double            m_legExtreme;        // highest high (bull leg) / lowest low (bear leg) so far
   int               m_pullbackCount;     // pullback bars seen since the last new extreme
   bool              m_havePrevPullback;  // is m_prevPullbackExtreme valid for the current sequence?
   double            m_prevPullbackExtreme; // previous pullback bar's counter-extreme (low in bull leg, high in bear leg)

   //--- Phase 3: does this trend bar also make a fresh N-bar extreme, -----
   //    closing strongly in its favor? That combination is Brooks' basic
   //    definition of a tradeable breakout bar.
   bool IsBreakoutBar(const SBarInfo &bar, const int index,
                       const double &high[], const double &low[], const int rates_total)
     {
      if(bar.barType != BAR_BULL_TREND && bar.barType != BAR_BEAR_TREND)
         return(false);

      bool bull = (bar.barType == BAR_BULL_TREND);
      if(bull && bar.clv < m_breakoutClvMin)
         return(false);
      if(!bull && bar.clv > -m_breakoutClvMin)
         return(false);

      int lookStart = index + 1;
      int lookEnd   = MathMin(rates_total - 1, index + m_breakoutLookback);
      if(lookStart > lookEnd)
         return(false);

      if(bull)
        {
         for(int i = lookStart; i <= lookEnd; i++)
            if(high[i] >= bar.high)
               return(false);
         return(true);
        }
      else
        {
         for(int i = lookStart; i <= lookEnd; i++)
            if(low[i] <= bar.low)
               return(false);
         return(true);
        }
     }

   //--- Phase 3: unusually large range + weak close = climax/exhaustion ---
   bool IsClimaxBar(const SBarInfo &bar, const int index,
                     const double &high[], const double &low[], const int rates_total)
     {
      double avgRange = CPabUtils::AverageRange(high, low, index + 1, m_climaxLookback);
      if(avgRange <= 0.0)
         return(false);
      bool bigRange = (bar.range >= m_climaxRangeMult * avgRange);
      bool weakClose = (bar.bodyRatio <= m_climaxBodyRatioMax);
      return(bigRange && weakClose);
     }

   //--- classify a single bar's TYPE (trend/doji/inside/outside) ----------
   ENUM_BAR_TYPE ClassifyType(const double o, const double h, const double l, const double c,
                               const double prevH, const double prevL, const bool havePrev)
     {
      if(havePrev && h <= prevH && l >= prevL)
         return(BAR_INSIDE);
      if(havePrev && h >= prevH && l <= prevL)
         return(BAR_OUTSIDE);

      double ratio = CPabUtils::BodyRatio(o, h, l, c);
      if(ratio < m_dojiBodyRatio)
         return(BAR_DOJI);

      return(c > o ? BAR_BULL_TREND : BAR_BEAR_TREND);
     }

   //--- score a pullback bar's signal quality (Phase 2) --------------------
   // bullLeg = true when scoring an H-pullback (bull leg), false for L-pullback (bear leg).
   ENUM_SIGNAL_QUALITY ScorePullback(const SBarInfo &bar, const bool bullLeg)
     {
      int score = 0;

      // Point 1: favorable close location. In a bull leg, an H-pullback bar
      // that still closes in the upper part of its range (positive CLV)
      // suggests buyers are already stepping back in; analogous for bear leg.
      bool favorableClose = bullLeg ? (bar.clv >= m_clvFavorableMin)
                                     : (bar.clv <= -m_clvFavorableMin);
      if(favorableClose)
         score++;

      // Point 2: shallower than the previous pullback bar in this sequence
      // (Brooks' "H2 should not make a much lower low than H1" quality cue).
      if(m_havePrevPullback)
        {
         bool shallower = bullLeg ? (bar.low > m_prevPullbackExtreme)
                                   : (bar.high < m_prevPullbackExtreme);
         if(shallower)
            score++;
        }

      if(score >= 2)
         return(QUALITY_STRONG);
      if(score == 1)
         return(QUALITY_MODERATE);
      return(QUALITY_WEAK);
     }

   //--- advance the pullback state machine with the newly classified bar ---
   void UpdatePullbackState(SBarInfo &bar)
     {
      if(!m_haveLeg)
        {
         if(bar.barType == BAR_BULL_TREND)
           {
            m_haveLeg = true; m_legIsBull = true;
            m_legExtreme = bar.high; m_pullbackCount = 0;
           }
         else if(bar.barType == BAR_BEAR_TREND)
           {
            m_haveLeg = true; m_legIsBull = false;
            m_legExtreme = bar.low; m_pullbackCount = 0;
           }
         bar.pullbackType = PB_NONE;
         bar.pullbackIndex = 0;
         bar.signalQuality = QUALITY_NA;
         m_havePrevPullback = false;
         return;
        }

      if(m_legIsBull)
        {
         if(bar.high > m_legExtreme)
           {
            m_legExtreme = bar.high;
            m_pullbackCount = 0;
            bar.pullbackType = PB_NONE;
            bar.pullbackIndex = 0;
            bar.signalQuality = QUALITY_NA;
            m_havePrevPullback = false;
           }
         else
           {
            m_pullbackCount++;
            bar.pullbackIndex = m_pullbackCount;
            bar.pullbackType = (m_pullbackCount == 1) ? PB_H1 :
                                (m_pullbackCount == 2) ? PB_H2 : PB_H3_PLUS;
            bar.signalQuality = ScorePullback(bar, true);
            m_prevPullbackExtreme = bar.low;
            m_havePrevPullback = true;
           }
        }
      else // bear leg
        {
         if(bar.low < m_legExtreme)
           {
            m_legExtreme = bar.low;
            m_pullbackCount = 0;
            bar.pullbackType = PB_NONE;
            bar.pullbackIndex = 0;
            bar.signalQuality = QUALITY_NA;
            m_havePrevPullback = false;
           }
         else
           {
            m_pullbackCount++;
            bar.pullbackIndex = m_pullbackCount;
            bar.pullbackType = (m_pullbackCount == 1) ? PB_L1 :
                                (m_pullbackCount == 2) ? PB_L2 : PB_L3_PLUS;
            bar.signalQuality = ScorePullback(bar, false);
            m_prevPullbackExtreme = bar.high;
            m_havePrevPullback = true;
           }
        }

      // Leg-flip: a fresh trend bar in the opposite direction that also
      // breaks the extreme starts a brand-new leg from scratch.
      if(m_legIsBull && bar.barType == BAR_BEAR_TREND && bar.low < m_legExtreme && m_pullbackCount >= 2)
        {
         m_legIsBull = false;
         m_legExtreme = bar.low;
         m_pullbackCount = 0;
         bar.pullbackType = PB_NONE;
         bar.pullbackIndex = 0;
         bar.signalQuality = QUALITY_NA;
         m_havePrevPullback = false;
        }
      else if(!m_legIsBull && bar.barType == BAR_BULL_TREND && bar.high > m_legExtreme && m_pullbackCount >= 2)
        {
         m_legIsBull = true;
         m_legExtreme = bar.high;
         m_pullbackCount = 0;
         bar.pullbackType = PB_NONE;
         bar.pullbackIndex = 0;
         bar.signalQuality = QUALITY_NA;
         m_havePrevPullback = false;
        }
     }

   //--- circular buffer push (O(1), no memmove) -----------------------------
   void PushFront(const SBarInfo &bar)
     {
      m_head = (m_head - 1 + m_capacity) % m_capacity;
      m_bars[m_head] = bar;
      if(m_size < m_capacity)
         m_size++;
     }

public:
                     CBarClassifier(const double dojiBodyRatio = 0.30, const int maxStored = 2000,
                                     const double clvFavorableMin = 0.15,
                                     const int breakoutLookback = 10, const double breakoutClvMin = 0.5,
                                     const int climaxLookback = 20, const double climaxRangeMult = 2.0,
                                     const double climaxBodyRatioMax = 0.35)
     {
      m_dojiBodyRatio   = dojiBodyRatio;
      m_capacity        = MathMax(10, maxStored);
      m_clvFavorableMin = clvFavorableMin;
      m_breakoutLookback   = MathMax(1, breakoutLookback);
      m_breakoutClvMin     = breakoutClvMin;
      m_climaxLookback     = MathMax(2, climaxLookback);
      m_climaxRangeMult    = climaxRangeMult;
      m_climaxBodyRatioMax = climaxBodyRatioMax;
      ArrayResize(m_bars, m_capacity);
      Reset();
     }

   void Reset() override
     {
      m_size = 0;
      m_head = 0;
      m_lastProcessedTime = 0;
      m_haveLeg = false;
      m_legIsBull = false;
      m_legExtreme = 0.0;
      m_pullbackCount = 0;
      m_havePrevPullback = false;
      m_prevPullbackExtreme = 0.0;
     }

   string Name() override { return("BarClassifier"); }

   // Classifies bar 'index' and pushes it into the circular history
   // buffer. Expects to be called oldest-to-newest exactly once per bar
   // (see the orchestrator loop in the main indicator file).
   void Update(const int index,
               const datetime &time[], const double &open[], const double &high[],
               const double &low[], const double &close[], const int rates_total) override
      {
       if(index < 0 || index >= rates_total || time[index] <= m_lastProcessedTime)
          return;
       m_lastProcessedTime = time[index];

       SBarInfo bar;
      bar.Clear();
      bar.time  = time[index];
      bar.open  = open[index];
      bar.high  = high[index];
      bar.low   = low[index];
      bar.close = close[index];
      bar.bodySize  = CPabUtils::BodySize(bar.open, bar.close);
      bar.range     = CPabUtils::BarRange(bar.high, bar.low);
      bar.bodyRatio = CPabUtils::BodyRatio(bar.open, bar.high, bar.low, bar.close);
      bar.clv       = CPabUtils::CloseLocationValue(bar.high, bar.low, bar.close);
      bar.isBullish = (bar.close > bar.open);

      bool havePrev = (index + 1 < rates_total);
      double prevH = havePrev ? high[index + 1] : 0.0;
      double prevL = havePrev ? low[index + 1]  : 0.0;
      bar.barType = ClassifyType(bar.open, bar.high, bar.low, bar.close, prevH, prevL, havePrev);

      bar.isBreakoutBar = IsBreakoutBar(bar, index, high, low, rates_total);
      bar.isClimax      = IsClimaxBar(bar, index, high, low, rates_total);

      UpdatePullbackState(bar);
      PushFront(bar);
     }

   //--- accessors -----------------------------------------------------------
   int      Count() const { return(m_size); }

   // i=0 is the most recently pushed bar, increasing i = older bars.
   bool     GetBar(const int i, SBarInfo &out) const
     {
      if(i < 0 || i >= m_size)
         return(false);
      int actual = (m_head + i) % m_capacity;
      out = m_bars[actual];
      return(true);
     }

   ENUM_MARKET_STATE CurrentLegDirection() const
     {
      if(!m_haveLeg)
         return(STATE_TRADING_RANGE);
      return(m_legIsBull ? STATE_BULL_TREND : STATE_BEAR_TREND);
     }
  };

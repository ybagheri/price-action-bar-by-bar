//+------------------------------------------------------------------+
//|                                              BarClassifier.mqh   |
//|                                                                    |
//| Classifies every bar per Al Brooks' bar-by-bar taxonomy:          |
//|   - Trend bar (bull/bear) vs Doji                                  |
//|   - Inside bar / Outside bar                                      |
//|   - Pullback sequence numbering (H1/H2/H3+, L1/L2/L3+)             |
//|                                                                    |
//| Single responsibility: this class ONLY classifies bars. It knows  |
//| nothing about swings, ranges, patterns or chart drawing — those   |
//| live in their own classes and consume SBarInfo[] as input.        |
//+------------------------------------------------------------------+
#property strict

#include "PAB_Types.mqh"
#include "PAB_IAnalyzer.mqh"
#include "PAB_Utils.mqh"

class CBarClassifier : public IAnalyzer
  {
private:
   double            m_dojiBodyRatio;     // body/range below this => Doji
   int               m_maxStored;         // ring-buffer size for m_bars
   SBarInfo          m_bars[];            // index 0 = most recent classified bar

   // Pullback-sequence state machine. A "leg" starts when a trend bar
   // makes a new local extreme in one direction; every bar afterward
   // that fails to extend that extreme is numbered as a pullback bar
   // (H1, H2, H3+ in a bull leg; L1, L2, L3+ in a bear leg) until a
   // new trend bar re-extends the extreme, which resets the count.
   bool              m_haveLeg;
   bool              m_legIsBull;         // true = tracking a bull leg (H-pullbacks)
   double            m_legExtreme;        // highest high (bull leg) / lowest low (bear leg) so far
   int               m_pullbackCount;     // pullback bars seen since the last new extreme

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

   //--- advance the pullback state machine with the newly classified bar ---
   void UpdatePullbackState(SBarInfo &bar)
     {
      if(!m_haveLeg)
        {
         // Bootstrap: the first trend bar we see starts a leg.
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
         return;
        }

      if(m_legIsBull)
        {
         if(bar.high > m_legExtreme)
           {
            // New high extends the bull leg — reset pullback counter.
            m_legExtreme = bar.high;
            m_pullbackCount = 0;
            bar.pullbackType = PB_NONE;
            bar.pullbackIndex = 0;
           }
         else
           {
            m_pullbackCount++;
            bar.pullbackIndex = m_pullbackCount;
            bar.pullbackType = (m_pullbackCount == 1) ? PB_H1 :
                                (m_pullbackCount == 2) ? PB_H2 : PB_H3_PLUS;

            // A strong bear trend bar while pulling back can flip the leg.
            if(bar.barType == BAR_BEAR_TREND && bar.low < m_legExtreme && m_pullbackCount >= 1)
              {
               // Leave the flip decision to the trend bar's own strength:
               // only flip once the bar breaks meaningfully below the
               // most recent pullback low sequence (kept simple/explicit).
              }
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
           }
         else
           {
            m_pullbackCount++;
            bar.pullbackIndex = m_pullbackCount;
            bar.pullbackType = (m_pullbackCount == 1) ? PB_L1 :
                                (m_pullbackCount == 2) ? PB_L2 : PB_L3_PLUS;
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
        }
      else if(!m_legIsBull && bar.barType == BAR_BULL_TREND && bar.high > m_legExtreme && m_pullbackCount >= 2)
        {
         m_legIsBull = true;
         m_legExtreme = bar.high;
         m_pullbackCount = 0;
         bar.pullbackType = PB_NONE;
         bar.pullbackIndex = 0;
        }
     }

public:
                     CBarClassifier(const double dojiBodyRatio = 0.30, const int maxStored = 2000)
     {
      m_dojiBodyRatio = dojiBodyRatio;
      m_maxStored     = maxStored;
      ArrayResize(m_bars, 0);
      Reset();
     }

   void Reset() override
     {
      ArrayFree(m_bars);
      ArrayResize(m_bars, 0);
      m_haveLeg = false;
      m_legIsBull = false;
      m_legExtreme = 0.0;
      m_pullbackCount = 0;
     }

   string Name() override { return("BarClassifier"); }

   // Classifies bar 'index' and pushes it to the front of the internal
   // history buffer. Expects to be called oldest-to-newest exactly once
   // per bar (see COrchestrator in the main indicator file).
   void Update(const int index,
               const datetime &time[], const double &open[], const double &high[],
               const double &low[], const double &close[], const int rates_total) override
     {
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
      bar.isBullish = (bar.close > bar.open);

      bool havePrev = (index + 1 < rates_total);
      double prevH = havePrev ? high[index + 1] : 0.0;
      double prevL = havePrev ? low[index + 1]  : 0.0;
      bar.barType = ClassifyType(bar.open, bar.high, bar.low, bar.close, prevH, prevL, havePrev);

      UpdatePullbackState(bar);

      // push_front into the ring buffer
      int n = ArraySize(m_bars);
      if(n >= m_maxStored)
        {
         for(int i = n - 1; i > 0; i--)
            m_bars[i] = m_bars[i - 1];
        }
      else
        {
         ArrayResize(m_bars, n + 1);
         for(int i = n; i > 0; i--)
            m_bars[i] = m_bars[i - 1];
        }
      m_bars[0] = bar;
     }

   //--- accessors -----------------------------------------------------------
   int      Count() const { return(ArraySize(m_bars)); }

   bool     GetBar(const int i, SBarInfo &out) const
     {
      if(i < 0 || i >= ArraySize(m_bars))
         return(false);
      out = m_bars[i];
      return(true);
     }

   ENUM_MARKET_STATE CurrentLegDirection() const
     {
      if(!m_haveLeg)
         return(STATE_TRADING_RANGE);
      return(m_legIsBull ? STATE_BULL_TREND : STATE_BEAR_TREND);
     }
  };

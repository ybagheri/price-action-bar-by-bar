//+------------------------------------------------------------------+
//|                                       TradingRangeDetector.mqh   |
//|                                                                    |
//| Classifies the recent market as STATE_TRADING_RANGE,               |
//| STATE_BULL_TREND, STATE_BEAR_TREND or STATE_TRANSITION.            |
//|                                                                    |
//| Brooks treats this as a judgment call; here we approximate it     |
//| with two objective, tunable proxies over a lookback window:       |
//|   1) Overlap ratio between consecutive bars (high overlap =       |
//|      choppy / ranging).                                            |
//|   2) Net directional displacement normalized by the average bar   |
//|      range (large displacement = trending).                      |
//| This keeps the detector auditable and replaceable — swap the      |
//| scoring function without touching any other module.               |
//+------------------------------------------------------------------+
#property strict

#include "PAB_Types.mqh"
#include "PAB_IAnalyzer.mqh"
#include "PAB_Utils.mqh"

class CTradingRangeDetector : public IAnalyzer
  {
private:
   int                m_lookback;          // bars used to score the current regime
   double             m_overlapThreshold;  // avg overlap above this => ranging
   double             m_displaceThreshold; // |net move| / avgRange above this => trending
   ENUM_MARKET_STATE  m_state;
   STradingRangeInfo  m_currentRange;

public:
                     CTradingRangeDetector(const int lookback = 20,
                                            const double overlapThreshold = 0.55,
                                            const double displaceThreshold = 3.0)
     {
      m_lookback = MathMax(5, lookback);
      m_overlapThreshold = overlapThreshold;
      m_displaceThreshold = displaceThreshold;
      Reset();
     }

   void Reset() override
     {
      m_state = STATE_TRADING_RANGE;
      m_currentRange.active = false;
      m_currentRange.top = m_currentRange.bottom = 0.0;
      m_currentRange.startBarIndex = m_currentRange.endBarIndex = 0;
      m_currentRange.overlapRatio = 0.0;
     }

   string Name() override { return("TradingRangeDetector"); }

   // Re-scores the regime using the m_lookback bars ending at 'index'.
   // Cheap enough to run every bar; only needs raw OHLC.
   void Update(const int index,
               const datetime &time[], const double &open[], const double &high[],
               const double &low[], const double &close[], const int rates_total) override
     {
      int last = index + m_lookback - 1;
      if(last >= rates_total)
         return; // not enough history yet

      // --- overlap score: average consecutive-bar range overlap ---------
      double overlapSum = 0.0;
      int    overlapN   = 0;
      for(int i = index; i < last; i++)
        {
         overlapSum += CPabUtils::RangeOverlap(high[i], low[i], high[i + 1], low[i + 1]);
         overlapN++;
        }
      double avgOverlap = (overlapN > 0) ? overlapSum / overlapN : 0.0;

      // --- displacement score: net move / average bar range -------------
      double avgRange = CPabUtils::AverageRange(high, low, index, m_lookback);
      double netMove  = close[index] - close[last];
      double displacement = (avgRange > 0.0) ? MathAbs(netMove) / avgRange : 0.0;

      // --- window extremes, used to describe the range box --------------
      double windowHigh = high[index], windowLow = low[index];
      for(int i = index; i <= last; i++)
        {
         if(high[i] > windowHigh) windowHigh = high[i];
         if(low[i]  < windowLow)  windowLow  = low[i];
        }

      ENUM_MARKET_STATE prevState = m_state;

      if(displacement >= m_displaceThreshold && avgOverlap < m_overlapThreshold)
        {
         m_state = (netMove > 0) ? STATE_BULL_TREND : STATE_BEAR_TREND;
         m_currentRange.active = false;
        }
      else if(avgOverlap >= m_overlapThreshold)
        {
         m_state = STATE_TRADING_RANGE;
         m_currentRange.active = true;
         m_currentRange.top = windowHigh;
         m_currentRange.bottom = windowLow;
         m_currentRange.startBarIndex = last;
         m_currentRange.endBarIndex = index;
         m_currentRange.overlapRatio = avgOverlap;
        }
      else
        {
         m_state = STATE_TRANSITION;
        }
     }

   //--- accessors -----------------------------------------------------------
   ENUM_MARKET_STATE State() const { return(m_state); }
   bool GetRange(STradingRangeInfo &out) const
     {
      out = m_currentRange;
      return(m_currentRange.active);
     }
  };

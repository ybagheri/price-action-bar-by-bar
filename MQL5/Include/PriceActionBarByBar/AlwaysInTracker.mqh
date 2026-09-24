//+------------------------------------------------------------------+
//|                                           AlwaysInTracker.mqh    |
//|                                                                    |
//| Tracks Brooks' "always-in" concept: which side you'd be on if you |
//| had to have a position right now. Unlike CTradingRangeDetector's  |
//| ENUM_MARKET_STATE (a rolling re-score that can flip back and      |
//| forth every bar), always-in is STICKY — it only changes when      |
//| price CLOSES beyond the most recent confirmed swing extreme in    |
//| the opposite direction, and holds that stance until the next      |
//| such break. This is the closest objective proxy to "which way     |
//| is the market really leaning" without requiring full discretionary|
//| judgment.                                                          |
//|                                                                    |
//| DESIGN NOTE: like CPatternDetector, this is inherently a function |
//| of SWINGS, not raw bars — IAnalyzer.Update() is a no-op here and  |
//| the real entry point is Evaluate(), called once per bar by the    |
//| orchestrator AFTER CSwingDetector has been updated.                |
//+------------------------------------------------------------------+
#property strict

#include "PAB_Types.mqh"

class CAlwaysInTracker
  {
private:
   ENUM_ALWAYS_IN_STATE m_state;
   double               m_referenceExtreme;  // swing extreme that would flip the current state if closed beyond
   datetime              m_lastFlipTime;
   bool                  m_haveFlip;

public:
                     CAlwaysInTracker()
     {
      Reset();
     }

   void Reset()
     {
      m_state = ALWAYS_IN_NONE;
      m_referenceExtreme = 0.0;
      m_lastFlipTime = 0;
      m_haveFlip = false;
     }

   // Called once per bar (on the newest/current bar) by the orchestrator,
   // after CSwingDetector has produced its latest swing list.
   //   closePrice          : close of the current bar
   //   haveSwingHigh/Low    : whether a confirmed swing of that type exists
   //   swingHighPrice/LowPrice : that swing's price
   //   barTime              : time of the current bar, recorded on a flip
   void Evaluate(const double closePrice,
                  const bool haveSwingHigh, const double swingHighPrice,
                  const bool haveSwingLow, const double swingLowPrice,
                  const datetime barTime)
     {
      if(m_state == ALWAYS_IN_NONE)
        {
         // Bootstrap: pick a side as soon as we have at least one swing to
         // measure against, using close vs. the nearer available swing.
         if(haveSwingHigh && closePrice > swingHighPrice)
           {
            m_state = ALWAYS_IN_LONG;
            m_referenceExtreme = swingLowPrice; // will need a swing low to flip back down
           }
         else if(haveSwingLow && closePrice < swingLowPrice)
           {
            m_state = ALWAYS_IN_SHORT;
            m_referenceExtreme = swingHighPrice;
           }
         return;
        }

      if(m_state == ALWAYS_IN_LONG && haveSwingLow && closePrice < swingLowPrice)
        {
         m_state = ALWAYS_IN_SHORT;
         m_referenceExtreme = swingHighPrice;
         m_lastFlipTime = barTime;
         m_haveFlip = true;
        }
      else if(m_state == ALWAYS_IN_SHORT && haveSwingHigh && closePrice > swingHighPrice)
        {
         m_state = ALWAYS_IN_LONG;
         m_referenceExtreme = swingLowPrice;
         m_lastFlipTime = barTime;
         m_haveFlip = true;
        }
     }

   //--- accessors -----------------------------------------------------------
   ENUM_ALWAYS_IN_STATE State() const { return(m_state); }
   bool LastFlipTime(datetime &out) const
     {
      if(!m_haveFlip)
         return(false);
      out = m_lastFlipTime;
      return(true);
     }
  };

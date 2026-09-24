//+------------------------------------------------------------------+
//|                                     MeasuredMoveDetector.mqh     |
//|                                                                    |
//| Minimal measured-move projection from the three most recent       |
//| confirmed swings: leg1 = swing(n-2) -> swing(n-1) (the completed  |
//| impulse), then an equal-size leg2 is projected from swing(n)      |
//| (the latest pullback swing, in the leg1 direction).                |
//|                                                                    |
//| SCOPE NOTE: this is intentionally minimal. `ybagheri/FM-indicator`|
//| already has a mature, multi-state Measured Move engine (lifecycle |
//| states, session modes, historical MAE/MFE export, etc.) — this    |
//| class is NOT meant to replace or duplicate that. It exists so     |
//| PriceActionBarByBar has a self-contained, swing-driven target     |
//| reference while standing alone. Phase 5 in ROADMAP.md covers      |
//| wiring this project's context (always-in, patterns) INTO the      |
//| real FM-indicator engine instead of growing this one further.     |
//|                                                                    |
//| DESIGN NOTE: like CPatternDetector, this depends on swings, not   |
//| raw bars — IAnalyzer.Update() is a no-op; AnalyzeSwings() is the  |
//| real entry point, called by the orchestrator after CSwingDetector.|
//+------------------------------------------------------------------+
#property strict

#include "PAB_Types.mqh"
#include "PAB_IAnalyzer.mqh"

class CMeasuredMoveDetector : public IAnalyzer
  {
private:
   SMeasuredMoveInfo m_current;

public:
                     CMeasuredMoveDetector()
     {
      Reset();
     }

   void Reset() override
     {
      m_current.active = false;
      m_current.isBullish = false;
      m_current.leg1Start = m_current.leg1End = 0.0;
      m_current.pivotPrice = m_current.targetPrice = 0.0;
      m_current.pivotTime = 0;
     }

   string Name() override { return("MeasuredMoveDetector"); }

   // No-op by design — see class header.
   void Update(const int index,
               const datetime &time[], const double &open[], const double &high[],
               const double &low[], const double &close[], const int rates_total) override
     {
      // no-op by design
     }

   // swings[0] = newest. Needs at least 3 swings, alternating in type
   // (high/low/high or low/high/low), to form leg1 + a pivot to project from.
   bool AnalyzeSwings(const SSwingPoint &swings[], const int count)
     {
      if(count < 3)
        {
         m_current.active = false;
         return(false);
        }

      SSwingPoint pivot = swings[0];   // swing(n): most recent pullback, projection origin
      SSwingPoint legEnd = swings[1];  // swing(n-1): end of the completed impulse leg
      SSwingPoint legStart = swings[2]; // swing(n-2): start of the completed impulse leg

      // Require a valid alternating sequence: legStart and pivot must be
      // the SAME type (both highs or both lows), legEnd the opposite —
      // i.e. a clean swing-low -> swing-high -> swing-low (or reverse) shape.
      if(legStart.type != pivot.type || legEnd.type == pivot.type)
        {
         m_current.active = false;
         return(false);
        }

      double legSize = MathAbs(legEnd.price - legStart.price);
      if(legSize <= 0.0)
        {
         m_current.active = false;
         return(false);
        }

      bool bullish = (legEnd.price > legStart.price); // leg1 moved up => project leg2 up from the pivot low
      m_current.active = true;
      m_current.isBullish = bullish;
      m_current.leg1Start = legStart.price;
      m_current.leg1End   = legEnd.price;
      m_current.pivotPrice = pivot.price;
      m_current.pivotTime = pivot.time;
      m_current.targetPrice = bullish ? (pivot.price + legSize) : (pivot.price - legSize);
      return(true);
     }

   SMeasuredMoveInfo Current() const { return(m_current); }
  };

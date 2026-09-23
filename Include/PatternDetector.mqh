//+------------------------------------------------------------------+
//|                                             PatternDetector.mqh  |
//|                                                                    |
//| Detects simple, objective multi-swing patterns:                   |
//|   - Higher-Highs/Higher-Lows or Lower-Highs/Lower-Lows structure   |
//|   - Double Top / Double Bottom                                    |
//|   - Triangle (converging highs & lows)                            |
//|   - 3-push Wedge (rising = bearish, falling = bullish per Brooks) |
//|                                                                    |
//| DESIGN NOTE: unlike the other analyzers, pattern recognition is   |
//| inherently a function of SWINGS, not raw bars. Rather than force  |
//| a bar-indexed Update() to do this work, IAnalyzer.Update() is a   |
//| deliberate no-op here and the real entry point is AnalyzeSwings(),|
//| called by the orchestrator once per bar AFTER CSwingDetector has  |
//| been updated. This keeps the dependency direction explicit        |
//| (PatternDetector depends on SwingDetector's output type only,     |
//| not on the class itself) and is documented in README.md.          |
//+------------------------------------------------------------------+
#property strict

#include "PAB_Types.mqh"
#include "PAB_IAnalyzer.mqh"
#include "PAB_Utils.mqh"

class CPatternDetector : public IAnalyzer
  {
private:
   double            m_similarityPct;   // e.g. 0.001 = 0.1% price tolerance for "equal" swings
   double            m_convergenceMin;  // minimum slope convergence (fraction) to call a triangle/wedge
   SPatternInfo      m_lastPattern;

   bool NearlyEqual(const double a, const double b) const
     {
      double avg = (MathAbs(a) + MathAbs(b)) / 2.0;
      if(avg <= 0.0)
         return(a == b);
      return(MathAbs(a - b) / avg <= m_similarityPct);
     }

public:
                     CPatternDetector(const double similarityPct = 0.0015,
                                       const double convergenceMin = 0.15)
     {
      m_similarityPct = similarityPct;
      m_convergenceMin = convergenceMin;
      Reset();
     }

   void Reset() override
     {
      m_lastPattern.type = PATTERN_NONE;
      m_lastPattern.startBarIndex = m_lastPattern.endBarIndex = 0;
      m_lastPattern.note = "";
     }

   string Name() override { return("PatternDetector"); }

   // Intentional no-op — see class header. Present only to satisfy
   // IAnalyzer so the orchestrator can still hold this in a generic
   // IAnalyzer[] array alongside the bar-driven analyzers if desired.
   void Update(const int index,
               const datetime &time[], const double &open[], const double &high[],
               const double &low[], const double &close[], const int rates_total) override
     {
      // no-op by design
     }

   // Real entry point: pass the most recent swings (index 0 = newest),
   // highs/lows/timestamps arrays for slope calculations. Needs at least
   // 4 swings (2 highs + 2 lows) to say anything meaningful.
   bool AnalyzeSwings(const SSwingPoint &swings[], const int count)
     {
      // collect the most recent 3 highs and 3 lows, newest first
      SSwingPoint highs[3], lows[3];
      int nH = 0, nL = 0;
      for(int i = 0; i < count && (nH < 3 || nL < 3); i++)
        {
         if(swings[i].type == SWING_HIGH && nH < 3) highs[nH++] = swings[i];
         if(swings[i].type == SWING_LOW  && nL < 3) lows[nL++]  = swings[i];
        }

      if(nH < 2 || nL < 2)
        {
         m_lastPattern.type = PATTERN_NONE;
         return(false);
        }

      // --- Double Top / Double Bottom (2 most recent same-type swings) ---
      if(nH >= 2 && NearlyEqual(highs[0].price, highs[1].price))
        {
         m_lastPattern.type = PATTERN_DOUBLE_TOP;
         m_lastPattern.startBarIndex = highs[1].barIndex;
         m_lastPattern.endBarIndex   = highs[0].barIndex;
         m_lastPattern.note = "Double Top ~" + DoubleToString(highs[0].price, _Digits);
         return(true);
        }
      if(nL >= 2 && NearlyEqual(lows[0].price, lows[1].price))
        {
         m_lastPattern.type = PATTERN_DOUBLE_BOTTOM;
         m_lastPattern.startBarIndex = lows[1].barIndex;
         m_lastPattern.endBarIndex   = lows[0].barIndex;
         m_lastPattern.note = "Double Bottom ~" + DoubleToString(lows[0].price, _Digits);
         return(true);
        }

      // --- Trend structure: HH+HL vs LH+LL (needs 2 highs + 2 lows) ------
      if(nH >= 2 && nL >= 2)
        {
         bool higherHighs = highs[0].price > highs[1].price;
         bool higherLows  = lows[0].price  > lows[1].price;
         bool lowerHighs  = highs[0].price < highs[1].price;
         bool lowerLows   = lows[0].price  < lows[1].price;

         if(higherHighs && higherLows)
           {
            m_lastPattern.type = PATTERN_HIGHER_HIGHS_LOWS;
            m_lastPattern.startBarIndex = MathMax(highs[1].barIndex, lows[1].barIndex);
            m_lastPattern.endBarIndex   = MathMin(highs[0].barIndex, lows[0].barIndex);
            m_lastPattern.note = "Higher-High / Higher-Low structure (bull)";
            return(true);
           }
         if(lowerHighs && lowerLows)
           {
            m_lastPattern.type = PATTERN_LOWER_HIGHS_LOWS;
            m_lastPattern.startBarIndex = MathMax(highs[1].barIndex, lows[1].barIndex);
            m_lastPattern.endBarIndex   = MathMin(highs[0].barIndex, lows[0].barIndex);
            m_lastPattern.note = "Lower-High / Lower-Low structure (bear)";
            return(true);
           }

         // --- Triangle: highs slope down AND lows slope up (converging) --
         double highSlope = CPabUtils::Slope(highs[1].barIndex, highs[1].price, highs[0].barIndex, highs[0].price);
         double lowSlope  = CPabUtils::Slope(lows[1].barIndex,  lows[1].price,  lows[0].barIndex,  lows[0].price);
         if(highSlope < -m_convergenceMin && lowSlope > m_convergenceMin)
           {
            m_lastPattern.type = PATTERN_TRIANGLE;
            m_lastPattern.startBarIndex = MathMax(highs[1].barIndex, lows[1].barIndex);
            m_lastPattern.endBarIndex   = MathMin(highs[0].barIndex, lows[0].barIndex);
            m_lastPattern.note = "Converging triangle";
            return(true);
           }

         // --- 3-push Wedge: needs 3 highs + 3 lows, both slopes same sign -
         if(nH >= 3 && nL >= 3)
           {
            bool risingHighs = highs[0].price > highs[1].price && highs[1].price > highs[2].price;
            bool risingLows  = lows[0].price  > lows[1].price  && lows[1].price  > lows[2].price;
            bool fallingHighs = highs[0].price < highs[1].price && highs[1].price < highs[2].price;
            bool fallingLows  = lows[0].price  < lows[1].price  && lows[1].price  < lows[2].price;

            if(risingHighs && risingLows)
              {
               m_lastPattern.type = PATTERN_WEDGE_RISING;
               m_lastPattern.startBarIndex = MathMax(highs[2].barIndex, lows[2].barIndex);
               m_lastPattern.endBarIndex   = MathMin(highs[0].barIndex, lows[0].barIndex);
               m_lastPattern.note = "3-push rising wedge (bearish per Brooks)";
               return(true);
              }
            if(fallingHighs && fallingLows)
              {
               m_lastPattern.type = PATTERN_WEDGE_FALLING;
               m_lastPattern.startBarIndex = MathMax(highs[2].barIndex, lows[2].barIndex);
               m_lastPattern.endBarIndex   = MathMin(highs[0].barIndex, lows[0].barIndex);
               m_lastPattern.note = "3-push falling wedge (bullish per Brooks)";
               return(true);
              }
           }
        }

      m_lastPattern.type = PATTERN_NONE;
      return(false);
     }

   SPatternInfo LastPattern() const { return(m_lastPattern); }
  };

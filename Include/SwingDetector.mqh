//+------------------------------------------------------------------+
//|                                              SwingDetector.mqh   |
//|                                                                    |
//| Detects swing highs/lows using an N-bar fractal rule: a bar is a  |
//| swing high if its high is the highest within a symmetric window   |
//| of N bars on each side (and analogously for swing lows).          |
//|                                                                    |
//| Depends only on raw price arrays — deliberately decoupled from    |
//| CBarClassifier so it can be reused/tested independently, or swapped|
//| for a different swing algorithm later without touching other      |
//| modules (Liskov-substitutable via IAnalyzer).                     |
//+------------------------------------------------------------------+
#property strict

#include "PAB_Types.mqh"
#include "PAB_IAnalyzer.mqh"

class CSwingDetector : public IAnalyzer
  {
private:
   int               m_fractalLegs;   // bars required on each side (e.g. 2 = 5-bar fractal)
   int               m_maxStored;
   SSwingPoint       m_swings[];      // index 0 = most recent confirmed swing

   void PushSwing(const SSwingPoint &sp)
     {
      int n = ArraySize(m_swings);
      if(n >= m_maxStored)
        {
         for(int i = n - 1; i > 0; i--)
            m_swings[i] = m_swings[i - 1];
        }
      else
        {
         ArrayResize(m_swings, n + 1);
         for(int i = n; i > 0; i--)
            m_swings[i] = m_swings[i - 1];
        }
      m_swings[0] = sp;
     }

public:
                     CSwingDetector(const int fractalLegs = 2, const int maxStored = 500)
     {
      m_fractalLegs = MathMax(1, fractalLegs);
      m_maxStored   = maxStored;
      Reset();
     }

   void Reset() override
     {
      ArrayFree(m_swings);
      ArrayResize(m_swings, 0);
     }

   string Name() override { return("SwingDetector"); }

   // A fractal centered at index 'c' can only be confirmed once
   // m_fractalLegs newer bars exist, i.e. once c - m_fractalLegs >= 0
   // in series indexing. We therefore evaluate the candidate bar at
   // (index + m_fractalLegs), not 'index' itself.
   void Update(const int index,
               const datetime &time[], const double &open[], const double &high[],
               const double &low[], const double &close[], const int rates_total) override
     {
      int c = index + m_fractalLegs;   // candidate center bar
      if(c + m_fractalLegs >= rates_total)
         return; // not enough older bars yet to confirm

      bool isHigh = true, isLow = true;
      for(int k = 1; k <= m_fractalLegs; k++)
        {
         if(high[c - k] >= high[c] || high[c + k] >= high[c]) isHigh = false;
         if(low[c - k]  <= low[c]  || low[c + k]  <= low[c])  isLow  = false;
         if(!isHigh && !isLow)
            break;
        }

      if(isHigh)
        {
         SSwingPoint sp;
         sp.barIndex = c; sp.time = time[c]; sp.price = high[c]; sp.type = SWING_HIGH;
         PushSwing(sp);
        }
      if(isLow)
        {
         SSwingPoint sp;
         sp.barIndex = c; sp.time = time[c]; sp.price = low[c]; sp.type = SWING_LOW;
         PushSwing(sp);
        }
     }

   //--- accessors -----------------------------------------------------------
   int  Count() const { return(ArraySize(m_swings)); }

   bool GetSwing(const int i, SSwingPoint &out) const
     {
      if(i < 0 || i >= ArraySize(m_swings))
         return(false);
      out = m_swings[i];
      return(true);
     }

   // Most recent swing of a given type, if any.
   bool LatestOfType(const ENUM_SWING_TYPE t, SSwingPoint &out) const
     {
      for(int i = 0; i < ArraySize(m_swings); i++)
        {
         if(m_swings[i].type == t)
           {
            out = m_swings[i];
            return(true);
           }
        }
      return(false);
     }
  };

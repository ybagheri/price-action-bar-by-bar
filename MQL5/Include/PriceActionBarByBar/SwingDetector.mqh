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
//|                                                                    |
//| Storage: fixed-capacity CIRCULAR buffer (head/size, no memmove),  |
//| matching CBarClassifier's Phase 2 optimization.                   |
//+------------------------------------------------------------------+
#property strict

#include "PAB_Types.mqh"
#include "PAB_IAnalyzer.mqh"

class CSwingDetector : public IAnalyzer
  {
private:
   int               m_fractalLegs;   // bars required on each side (e.g. 2 = 5-bar fractal)

   int               m_capacity;
   int               m_size;
   int               m_head;          // index of the most recent swing (logical position 0)
   datetime          m_lastProcessedTime;
   SSwingPoint       m_swings[];

   void PushSwing(const SSwingPoint &sp)
     {
      m_head = (m_head - 1 + m_capacity) % m_capacity;
      m_swings[m_head] = sp;
      if(m_size < m_capacity)
         m_size++;
     }

public:
                     CSwingDetector(const int fractalLegs = 2, const int maxStored = 500)
     {
      m_fractalLegs = MathMax(1, fractalLegs);
      m_capacity    = MathMax(10, maxStored);
      ArrayResize(m_swings, m_capacity);
      Reset();
     }

   void Reset() override
     {
      m_size = 0;
      m_head = 0;
      m_lastProcessedTime = 0;
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
       if(index < 0 || index >= rates_total || time[index] <= m_lastProcessedTime)
          return;
       m_lastProcessedTime = time[index];

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
   int  Count() const { return(m_size); }

   bool GetSwing(const int i, SSwingPoint &out) const
     {
      if(i < 0 || i >= m_size)
         return(false);
      int actual = (m_head + i) % m_capacity;
      out = m_swings[actual];
      return(true);
     }

   // Most recent swing of a given type, if any.
   bool LatestOfType(const ENUM_SWING_TYPE t, SSwingPoint &out) const
     {
      for(int i = 0; i < m_size; i++)
        {
         SSwingPoint sp;
         GetSwing(i, sp);
         if(sp.type == t)
           {
            out = sp;
            return(true);
           }
        }
      return(false);
     }
  };

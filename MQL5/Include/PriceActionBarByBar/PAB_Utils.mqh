//+------------------------------------------------------------------+
//|                                                   PAB_Utils.mqh  |
//|                                                                    |
//| Small, stateless helper functions. Kept free of any class state  |
//| so they can be unit-exercised in isolation and reused anywhere.  |
//+------------------------------------------------------------------+
#property strict

class CPabUtils
  {
public:
   //--- basic bar geometry -------------------------------------------------
   static double BodySize(const double o, const double c)
     {
      return(MathAbs(c - o));
     }

   static double BarRange(const double h, const double l)
     {
      return(h - l);
     }

   static double BodyRatio(const double o, const double h, const double l, const double c)
     {
      double range = BarRange(h, l);
      if(range <= 0.0)
         return(0.0);
      return(BodySize(o, c) / range);
     }

   // Close Location Value: where the close sits within the bar's range.
   // +1.0 = close at the high (maximally bullish close), -1.0 = close at
   // the low (maximally bearish close), 0.0 = close at the midpoint.
   static double CloseLocationValue(const double h, const double l, const double c)
     {
      double range = BarRange(h, l);
      if(range <= 0.0)
         return(0.0);
      return(((c - l) - (h - c)) / range);
     }

   //--- overlap between two ranges, used by the trading-range detector -----
   // Returns 0..1: fraction of the smaller range's extent covered by the
   // intersection with the other range. 1.0 = fully overlapping.
   static double RangeOverlap(const double h1, const double l1,
                               const double h2, const double l2)
     {
      double overlapHigh = MathMin(h1, h2);
      double overlapLow  = MathMax(l1, l2);
      double overlap     = overlapHigh - overlapLow;
      if(overlap <= 0.0)
         return(0.0);
      double smaller = MathMin(h1 - l1, h2 - l2);
      if(smaller <= 0.0)
         return(0.0);
      return(overlap / smaller);
     }

   //--- simple ATR-style average range, used to normalize thresholds -------
   static double AverageRange(const double &high[], const double &low[],
                               const int fromIndex, const int period)
     {
      if(period <= 0)
         return(0.0);
      double sum = 0.0;
      int    n   = 0;
      for(int i = fromIndex; i < fromIndex + period; i++)
        {
         if(i < 0 || i >= ArraySize(high))
            break;
         sum += (high[i] - low[i]);
         n++;
        }
      if(n == 0)
         return(0.0);
      return(sum / n);
     }

   //--- slope of a price series, normalized so thresholds can be shared -----
   // The x-axis is BAR TIMESTAMP, never a series index. A series index
   // shifts every time a new bar arrives and restarts on a history reload,
   // so two swings confirmed at different moments would produce different
   // slopes for the same geometry. Timestamps are stable.
   //
   // The y-axis is divided by the reference price, so the result is a
   // dimensionless "fraction of price per bar". That is what makes one
   // threshold meaningful on EURUSD at 1.10 and on gold at 3400, and on M5
   // as well as H1. A raw price-per-bar slope is not: the old
   // price-per-index slope produced ~0.0025 on a 1.10 instrument, so a
   // 0.15 threshold could never be met and triangles never fired at all.
   //
   // Sign convention: positive means the series rose as time advanced, i.e.
   // toward the newer point. t1/y1 is the OLDER point, t2/y2 the NEWER one.
   // Returns 0.0 when the two points cannot be separated on the time axis or
   // the reference price is not positive, because "no measurable slope" must
   // never satisfy a convergence threshold.
   static double NormalizedSlopePerBar(const datetime t1, const double y1,
                                       const datetime t2, const double y2,
                                       const int secondsPerBar)
     {
      if(secondsPerBar <= 0)
         return(0.0);
      double span = (double)(t2 - t1);
      if(span <= 0.0)
         return(0.0);
      double barsApart = span / (double)secondsPerBar;
      if(barsApart < 1.0)
         return(0.0);
      if(y1 <= 0.0)
         return(0.0);
      return((y2 - y1) / y1) / barsApart;
     }
  };

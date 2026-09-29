#property strict

#include "PAB_Types.mqh"
#include "PAB_Utils.mqh"

class CContextAnalyzer
  {
private:
   void FindLevels(const SBarInfo &bar, const double averageRange,
                   const SSwingPoint &swings[], const int swingCount,
                   double &support, double &resistance,
                   bool &nearSupport, bool &nearResistance) const
     {
      support = 0.0;
      resistance = 0.0;
      nearSupport = false;
      nearResistance = false;

      for(int i = 0; i < swingCount; i++)
        {
         if(swings[i].type == SWING_LOW && swings[i].price <= bar.low)
           {
            if(support == 0.0 || swings[i].price > support)
               support = swings[i].price;
           }
         if(swings[i].type == SWING_HIGH && swings[i].price >= bar.high)
           {
            if(resistance == 0.0 || swings[i].price < resistance)
               resistance = swings[i].price;
           }
        }

      nearSupport = support > 0.0 && bar.low - support <= averageRange * 0.75;
      nearResistance = resistance > 0.0 && resistance - bar.high <= averageRange * 0.75;
     }

public:
   void Analyze(const SBarInfo &bars[], const int count,
                const SSwingPoint &swings[], const int swingCount,
                const ENUM_MARKET_STATE mediumState,
                const ENUM_ALWAYS_IN_STATE alwaysIn,
                SContextInfo &out) const
     {
      out.valid = false;
      out.microState = STATE_TRANSITION;
      out.mediumState = mediumState;
      out.overlap = 0.0;
      out.displacement = 0.0;
      out.bullPressure = 0.0;
      out.bearPressure = 0.0;
      out.failedBullBreakout = false;
      out.failedBearBreakout = false;
      out.nearSupport = false;
      out.nearResistance = false;
      out.support = 0.0;
      out.resistance = 0.0;
      out.averageRange = 0.0;

      int n = MathMin(count, 10);
      if(n < 3)
         return;

      double rangeSum = 0.0;
      double overlapSum = 0.0;
      for(int i = 0; i < n; i++)
        {
         rangeSum += bars[i].range;
         out.bullPressure += bars[i].isBullish ? bars[i].bodyRatio : 0.0;
         out.bearPressure += bars[i].isBullish ? 0.0 : bars[i].bodyRatio;
         if(i + 1 < n)
            overlapSum += bars[i].overlapPrev;
        }

      out.averageRange = rangeSum / n;
      out.overlap = overlapSum / MathMax(1, n - 1);
      double totalPressure = out.bullPressure + out.bearPressure;
      if(totalPressure > 0.0)
        {
         out.bullPressure /= totalPressure;
         out.bearPressure /= totalPressure;
        }

      double netMove = bars[0].close - bars[n - 1].close;
      out.displacement = out.averageRange > 0.0 ? netMove / out.averageRange : 0.0;
      if(out.displacement >= 0.75 && out.overlap < 0.60)
         out.microState = netMove > 0.0 ? STATE_BULL_TREND : STATE_BEAR_TREND;
      else if(out.overlap >= 0.70)
         out.microState = STATE_TRADING_RANGE;
      else
         out.microState = STATE_TRANSITION;

      SSwingPoint highSwing, lowSwing;
      ZeroMemory(highSwing);
      ZeroMemory(lowSwing);
      bool haveHigh = false;
      bool haveLow = false;
      for(int i = 0; i < swingCount; i++)
        {
         if(!haveHigh && swings[i].type == SWING_HIGH) { highSwing = swings[i]; haveHigh = true; }
         if(!haveLow && swings[i].type == SWING_LOW) { lowSwing = swings[i]; haveLow = true; }
         if(haveHigh && haveLow)
            break;
        }

      SBarInfo current = bars[0];

      // A FAILED breakout needs evidence that a breakout actually happened.
      // The previous test only asked whether the current bar was below the
      // swing high, which is true for almost every bar that has not broken
      // out, so it labelled ordinary bullish bars under resistance as failed
      // breakouts. A real historical export showed 53,329 of 72,188 events
      // classified as SETUP_FAILED_BREAKOUT, 74 percent of the sample, which
      // made every aggregate figure a restatement of one over-triggered
      // heuristic.
      //
      // So the window extremes are checked as well: the recent bars must
      // have traded beyond the level, and only then may the current bar's
      // close back inside it count as the failure. The current bar is
      // included in the extremes, which is what lets a single-bar poke and
      // rejection register.
      double windowHigh = current.high;
      double windowLow  = current.low;
      for(int i = 1; i < n; i++)
        {
         if(bars[i].high > windowHigh) windowHigh = bars[i].high;
         if(bars[i].low  < windowLow)  windowLow  = bars[i].low;
        }

      out.failedBullBreakout = haveHigh && windowHigh > highSwing.price &&
                               current.close < highSwing.price && current.isBullish;
      out.failedBearBreakout = haveLow && windowLow < lowSwing.price &&
                               current.close > lowSwing.price && !current.isBullish;
      FindLevels(current, out.averageRange, swings, swingCount,
                 out.support, out.resistance, out.nearSupport, out.nearResistance);

      if(alwaysIn == ALWAYS_IN_LONG && out.bearPressure > 0.65)
         out.microState = STATE_TRANSITION;
      if(alwaysIn == ALWAYS_IN_SHORT && out.bullPressure > 0.65)
         out.microState = STATE_TRANSITION;
      out.valid = true;
     }
  };

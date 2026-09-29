#property strict

#include "PAB_Types.mqh"

class CDecisionEngine
  {
private:
   int m_minimumQuality;
   double m_minimumRiskReward;

   // The single exit point for a NO TRADE verdict.
   //
   // A NO TRADE row means "the engine saw something and declined to act",
   // so it must NOT carry a direction or price levels. Both the export
   // schema and pab_research.SetupEvent require status=no_trade to imply
   // direction=none: a row with status=no_trade and direction=long is
   // rejected by the research layer, and a stale entry/target on a
   // declined row invites a reader to treat it as a real proposal. Every
   // early return goes through here so the two can never disagree.
   void NoTrade(SSetupCandidate &candidate, const string reason) const
     {
      candidate.status    = STATUS_NO_TRADE;
      candidate.direction = SETUP_NONE;
      candidate.type      = SETUP_NO_TRADE;
      candidate.entryPrice  = 0.0;
      candidate.stopPrice   = 0.0;
      candidate.targetPrice = 0.0;
      candidate.riskReward  = 0.0;
      candidate.noTradeReason = reason;
     }

   void ClearCandidate(SSetupCandidate &candidate) const
     {
      candidate.active = true;
      candidate.direction = SETUP_NONE;
      candidate.type = SETUP_NO_TRADE;
      candidate.status = STATUS_NO_TRADE;
      candidate.barTime = 0;
      candidate.entryPrice = 0.0;
      candidate.stopPrice = 0.0;
      candidate.targetPrice = 0.0;
      candidate.riskReward = 0.0;
      candidate.contextScore = 0;
      candidate.signalScore = 0;
      candidate.locationScore = 0;
      candidate.followThroughScore = 0;
      candidate.roomScore = 0;
      candidate.opposingPressureScore = 0;
      candidate.qualityScore = 0;
      for(int i = 0; i < 8; i++)
         candidate.reasons[i] = "";
      for(int i = 0; i < 6; i++)
         candidate.risks[i] = "";
      candidate.noTradeReason = "";
     }

   void AddReason(SSetupCandidate &candidate, const int index, const string reason) const
     {
      if(index >= 0 && index < ArraySize(candidate.reasons))
         candidate.reasons[index] = reason;
     }

   void AddRisk(SSetupCandidate &candidate, const int index, const string risk) const
     {
      if(index >= 0 && index < ArraySize(candidate.risks))
         candidate.risks[index] = risk;
     }

   bool IsLong(const SSetupCandidate &candidate) const
     {
      return(candidate.direction == SETUP_LONG);
     }

public:
   CDecisionEngine(const int minimumQuality = 55, const double minimumRiskReward = 1.5)
     {
      m_minimumQuality = MathMax(0, MathMin(100, minimumQuality));
      m_minimumRiskReward = MathMax(0.1, minimumRiskReward);
     }

   void Analyze(const SBarInfo &bar, const SContextInfo &context,
                const SPatternInfo &pattern, const SMeasuredMoveInfo &measuredMove,
                SSetupCandidate &candidate) const
     {
      ClearCandidate(candidate);
      candidate.barTime = bar.time;
      candidate.entryPrice = bar.close;

      bool longSignal = bar.pullbackType == PB_H1 || bar.pullbackType == PB_H2;
      bool shortSignal = bar.pullbackType == PB_L1 || bar.pullbackType == PB_L2;

      if(context.failedBullBreakout)
        {
         candidate.direction = SETUP_LONG;
         candidate.type = SETUP_FAILED_BREAKOUT;
         AddReason(candidate, 0, "Bear breakout failed and the signal bar closed bullishly");
        }
      else if(context.failedBearBreakout)
        {
         candidate.direction = SETUP_SHORT;
         candidate.type = SETUP_FAILED_BREAKOUT;
         AddReason(candidate, 0, "Bull breakout failed and the signal bar closed bearishly");
        }
      else if(pattern.type == PATTERN_WEDGE_RISING)
        {
         candidate.direction = SETUP_SHORT;
         candidate.type = SETUP_WEDGE_REVERSAL;
         AddReason(candidate, 0, "Three-push rising wedge is a bearish reversal heuristic");
        }
      else if(pattern.type == PATTERN_WEDGE_FALLING)
        {
         candidate.direction = SETUP_LONG;
         candidate.type = SETUP_WEDGE_REVERSAL;
         AddReason(candidate, 0, "Three-push falling wedge is a bullish reversal heuristic");
        }
      else if(bar.isBreakoutBar)
        {
         candidate.direction = bar.barType == BAR_BULL_TREND ? SETUP_LONG : SETUP_SHORT;
         candidate.type = SETUP_BREAKOUT_FOLLOW_THROUGH;
         AddReason(candidate, 0, "Strong close created a fresh extreme");
        }
      else if(bar.pullbackType == PB_H2 || bar.pullbackType == PB_L2)
        {
         candidate.direction = bar.pullbackType == PB_H2 ? SETUP_LONG : SETUP_SHORT;
         candidate.type = SETUP_SECOND_ENTRY;
         AddReason(candidate, 0, "Second-entry pullback structure detected");
        }
      else if(longSignal || shortSignal)
        {
         candidate.direction = longSignal ? SETUP_LONG : SETUP_SHORT;
         candidate.type = SETUP_TREND_PULLBACK;
         AddReason(candidate, 0, "First-entry pullback structure detected");
        }

      if(candidate.direction == SETUP_NONE || !context.valid)
        {
         NoTrade(candidate, context.valid ? "No composed context and signal-bar setup"
                                          : "Insufficient closed-bar context");
         return;
        }

      bool longTrade = IsLong(candidate);
      double stopBuffer = MathMax(_Point, bar.range * 0.25);
      candidate.stopPrice = longTrade ? bar.low - stopBuffer : bar.high + stopBuffer;
      double risk = MathAbs(candidate.entryPrice - candidate.stopPrice);
      if(risk <= 0.0)
        {
         NoTrade(candidate, "Invalid structural stop distance");
         return;
        }

      // A target must sit BEYOND entry in the direction of the trade, or
      // it is not a target at all. The baseline below always does. The
      // resistance and support clamps preserve that property because they
      // only ever pull the target toward, but still above (long) or below
      // (short), entry.
      //
      // A measured move does NOT. Its direction alignment is checked, but
      // the projected price can still land short of entry when the pivot
      // sits well below the current price, which is common in a failed
      // breakout. Because reward/risk is computed from an ABSOLUTE
      // difference, adopting such a target used to produce a healthy
      // looking R:R and a full roomScore for a target that could never be
      // reached. Real exports showed 6,025 of 72,188 rows with the target
      // on the wrong side of entry.
      double target = longTrade ? candidate.entryPrice + 2.0 * bar.range
                                : candidate.entryPrice - 2.0 * bar.range;

      bool mmUsable = measuredMove.active &&
                      ((longTrade && measuredMove.isBullish) ||
                       (!longTrade && !measuredMove.isBullish)) &&
                      (longTrade ? measuredMove.targetPrice > candidate.entryPrice
                                 : measuredMove.targetPrice < candidate.entryPrice);

      if(mmUsable)
         target = measuredMove.targetPrice;
      else if(longTrade && context.resistance > candidate.entryPrice)
        {
         double clamped = MathMin(target, context.resistance);
         // Only accept the clamp if it still leaves the target strictly
         // beyond entry by more than one point. A resistance sitting a
         // hair above entry otherwise produces a target that exports as
         // the same printed price as entry, which no consumer can tell
         // apart from a target that is not beyond entry at all. The
         // reward/risk gate then rejects the economically-useless ones.
         if(longTrade ? (clamped > candidate.entryPrice + _Point)
                      : (clamped < candidate.entryPrice - _Point))
            target = clamped;
        }
      else if(!longTrade && context.support > 0.0 && context.support < candidate.entryPrice)
        {
         double clamped = MathMax(target, context.support);
         if(longTrade ? (clamped > candidate.entryPrice + _Point)
                      : (clamped < candidate.entryPrice - _Point))
            target = clamped;
        }

      // Final guard, so no future branch can emit a target behind entry.
      // One point of separation is the minimum, because the export prints
      // five decimals and anything tighter is indistinguishable from entry.
      bool beyondEntry = longTrade ? (target >= candidate.entryPrice + _Point)
                                   : (target <= candidate.entryPrice - _Point);
      if(!beyondEntry)
        {
         NoTrade(candidate, "No usable target beyond entry in the trade direction");
         return;
        }

      candidate.targetPrice = target;
      candidate.riskReward = MathAbs(target - candidate.entryPrice) / risk;

      ENUM_MARKET_STATE alignedState = longTrade ? STATE_BULL_TREND : STATE_BEAR_TREND;
      if(context.mediumState == alignedState) candidate.contextScore += 12;
      else if(context.mediumState == STATE_TRADING_RANGE) candidate.contextScore += 7;
      if(context.microState == alignedState) candidate.contextScore += 8;
      if(context.microState == STATE_TRANSITION) candidate.contextScore += 3;
      if((longTrade && context.bullPressure > 0.55) || (!longTrade && context.bearPressure > 0.55))
         candidate.contextScore += 5;

      if(bar.strength == STRENGTH_STRONG) candidate.signalScore += 20;
      else if(bar.strength == STRENGTH_MODERATE) candidate.signalScore += 14;
      if(longTrade && bar.clv >= 0.25) candidate.signalScore += 7;
      if(!longTrade && bar.clv <= -0.25) candidate.signalScore += 7;
      if(bar.signalQuality == QUALITY_STRONG) candidate.signalScore += 5;

      if(longTrade && context.nearSupport && !context.nearResistance) candidate.locationScore += 20;
      if(!longTrade && context.nearResistance && !context.nearSupport) candidate.locationScore += 20;
      if(context.nearSupport || context.nearResistance) candidate.locationScore += 8;
      if(!longTrade && context.nearResistance) AddRisk(candidate, 0, "Resistance is close to entry");
      if(longTrade && context.nearSupport) AddRisk(candidate, 0, "Support may be tested before reaching target");

      if(bar.hasFollowThrough) candidate.followThroughScore += 15;
      if(bar.failedFollowThrough) candidate.followThroughScore = 0;
      if(bar.isBreakoutBar && bar.hasFollowThrough) candidate.followThroughScore = 15;

      if(candidate.riskReward >= 2.0) candidate.roomScore += 15;
      else if(candidate.riskReward >= 1.0) candidate.roomScore += 8;
      if(candidate.riskReward < m_minimumRiskReward) AddRisk(candidate, 1, "Reward/risk is below the configured minimum");

      double opposing = longTrade ? context.bearPressure : context.bullPressure;
      if(opposing >= 0.65) candidate.opposingPressureScore = 0;
      else if(opposing <= 0.35) candidate.opposingPressureScore = 15;
      else candidate.opposingPressureScore = 8;

      candidate.qualityScore = candidate.contextScore + candidate.signalScore + candidate.locationScore +
                              candidate.followThroughScore + candidate.roomScore + candidate.opposingPressureScore;
      if(candidate.qualityScore > 100)
         candidate.qualityScore = 100;

      if(candidate.qualityScore >= 75 && candidate.type == SETUP_BREAKOUT_FOLLOW_THROUGH && bar.hasFollowThrough)
         candidate.status = STATUS_CONFIRMED;
      else if(candidate.qualityScore >= 70)
         candidate.status = STATUS_PROBABLE;
      else if(candidate.qualityScore >= m_minimumQuality)
         candidate.status = STATUS_POSSIBLE;
      else
         candidate.status = STATUS_WEAK;

      if(candidate.qualityScore < m_minimumQuality)
         candidate.noTradeReason = "Setup evidence is below the configured quality threshold";
      else if(candidate.riskReward < m_minimumRiskReward)
        {
         NoTrade(candidate, "Reward/risk is below the configured minimum");
        }

      AddReason(candidate, 1, StringFormat("Context score: %d/25", candidate.contextScore));
      AddReason(candidate, 2, StringFormat("Signal score: %d/32", candidate.signalScore));
      AddReason(candidate, 3, StringFormat("Location score: %d/20", candidate.locationScore));
      AddReason(candidate, 4, StringFormat("Follow-through score: %d/15", candidate.followThroughScore));
      AddReason(candidate, 5, StringFormat("Room score: %d/15", candidate.roomScore));
      AddReason(candidate, 6, StringFormat("Opposing pressure score: %d/15", candidate.opposingPressureScore));
      AddReason(candidate, 7, StringFormat("Total evidence strength: %d/100", candidate.qualityScore));
     }
  };

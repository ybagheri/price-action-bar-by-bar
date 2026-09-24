//+------------------------------------------------------------------+
//|                                                   PAB_Types.mqh |
//|                        Price Action Bar-by-Bar — Shared Types    |
//|                                                                    |
//| Central definition of every enum / struct shared by the analyzer |
//| classes. Keeping these in one file avoids circular includes and  |
//| gives every module the same vocabulary (Single Source of Truth). |
//+------------------------------------------------------------------+
#property strict

//====================================================================
// BAR CLASSIFICATION
//====================================================================

// The fundamental classification of a single bar, per Al Brooks'
// "Reading Price Charts Bar by Bar".
enum ENUM_BAR_TYPE
  {
   BAR_BULL_TREND,   // strong close near the high, small tails
   BAR_BEAR_TREND,   // strong close near the low, small tails
   BAR_DOJI,         // small body relative to range, indecision bar
   BAR_INSIDE,       // high <= prev high AND low >= prev low
   BAR_OUTSIDE       // high >= prev high AND low <= prev low
  };

// Brooks' pullback-bar taxonomy, counted from the most recent
// swing extreme in the direction of the prevailing trend leg.
enum ENUM_PULLBACK_TYPE
  {
   PB_NONE,          // not currently in a pullback sequence
   PB_H1,            // 1st pullback bar in a bull leg (high-1)
   PB_H2,            // 2nd pullback bar in a bull leg (high-2)
   PB_H3_PLUS,       // 3rd+ pullback bar in a bull leg (high-3, 4...)
   PB_L1,            // 1st pullback bar in a bear leg (low-1)
   PB_L2,            // 2nd pullback bar in a bear leg (low-2)
   PB_L3_PLUS        // 3rd+ pullback bar in a bear leg (low-3, 4...)
  };

// Signal quality for a pullback bar, per Phase 2: an objective proxy for
// how "textbook" the bar looks as an H1/H2/L1/L2 entry trigger. Computed
// from Close Location Value (CLV) and whether the bar's extreme stays
// inside the prior same-type pullback bar's extreme (the classic
// "smaller second pullback" quality marker Brooks describes for H2/L2).
enum ENUM_SIGNAL_QUALITY
  {
   QUALITY_NA,        // not a pullback bar / not applicable
   QUALITY_WEAK,
   QUALITY_MODERATE,
   QUALITY_STRONG
  };

// One fully-analyzed bar. This is the atomic unit every higher-level
// module (swings, trading range, patterns) consumes.
struct SBarInfo
  {
   datetime          time;
   double            open, high, low, close;
   double            bodySize;         // |close-open|
   double            range;            // high-low
   double            bodyRatio;        // bodySize / range, 0 when range==0
   double            clv;              // Close Location Value: -1 (close=low) .. +1 (close=high)
   bool              isBullish;        // close > open
   ENUM_BAR_TYPE     barType;
   ENUM_PULLBACK_TYPE pullbackType;
   int               pullbackIndex;    // 1,2,3... within current sequence, 0 if PB_NONE
   ENUM_SIGNAL_QUALITY signalQuality;  // Phase 2: objective quality score for pullback bars
   bool              isBreakoutBar;    // Phase 3: strong trend bar that also makes a fresh N-bar extreme
   bool              isClimax;         // Phase 3: unusually large range + weak/indecisive close (exhaustion risk)

   void Clear()
     {
      time = 0; open = high = low = close = 0.0;
      bodySize = range = bodyRatio = clv = 0.0;
      isBullish = false;
      barType = BAR_DOJI;
      pullbackType = PB_NONE;
      pullbackIndex = 0;
      signalQuality = QUALITY_NA;
      isBreakoutBar = false;
      isClimax = false;
     }
  };

//====================================================================
// SWINGS
//====================================================================

enum ENUM_SWING_TYPE
  {
   SWING_HIGH,
   SWING_LOW
  };

struct SSwingPoint
  {
   int               barIndex;   // index in the series (0 = current, increasing = older)
   datetime          time;
   double            price;
   ENUM_SWING_TYPE   type;
  };

//====================================================================
// TRADING RANGE / TREND STATE
//====================================================================

// Brooks' market-cycle state: is price trending or trading sideways?
// Deliberately coarse — the fine-grained "always-in" judgment calls
// are intentionally left to the trader, per the project's design notes.
enum ENUM_MARKET_STATE
  {
   STATE_TRADING_RANGE,
   STATE_BULL_TREND,
   STATE_BEAR_TREND,
   STATE_TRANSITION       // breaking out of a range, not yet confirmed
  };

struct STradingRangeInfo
  {
   bool              active;
   double            top;
   double            bottom;
   int               startBarIndex;    // oldest bar (largest index) belonging to the range
   int               endBarIndex;      // newest bar (smallest index)
   double            overlapRatio;     // 0..1, higher = more overlap/consolidation
  };

//====================================================================
// PATTERNS
//====================================================================

enum ENUM_PATTERN_TYPE
  {
   PATTERN_NONE,
   PATTERN_HIGHER_HIGHS_LOWS,   // trending structure, bull
   PATTERN_LOWER_HIGHS_LOWS,    // trending structure, bear
   PATTERN_DOUBLE_TOP,
   PATTERN_DOUBLE_BOTTOM,
   PATTERN_TRIANGLE,            // converging highs & lows
   PATTERN_WEDGE_RISING,        // 3-push rising wedge (bearish per Brooks)
   PATTERN_WEDGE_FALLING        // 3-push falling wedge (bullish per Brooks)
  };

struct SPatternInfo
  {
   ENUM_PATTERN_TYPE type;
   datetime          startTime;  // stable across calls, unlike a cached bar index
   datetime          endTime;
   string            note;       // short human-readable annotation for chart/log
  };

//====================================================================
// ALWAYS-IN (Phase 3)
//====================================================================

// Brooks' "always-in" concept: if you had to be in the market right now,
// which side are you on? Unlike ENUM_MARKET_STATE (which re-scores every
// bar from a rolling lookback window and can flicker), always-in is a
// STICKY state that only flips on a clear structural break — a close
// beyond the most recent confirmed swing extreme in the opposite
// direction — and holds until the next such break.
enum ENUM_ALWAYS_IN_STATE
  {
   ALWAYS_IN_NONE,     // not enough structure yet to have an opinion
   ALWAYS_IN_LONG,
   ALWAYS_IN_SHORT
  };

//====================================================================
// MEASURED MOVE (Phase 3, lightweight)
//====================================================================

// A minimal three-swing measured-move projection: leg1 = swing(n-2)->swing(n-1),
// leg2 projected with equal size from swing(n) (the latest pullback swing).
// Deliberately simple — see README for why a fuller implementation is
// intentionally left to (and better served by) the existing FM-Indicator
// project rather than duplicated here.
struct SMeasuredMoveInfo
  {
   bool              active;
   bool              isBullish;        // projecting upward (bull leg1) or downward
   double            leg1Start;
   double            leg1End;
   double            pivotPrice;       // swing the projection is measured from
   double            targetPrice;      // leg1Start/End size projected from pivotPrice
   datetime          pivotTime;        // stable across calls, unlike a cached bar index
  };

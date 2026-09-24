//+------------------------------------------------------------------+
//|                                              ChartRenderer.mqh   |
//|                                                                    |
//| The ONLY class allowed to touch chart objects. Every analyzer    |
//| module is pure logic and knows nothing about ObjectCreate/colors |
//| — this keeps analysis unit-testable (in a Strategy-Tester/script |
//| harness) independent of the chart, and means a future NinjaTrader|
//| port only has to rewrite this one file's equivalent.             |
//+------------------------------------------------------------------+
#property strict

#include "PAB_Types.mqh"

class CChartRenderer
  {
private:
   string            m_prefix;
   long              m_chartId;
   color             m_colorBull;
   color             m_colorBear;
   color             m_colorDoji;
   color             m_colorSwingHigh;
   color             m_colorSwingLow;
   color             m_colorRange;
   color             m_colorPattern;
   color             m_colorBreakout;
   color             m_colorClimax;
   color             m_colorMeasuredMove;
   bool              m_showPullbackLabels;
   bool              m_showSwings;
   bool              m_showRange;
   bool              m_showPatterns;
   bool              m_showBreakouts;
   bool              m_showClimax;
   bool              m_showMeasuredMove;

   string ObjName(const string kind, const string uniq)
     {
      return(m_prefix + "_" + kind + "_" + uniq);
     }

   void DeleteObject(const string name)
     {
      if(ObjectFind(m_chartId, name) >= 0)
         ObjectDelete(m_chartId, name);
     }

public:
                     CChartRenderer(const long chartId = 0, const string prefix = "PAB")
     {
      m_chartId = chartId;
      m_prefix  = prefix;
      m_colorBull       = clrDodgerBlue;
      m_colorBear       = clrCrimson;
      m_colorDoji       = clrSilver;
      m_colorSwingHigh  = clrOrange;
      m_colorSwingLow   = clrLime;
      m_colorRange      = clrKhaki;
      m_colorPattern    = clrMagenta;
      m_colorBreakout   = clrYellow;
      m_colorClimax     = clrRed;
      m_colorMeasuredMove = clrAqua;
      m_showPullbackLabels = true;
      m_showSwings         = true;
      m_showRange          = true;
      m_showPatterns       = true;
      m_showBreakouts      = true;
      m_showClimax         = true;
      m_showMeasuredMove   = true;
     }

   //--- configuration ---------------------------------------------------
   void SetColors(const color bull, const color bear, const color doji,
                   const color swingHigh, const color swingLow,
                   const color range, const color pattern,
                   const color breakout, const color climax, const color measuredMove)
     {
      m_colorBull = bull; m_colorBear = bear; m_colorDoji = doji;
      m_colorSwingHigh = swingHigh; m_colorSwingLow = swingLow;
      m_colorRange = range; m_colorPattern = pattern;
      m_colorBreakout = breakout; m_colorClimax = climax; m_colorMeasuredMove = measuredMove;
     }

   void SetVisibility(const bool pullbackLabels, const bool swings,
                       const bool range, const bool patterns,
                       const bool breakouts, const bool climax, const bool measuredMove)
     {
      m_showPullbackLabels = pullbackLabels;
      m_showSwings = swings;
      m_showRange = range;
      m_showPatterns = patterns;
      m_showBreakouts = breakouts;
      m_showClimax = climax;
      m_showMeasuredMove = measuredMove;
     }

   //--- drawing -----------------------------------------------------------
   void DrawBarLabel(const SBarInfo &bar, const int barIndex)
     {
      string name = ObjName("LBL", (string)bar.time);
      if(!m_showPullbackLabels || bar.pullbackType == PB_NONE)
        {
         DeleteObject(name);
         return;
        }

      string txt;
      switch(bar.pullbackType)
        {
         case PB_H1:      txt = "H1"; break;
         case PB_H2:      txt = "H2"; break;
         case PB_H3_PLUS:  txt = "H3+"; break;
         case PB_L1:      txt = "L1"; break;
         case PB_L2:      txt = "L2"; break;
         case PB_L3_PLUS:  txt = "L3+"; break;
         default:         return;
        }

      // Phase 2: append a quality marker so a strong H2/L2 (favorable close
      // + shallower than the previous pullback) stands out from a weak one
      // at a glance, without needing a separate object/legend.
      int fontSize = 7;
      if(bar.signalQuality == QUALITY_STRONG)  { txt += "*"; fontSize = 9; }
      else if(bar.signalQuality == QUALITY_WEAK) { fontSize = 6; }

      bool isHigh = (bar.pullbackType == PB_H1 || bar.pullbackType == PB_H2 || bar.pullbackType == PB_H3_PLUS);
      double price = isHigh ? bar.high : bar.low;
      double offset = bar.range * 0.15 + _Point;
      price = isHigh ? price + offset : price - offset;

      if(ObjectFind(m_chartId, name) < 0)
         ObjectCreate(m_chartId, name, OBJ_TEXT, 0, bar.time, price);
      else
         ObjectMove(m_chartId, name, 0, bar.time, price);

      ObjectSetString(m_chartId, name, OBJPROP_TEXT, txt);
      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, isHigh ? m_colorBear : m_colorBull);
      ObjectSetInteger(m_chartId, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(m_chartId, name, OBJPROP_ANCHOR, isHigh ? ANCHOR_BOTTOM : ANCHOR_TOP);
     }

   void DrawSwing(const SSwingPoint &sp)
     {
      if(!m_showSwings)
         return;
      string name = ObjName("SWING", (string)sp.time + (sp.type == SWING_HIGH ? "H" : "L"));
      if(ObjectFind(m_chartId, name) < 0)
         ObjectCreate(m_chartId, name, OBJ_ARROW, 0, sp.time, sp.price);
      ObjectSetInteger(m_chartId, name, OBJPROP_ARROWCODE, sp.type == SWING_HIGH ? 217 : 218);
      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, sp.type == SWING_HIGH ? m_colorSwingHigh : m_colorSwingLow);
      ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, 1);
     }

   void DrawTradingRange(const STradingRangeInfo &r, const datetime &time[])
     {
      string name = ObjName("RANGE", "current");
      if(!m_showRange || !r.active)
        {
         DeleteObject(name);
         return;
        }
      datetime t1 = time[r.startBarIndex];
      datetime t2 = time[r.endBarIndex];
      if(ObjectFind(m_chartId, name) < 0)
         ObjectCreate(m_chartId, name, OBJ_RECTANGLE, 0, t1, r.top, t2, r.bottom);
      else
        {
         ObjectMove(m_chartId, name, 0, t1, r.top);
         ObjectMove(m_chartId, name, 1, t2, r.bottom);
        }
      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, m_colorRange);
      ObjectSetInteger(m_chartId, name, OBJPROP_FILL, true);
      ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
      ObjectSetInteger(m_chartId, name, OBJPROP_STYLE, STYLE_DOT);
     }

   // Phase 3: small triangle under/over a breakout bar (yellow by default).
   void DrawBreakoutMarker(const SBarInfo &bar)
     {
      string name = ObjName("BRK", (string)bar.time);
      if(!m_showBreakouts || !bar.isBreakoutBar)
        {
         DeleteObject(name);
         return;
        }
      bool bull = (bar.barType == BAR_BULL_TREND);
      double offset = bar.range * 0.30 + _Point;
      double price = bull ? bar.low - offset : bar.high + offset;
      if(ObjectFind(m_chartId, name) < 0)
         ObjectCreate(m_chartId, name, OBJ_ARROW, 0, bar.time, price);
      ObjectSetInteger(m_chartId, name, OBJPROP_ARROWCODE, bull ? 233 : 234);
      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, m_colorBreakout);
      ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, 2);
     }

   // Phase 3: "X" marker on a climax/exhaustion bar (red by default) — a
   // visual heads-up that this big-range bar had a weak/indecisive close.
   void DrawClimaxMarker(const SBarInfo &bar)
     {
      string name = ObjName("CLX", (string)bar.time);
      if(!m_showClimax || !bar.isClimax)
        {
         DeleteObject(name);
         return;
        }
      double price = (bar.high + bar.low) / 2.0;
      if(ObjectFind(m_chartId, name) < 0)
         ObjectCreate(m_chartId, name, OBJ_ARROW, 0, bar.time, price);
      ObjectSetInteger(m_chartId, name, OBJPROP_ARROWCODE, 251); // X
      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, m_colorClimax);
      ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, 2);
     }

   // Phase 3: horizontal dashed target line for the current measured-move
   // projection, from the pivot swing out to the current (newest) bar.
   void DrawMeasuredMove(const SMeasuredMoveInfo &mm, const datetime currentBarTime)
     {
      string name = ObjName("MM", "target");
      string lblName = ObjName("MM", "label");
      if(!m_showMeasuredMove || !mm.active)
        {
         DeleteObject(name);
         DeleteObject(lblName);
         return;
        }
      if(ObjectFind(m_chartId, name) < 0)
         ObjectCreate(m_chartId, name, OBJ_TREND, 0, mm.pivotTime, mm.targetPrice, currentBarTime, mm.targetPrice);
      else
        {
         ObjectMove(m_chartId, name, 0, mm.pivotTime, mm.targetPrice);
         ObjectMove(m_chartId, name, 1, currentBarTime, mm.targetPrice);
        }
      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, m_colorMeasuredMove);
      ObjectSetInteger(m_chartId, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(m_chartId, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, 1);

      if(ObjectFind(m_chartId, lblName) < 0)
         ObjectCreate(m_chartId, lblName, OBJ_TEXT, 0, currentBarTime, mm.targetPrice);
      else
         ObjectMove(m_chartId, lblName, 0, currentBarTime, mm.targetPrice);
      ObjectSetString(m_chartId, lblName, OBJPROP_TEXT, "MM target " + DoubleToString(mm.targetPrice, _Digits));
      ObjectSetInteger(m_chartId, lblName, OBJPROP_COLOR, m_colorMeasuredMove);
      ObjectSetInteger(m_chartId, lblName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(m_chartId, lblName, OBJPROP_ANCHOR, mm.isBullish ? ANCHOR_LOWER : ANCHOR_UPPER);
     }

   void DrawPattern(const SPatternInfo &p, const double topPrice)
     {
      string name = ObjName("PATTERN", "current");
      if(!m_showPatterns || p.type == PATTERN_NONE)
        {
         DeleteObject(name);
         return;
        }
      if(ObjectFind(m_chartId, name) < 0)
         ObjectCreate(m_chartId, name, OBJ_TEXT, 0, p.endTime, topPrice);
      else
         ObjectMove(m_chartId, name, 0, p.endTime, topPrice);
      ObjectSetString(m_chartId, name, OBJPROP_TEXT, p.note);
      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, m_colorPattern);
      ObjectSetInteger(m_chartId, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(m_chartId, name, OBJPROP_ANCHOR, ANCHOR_LOWER);
     }

   void DrawStatePanel(const string text)
     {
      string name = ObjName("PANEL", "state");
      if(ObjectFind(m_chartId, name) < 0)
        {
         ObjectCreate(m_chartId, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chartId, name, OBJPROP_XDISTANCE, 10);
         ObjectSetInteger(m_chartId, name, OBJPROP_YDISTANCE, 20);
         ObjectSetInteger(m_chartId, name, OBJPROP_FONTSIZE, 9);
        }
      ObjectSetString(m_chartId, name, OBJPROP_TEXT, text);
      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clrWhite);
     }

   void HideTradingRange()
     {
      DeleteObject(ObjName("RANGE", "current"));
     }

   void HidePattern()
     {
      DeleteObject(ObjName("PATTERN", "current"));
     }

   void HideMeasuredMove()
     {
      DeleteObject(ObjName("MM", "target"));
      DeleteObject(ObjName("MM", "label"));
     }

   void HideStatePanel()
     {
      DeleteObject(ObjName("PANEL", "state"));
     }

   // Removes every object this indicator ever created (OnDeinit / on reload).
   void ClearAll()
     {
      ObjectsDeleteAll(m_chartId, m_prefix + "_");
     }
  };

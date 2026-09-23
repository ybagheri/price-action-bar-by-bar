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
   bool              m_showPullbackLabels;
   bool              m_showSwings;
   bool              m_showRange;
   bool              m_showPatterns;

   string ObjName(const string kind, const string uniq)
     {
      return(m_prefix + "_" + kind + "_" + uniq);
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
      m_showPullbackLabels = true;
      m_showSwings         = true;
      m_showRange          = true;
      m_showPatterns       = true;
     }

   //--- configuration ---------------------------------------------------
   void SetColors(const color bull, const color bear, const color doji,
                   const color swingHigh, const color swingLow,
                   const color range, const color pattern)
     {
      m_colorBull = bull; m_colorBear = bear; m_colorDoji = doji;
      m_colorSwingHigh = swingHigh; m_colorSwingLow = swingLow;
      m_colorRange = range; m_colorPattern = pattern;
     }

   void SetVisibility(const bool pullbackLabels, const bool swings,
                       const bool range, const bool patterns)
     {
      m_showPullbackLabels = pullbackLabels;
      m_showSwings = swings;
      m_showRange = range;
      m_showPatterns = patterns;
     }

   //--- drawing -----------------------------------------------------------
   void DrawBarLabel(const SBarInfo &bar, const int barIndex)
     {
      if(!m_showPullbackLabels || bar.pullbackType == PB_NONE)
         return;

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

      bool isHigh = (bar.pullbackType == PB_H1 || bar.pullbackType == PB_H2 || bar.pullbackType == PB_H3_PLUS);
      string name = ObjName("LBL", (string)bar.time);
      double price = isHigh ? bar.high : bar.low;
      double offset = bar.range * 0.15 + _Point;
      price = isHigh ? price + offset : price - offset;

      if(ObjectFind(m_chartId, name) < 0)
         ObjectCreate(m_chartId, name, OBJ_TEXT, 0, bar.time, price);
      else
         ObjectMove(m_chartId, name, 0, bar.time, price);

      ObjectSetString(m_chartId, name, OBJPROP_TEXT, txt);
      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, isHigh ? m_colorBear : m_colorBull);
      ObjectSetInteger(m_chartId, name, OBJPROP_FONTSIZE, 7);
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
      if(!m_showRange || !r.active)
         return;
      string name = ObjName("RANGE", "current");
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

   void DrawPattern(const SPatternInfo &p, const datetime &time[], const double topPrice)
     {
      if(!m_showPatterns || p.type == PATTERN_NONE)
         return;
      string name = ObjName("PATTERN", (string)time[p.endBarIndex]);
      if(ObjectFind(m_chartId, name) < 0)
         ObjectCreate(m_chartId, name, OBJ_TEXT, 0, time[p.endBarIndex], topPrice);
      else
         ObjectMove(m_chartId, name, 0, time[p.endBarIndex], topPrice);
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

   // Removes every object this indicator ever created (OnDeinit / on reload).
   void ClearAll()
     {
      ObjectsDeleteAll(m_chartId, m_prefix + "_");
     }
  };

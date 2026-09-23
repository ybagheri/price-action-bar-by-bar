//+------------------------------------------------------------------+
//|                                              PAB_IAnalyzer.mqh   |
//|                                                                    |
//| Common interface for every analyzer stage in the pipeline         |
//| (BarClassifier, SwingDetector, TradingRangeDetector,               |
//|  PatternDetector). Lets the main indicator orchestrate the         |
//| pipeline polymorphically and lets any future analyzer be dropped  |
//| in without touching the orchestrator.                            |
//+------------------------------------------------------------------+
#property strict

interface IAnalyzer
  {
   // Called once per completed bar, oldest-processed-first, by the
   // orchestrator. 'index' follows MQL5 series indexing (0 = current).
   void Update(const int index,
               const datetime &time[],
               const double &open[],
               const double &high[],
               const double &low[],
               const double &close[],
               const int rates_total);

   // Human-readable name, used in logs and on-chart comments.
   string Name();

   // Drop all internal state (on ChartEvent "reset" or timeframe change).
   void Reset();
  };

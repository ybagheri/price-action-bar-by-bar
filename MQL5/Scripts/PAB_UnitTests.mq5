//+------------------------------------------------------------------+
//|                                          PAB_UnitTests.mq5       |
//|                                                                    |
//| The interactive entry point to the regression harness. Run it from |
//| the Navigator (Scripts) on any chart; output goes to the          |
//| Experts/Journal log. It never touches chart objects.              |
//|                                                                    |
//| The assertions themselves live in                                |
//| Include/PriceActionBarByBar/PabTests.mqh and are shared verbatim  |
//| with Experts/PAB_HarnessEA.mq5, which runs the same suite          |
//| headlessly in the Strategy Tester. This file is a launcher and    |
//| holds no test logic, so the two can never diverge.                 |
//|                                                                    |
//| This is intentionally NOT a Strategy Tester backtest of the       |
//| strategy. It is a fast, deterministic check over the analyzer      |
//| classes that should be re-run after any change to Include/*.mqh.   |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

#include "../Include/PriceActionBarByBar/PabTests.mqh"

void OnStart()
  {
   Print("======================================================");
   Print(" PriceActionBarByBar - Unit Test Harness");
   Print("======================================================");

   RunAllPabTests();

   Print("------------------------------------------------------");
   PrintFormat(" RESULT: %d passed, %d failed", g_pass, g_fail);
   Print("======================================================");

   if(g_fail > 0)
      Alert("PriceActionBarByBar unit tests: ", g_fail, " FAILED - see Experts log.");
   else
      Print("PriceActionBarByBar unit tests: all ", g_pass, " passed.");
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                            PAB_HarnessEA.mq5     |
//|                      Price Action Bar-by-Bar - Headless Harness  |
//|                                                                    |
//| PHASE 17. Runs the regression suite unattended in the MT5 Strategy |
//| Tester, so a test run does not depend on a human opening a chart.  |
//|                                                                    |
//| Why an Expert Advisor and not the Script: MT5 only calls           |
//| OnCalculate for files built as indicators. A file in Experts\ is   |
//| driven through OnInit/OnTick, which is what makes this scriptable  |
//| from the terminal command line via /config:. The Script remains the |
//| interactive path; both call the same RunAllPabTests().             |
//|                                                                    |
//| It writes a machine-readable summary next to the journal, because  |
//| scraping the tester log for a pass count is exactly the kind of    |
//| fragile evidence this project should not depend on. The summary    |
//| also records the engine version and the MT5 build, so an archived   |
//| result says what produced it.                                      |
//|                                                                    |
//| It places no orders and opens no charts. There is no CTrade call.  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include "../Include/PriceActionBarByBar/PabTests.mqh"

input string InpResultFile = "pab_harness.txt";

//+------------------------------------------------------------------+
int OnInit()
  {
   Print("======================================================");
   Print(" PriceActionBarByBar - Unit Test Harness (headless)");
   Print("======================================================");

   RunAllPabTests();

   Print("------------------------------------------------------");
   PrintFormat(" RESULT: %d passed, %d failed", g_pass, g_fail);
   Print("======================================================");

   // The summary is rewritten on every run, never appended, so a stale
   // PASS can never be mistaken for the current one.
   int handle = FileOpen(InpResultFile,
                         FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(handle == INVALID_HANDLE)
     {
      PrintFormat("PAB_HarnessEA: cannot write %s, error %d. In the Strategy "
                  "Tester a relative path resolves to the agent's MQL5\\Files "
                  "folder.", InpResultFile, GetLastError());
      return(g_fail > 0 ? INIT_FAILED : INIT_SUCCEEDED);
     }

   // FileWriteString writes the string verbatim, so each record carries its
   // own terminator. Without this the file is one run-on line and cannot be
   // parsed, which defeats the point of writing it.
   FileWriteString(handle, StringFormat("engine_version %s\r\n", PAB_ENGINE_VERSION));
   FileWriteString(handle, StringFormat("build %d\r\n", TerminalInfoInteger(TERMINAL_BUILD)));
   FileWriteString(handle, StringFormat("symbol %s\r\n", _Symbol));
   FileWriteString(handle, StringFormat("result %d %d\r\n", g_pass, g_fail));
   FileWriteString(handle, StringFormat("verdict %s\r\n", g_fail > 0 ? "FAIL" : "PASS"));
   if(g_fail > 0)
      FileWriteString(handle, "failing_assertions:\r\n");
   for(int i = 0; i < ArraySize(g_failures); i++)
      FileWriteString(handle, StringFormat("FAIL %s\r\n", g_failures[i]));
   FileClose(handle);

   PrintFormat("PAB_HarnessEA: summary written to %s, verdict %s",
               InpResultFile, g_fail > 0 ? "FAIL" : "PASS");

   return(INIT_SUCCEEDED);
  }

void OnTick()
  {
   // The whole suite runs once, in OnInit.
  }
//+------------------------------------------------------------------+

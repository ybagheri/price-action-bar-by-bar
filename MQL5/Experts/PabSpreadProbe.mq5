//+------------------------------------------------------------------+
//|                                             PabSpreadProbe.mq5 |
//|  A VIABILITY PROBE, NOT PART OF THE INDICATOR.                  |
//|                                                                   |
//|  Phase 20 asked whether a HISTORICAL per-bar spread can be       |
//|  measured on this machine. This file is how that question was    |
//|  answered, so the answer can be re-checked rather than trusted.  |
//|                                                                   |
//|  Run it in the Strategy Tester and read pab_spread_probe.txt      |
//|  from the AGENT's MQL5\Files folder. It reports what it saw,     |
//|  including every failure, and ends in a VERDICT line whose        |
//|  wording is chosen so it cannot be read optimistically.           |
//|                                                                   |
//|  VERDICT ON THIS MACHINE (Alpari MT5_3 build 6230, EURUSD):      |
//|                                                                   |
//|    Model=0 (Every tick)     -> "GENERATED_TICKS"                  |
//|    Model=2 (real ticks)     -> NO_TICKS, error 4014               |
//|                                                                   |
//|  and the tester log for the Model=2 run says, in its own words:  |
//|                                                                   |
//|    EURUSD,M5: 3145 ticks, 842 bars generated.                     |
//|                                                                   |
//|  "generated" is the operative word. Real tick mode did not        |
//|  engage, so the bid/ask the tester hands out are synthesised      |
//|  from OHLC and the spread inside them is a tester SETTING.        |
//|  A number produced that way is not a measurement of the broker,  |
//|  and Phase 19's blank cost columns stay correct. Recording the   |
//|  tester's spread as if it were measured is exactly the failure   |
//|  this project exists to prevent.                                  |
//|                                                                   |
//|  WHY CopyTicksRange cannot rescue it:                             |
//|                                                                   |
//|   - In the tester it is clipped to the tester's CURRENT time.     |
//|     Querying 2013.01.02..2013.01.03 from a run sitting at        |
//|     2013.01.02 00:05 returned exactly ONE tick, the one that      |
//|     woke OnTick. Real history is not reachable this way.          |
//|   - With real ticks requested it returns error 4014 and no data.  |
//|   - No per-day tick files exist under bases\...\ticks\<symbol>\    |
//|     on this machine. Only the ticks.dat index is there, so there  |
//|     is no cached tick history to reconstruct from.                |
//|   - ACCOUNT_TRADE_MODE reads 0 (disabled) inside the tester, so  |
//|     an agent cannot reach the broker to download ticks. A /config |
//|     run does not trigger the download the terminal UI would.      |
//|                                                                   |
//|  The one genuine trap in this file, which cost several compiles: |
//|  CopyTicksRange's signature is NOT (symbol, from, to, ticks).     |
//|  The array is the SECOND parameter and the times are ulong        |
//|  MILLISECONDS, not datetime:                                      |
//|                                                                   |
//|    int CopyTicksRange(const string symbol_name,                   |
//|                        MqlTick&    ticks_array[],                 |
//|                        uint        flags = COPY_TICKS_ALL,       |
//|                        ulong       from_msc = 0,                 |
//|                        ulong       to_msc   = 0);                |
//|                                                                   |
//|  Passing a datetime there gives error 246, and passing a literal  |
//|  gives 137 "lvalue expected". Both point at the wrong argument.  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

input string InpSymbol   = "EURUSD";
input string InpOldFrom  = "2013.01.02";   // the study year the exports cover
input string InpOldTo    = "2013.01.03";
input string InpNewFrom  = "2026.09.20";   // recent, to separate "old" from "no data at all"
input string InpNewTo    = "2026.09.21";

//--- 6 hours. Small enough that a dynamic tick array never blows memory,
//--- large enough that a real FX day is sampled in a sane number of calls.
const int CHUNK_HOURS = 6;

int    g_handle = INVALID_HANDLE;
bool   g_done   = false;

int OnInit()
{
   g_handle = FileOpen("pab_spread_probe.txt", FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(g_handle == INVALID_HANDLE)
     {
      Print("PabSpreadProbe: cannot open output, error ", GetLastError());
      return(INIT_FAILED);
     }

   string sym = InpSymbol;

   Emit("build="      + (string)TerminalInfoInteger(TERMINAL_BUILD));
   Emit("server="     + AccountInfoString(ACCOUNT_SERVER));
   Emit("symbol="     + sym);
   Emit("point="      + DoubleToString(SymbolInfoDouble(sym, SYMBOL_POINT), _Digits));
   Emit("digits="     + (string)SymbolInfoInteger(sym, SYMBOL_DIGITS));
   // ENUM_ACCOUNT_TRADE_MODE: 0=disabled 1=contest 2=demo 3=real.
   // Reads 0 inside the tester, which is why no tick download can happen here.
   Emit("trade_mode=" + (string)AccountInfoInteger(ACCOUNT_TRADE_MODE));
   Emit("period="     + (string)_Period);
   Emit("bars_via_iBars=" + (string)iBars(sym, _Period));

   // A failed date parse would quietly turn every window into 1970 and then
   // report "no history" for all of them, which is indistinguishable from the
   // real answer. So the parse is reported rather than trusted.
   Emit("parse_old_from=" + TimeToString(StringToTime(InpOldFrom))
        + " msc=" + (string)((ulong)((long)StringToTime(InpOldFrom) * 1000)));
   Emit("parse_old_to="   + TimeToString(StringToTime(InpOldTo)));
   Emit("parse_new_from=" + TimeToString(StringToTime(InpNewFrom)));
   Emit("parse_new_to="   + TimeToString(StringToTime(InpNewTo)));
   Emit("");

   return(INIT_SUCCEEDED);
}

//--- The symbol's history is not necessarily loaded when OnInit runs, and
//--- reading that early returns 4401, which looks exactly like "the broker
//--- has no data". Waiting for the first real tick avoids that false negative.
void OnTick()
{
   if(g_done) return;
   g_done = true;

   string sym = InpSymbol;

   MqlTick now;
   if(SymbolInfoTick(sym, now))
      Emit("live_tick_spread_points=" + DoubleToString((now.ask - now.bid) / SymbolInfoDouble(sym, SYMBOL_POINT), 1));
   else
      Emit("live_tick_spread_points=UNAVAILABLE error=" + (string)GetLastError());
   Emit("first_ontick_time=" + TimeToString(TimeCurrent()));
   Emit("bars_via_iBars=" + (string)iBars(sym, _Period));

   //--- reconfirm the documented iSpread/CopyBuffer failure -----------------
   // Expected: copied -1, error 4807. If this ever starts returning values,
   // the whole cost story in Phase 19 should be revisited.
   int sh = iSpread(sym, _Period, 1);
   Emit("iSpread_handle=" + (string)sh);
   if(sh != INVALID_HANDLE)
     {
      double buf[];
      ResetLastError();
      int got = CopyBuffer(sh, 0, 0, 10, buf);
      Emit("iSpread_CopyBuffer_copied=" + (string)got + " error=" + (string)GetLastError());
      IndicatorRelease(sh);
     }

   //--- are historical BARS available? --------------------------------------
   MqlRates rates[];
   ResetLastError();
   int nrates = CopyRates(sym, _Period, StringToTime(InpOldFrom), StringToTime(InpOldTo), rates);
   Emit("CopyRates_count=" + (string)nrates + " error=" + (string)GetLastError());
   if(nrates > 0)
      Emit("bars_first=" + TimeToString(rates[0].time) + " bars_last=" + TimeToString(rates[nrates-1].time));

   Emit("");
   Emit("=== window A (study year) " + InpOldFrom + " .. " + InpOldTo);
   ProbeWindow(sym, InpOldFrom, InpOldTo);

   Emit("");
   Emit("=== window B (recent) " + InpNewFrom + " .. " + InpNewTo);
   ProbeWindow(sym, InpNewFrom, InpNewTo);

   FileClose(g_handle);
   Print("PabSpreadProbe: done, verdict lines above");
}

//+------------------------------------------------------------------+
//| Walk a range in chunks and report what the ticks actually look   |
//| like, so density can be judged against a known yardstick.        |
//+------------------------------------------------------------------+
void ProbeWindow(string sym, string fromStr, string toStr)
{
   datetime from = StringToTime(fromStr);
   datetime to   = StringToTime(toStr);
   double   point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int      chunk = CHUNK_HOURS * 60 * 60;

   long   total      = 0;
   long   withBoth   = 0;   // bid and ask both populated
   long   withSpread = 0;   // ask > bid
   double minPts = 1e9, maxPts = 0.0, sumPts = 0.0;
   long   firstErr  = 0;
   int    calls     = 0;
   int    printed   = 0;

   for(datetime t = from; t < to; t += chunk)
     {
      datetime t2 = t + chunk;
      if(t2 > to) t2 = to;
      if(t2 <= t) break;

      MqlTick tk[];
      ArraySetAsSeries(tk, false);
      ResetLastError();
      // Times are ulong milliseconds since 1970, NOT datetime.
      int got = CopyTicksRange(sym, tk, COPY_TICKS_ALL,
                               (ulong)((long)t * 1000), (ulong)((long)t2 * 1000));
      calls++;
      if(got <= 0)
        {
         if(firstErr == 0) firstErr = GetLastError();
         continue;
        }

      for(int i = 0; i < got; i++)
        {
         total++;
         if(tk[i].ask > 0.0 && tk[i].bid > 0.0) withBoth++;
         if(tk[i].ask > tk[i].bid)
           {
            withSpread++;
            double p = (tk[i].ask - tk[i].bid) / point;
            if(p < minPts) minPts = p;
            if(p > maxPts) maxPts = p;
            sumPts += p;
            // A few verbatim samples are the evidence that bid/ask are real
            // broker prices rather than something the tester made up.
            if(printed < 5)
              {
               printed++;
               Emit("  sample tick " + (string)printed
                    + " time=" + TimeToString((datetime)(tk[i].time_msc / 1000))
                    + " bid=" + DoubleToString(tk[i].bid, _Digits)
                    + " ask=" + DoubleToString(tk[i].ask, _Digits)
                    + " spread_pts=" + DoubleToString(p, 1)
                    + " flags=" + (string)tk[i].flags);
              }
           }
        }
     }

   double days = (double)(to - from) / 86400.0;
   if(days <= 0.0) days = 1.0;

   Emit("  calls="                    + (string)calls);
   Emit("  tick_total="               + (string)total);
   Emit("  tick_with_bid_ask="        + (string)withBoth);
   Emit("  tick_with_positive_spread=" + (string)withSpread);
   Emit("  ticks_per_day="            + DoubleToString((double)total / days, 0));
   if(withSpread > 0)
     {
      Emit("  spread_points_min="  + DoubleToString(minPts, 2));
      Emit("  spread_points_mean=" + DoubleToString(sumPts / (double)withSpread, 2));
      Emit("  spread_points_max="  + DoubleToString(maxPts, 2));
     }
   else
      Emit("  spread_points_min=NONE_MEASURED");
   if(firstErr != 0)
      Emit("  first_error=" + (string)firstErr);

   // A real FX tick stream runs to tens of thousands of ticks a day. One per
   // minute is what the tester synthesises from minute OHLC when real ticks
   // are not in use. The two are nowhere near each other, so density decides
   // it, and a "measured" spread off a synthesised stream is not a measurement.
   double tpd = (double)total / days;
   string verdict;
   if(total == 0)
      verdict = "  VERDICT=NO_TICKS - CopyTicksRange returned nothing for this window";
   else if(withSpread == 0)
      verdict = "  VERDICT=TICKS_WITHOUT_SPREAD - ticks exist but ask<=bid on every one; no spread is measurable";
   else if(tpd >= 20000.0)
      verdict = "  VERDICT=REAL_TICKS_WITH_SPREAD - density is consistent with real ticks, not 1-minute generation";
   else if(tpd > 3000.0)
      verdict = "  VERDICT=AMBIGUOUS - denser than 1/minute but not enough to call real; inspect before trusting";
   else
      verdict = "  VERDICT=GENERATED_TICKS - density is about one per minute, i.e. synthesised from OHLC, not real";
   Emit(verdict);
}

void Emit(string line)
{
   FileWriteString(g_handle, line + "\n");
   Print("PabSpreadProbe: ", line);
}

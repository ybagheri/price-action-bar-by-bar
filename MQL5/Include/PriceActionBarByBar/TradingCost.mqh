//+------------------------------------------------------------------+
//|                                                TradingCost.mqh   |
//|                 Price Action Bar-by-Bar — Execution Cost Model  |
//|                                                                    |
//| PHASE 19. Every expectancy figure this project had produced up to  |
//| now was GROSS: no spread, no slippage, no commission. The        |
//| measured edge was a couple of hundredths of an R and realistic  |
//| costs on these markets are several times that, so no figure could |
//| be compared to a broker statement. This file is the one place    |
//| that decides what a trade costs.                                 |
//|                                                                    |
//| WHAT IS MEASURED AND WHAT IS ASSUMED                             |
//| Spread is measured, per bar, from the terminal's own record.     |
//| Slippage and commission cannot be measured from a bar series,    |
//| so they are inputs and are labelled as assumptions in every row  |
//| they touch. Anything that is assumed says so in the row, because |
//| a cost figure that hides its own provenance is not evidence.     |
//|                                                                    |
//| WHY EVERYTHING IS CONVERTED TO A PRICE DISTANCE                  |
//| Expectancy is reported in R, and R is defined by the setup's own |
//| stop distance, which is a price quantity. Converting a currency  |
//| commission into that unit needs the broker's tick value, and     |
//| that conversion is the step most easily got wrong: a commission  |
//| divided by a price distance produces a number with no units. So  |
//| the model stores cost as a PRICE DISTANCE and only then divides  |
//| by the stop distance. The research layer recomputes exactly this |
//| from the exported columns, which is what makes the number        |
//| auditable rather than asserted.                                  |
//|                                                                    |
//| DELIBERATELY CONSERVATIVE                                        |
//| The full spread is charged once per round trip, and slippage is  |
//| charged on BOTH sides. Charging half the spread (the textbook   |
//| mid-price convention) would halve the cost and flatter the      |
//| result; the entry fill is an ask while the levels were drawn on |
//| a bid chart, so the trader pays the whole thing.                 |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| The per-event cost model. Exported verbatim on every row so an   |
//| archived CSV states its own assumptions instead of requiring the |
//| reader to trust a script.                                         |
//+------------------------------------------------------------------+
struct SCostModel
  {
   double            spreadPrice;      // MEASURED: bar spread, as a price distance
   double            spreadPoints;     // MEASURED: the same spread in broker points
   bool              spreadMeasured;   // false when the configured fallback was used
   double            slippagePrice;    // ASSUMED: per side, as a price distance
   double            slippagePoints;   // ASSUMED: per side, in broker points
   double            commissionPrice;  // ASSUMED: round trip, as a price distance
   string            Model() const;
  };

//+------------------------------------------------------------------+
//| A self-describing label, written onto every exported row.         |
//|                                                                    |
//| "assumed" appears next to any number that is an input rather than |
//| a measurement, so a row cannot be quoted as a measured cost when  |
//| part of it was chosen by the person running the export.           |
//+------------------------------------------------------------------+
string SCostModel::Model() const
  {
   return(StringFormat("spread=%s%.2fpts/%.8f;slippage=%s%.2fpts/%.8f;commission=%s%.8f",
                       (spreadMeasured ? "" : "assumed:"), spreadPoints, spreadPrice,
                       (slippagePrice > 0.0 ? "assumed:" : ""), slippagePoints, slippagePrice,
                       (commissionPrice > 0.0 ? "assumed:" : ""), commissionPrice));
  }

//+------------------------------------------------------------------+
//| Stateless cost arithmetic, so both exporters and the regression  |
//| harness can exercise the same formulas.                          |
//+------------------------------------------------------------------+
class CTradingCost
  {
public:
   //--- price paid per round trip, in the instrument's own price units ----
   static double RoundTripCostPrice(const SCostModel &model)
     {
      return(model.spreadPrice + 2.0 * model.slippagePrice + model.commissionPrice);
     }

   //--- the same cost expressed in R, using the setup's own stop distance --
   // A zero stop distance yields 0.0 rather than a division by zero. A
   // NO TRADE row carries no levels at all, and 0.0 is the honest answer
   // for it: there is no trade, so there is nothing to pay.
   static double CostInR(const SCostModel &model, const double entry, const double stop)
     {
      double risk = MathAbs(entry - stop);
      if(risk <= 0.0)
         return(0.0);
      return(RoundTripCostPrice(model) / risk);
     }

   //--- turn a currency commission into a price distance -------------------
   // tickValue is the account-currency value of one tickSize move for ONE
   // lot, so the account-currency value of a `point` move for `lotSize`
   // lots is tickValue * (point / tickSize) * lotSize. Inverting that
   // converts a commission back into the price move that costs the same.
   // A zero commission, lot size, tick value, or tick size yields 0.0
   // rather than a division by zero, because an unavailable broker fact
   // must never become an infinite cost.
   static double CommissionPriceFromPerLot(const double commissionPerLotRoundTrip,
                                            const double lotSize,
                                            const double tickValue,
                                            const double tickSize)
     {
      if(commissionPerLotRoundTrip <= 0.0 || lotSize <= 0.0 ||
         tickValue <= 0.0 || tickSize <= 0.0)
         return(0.0);
      return((commissionPerLotRoundTrip / lotSize) * tickSize / tickValue);
     }
  };

//+------------------------------------------------------------------+
//| Broker facts the cost model needs, read once.                    |
//|                                                                    |
//| ReadSymbolCostFacts returns false when a property is unavailable |
//| rather than substituting a plausible default. A missing tick value |
//| used to make a commission free; here it makes the whole cost     |
//| model unavailable, and the caller must say so in the output.     |
//+------------------------------------------------------------------+
bool ReadSymbolCostFacts(const string symbol, double &point, double &tickValue,
                         double &tickSize, string &reason)
  {
   point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

   if(point <= 0.0 || tickSize <= 0.0)
     {
      reason = StringFormat("%s: SYMBOL_POINT or SYMBOL_TRADE_TICK_SIZE unavailable", symbol);
      return(false);
     }
   if(tickValue <= 0.0)
     {
      reason = StringFormat("%s: SYMBOL_TRADE_TICK_VALUE unavailable, so a currency "
                            "commission cannot be converted to a price distance", symbol);
      return(false);
     }
   reason = "";
   return(true);
  }
//+------------------------------------------------------------------+

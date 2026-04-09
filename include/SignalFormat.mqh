//+------------------------------------------------------------------+
//|                                              SignalFormat.mqh     |
//|                                              OkiSignal Project   |
//|  Format signal/close/report data as Discord embeds               |
//+------------------------------------------------------------------+
#ifndef SIGNAL_FORMAT_MQH
#define SIGNAL_FORMAT_MQH

#include "CommonDefs.mqh"
#include "DiscordWebhook.mqh"

//+------------------------------------------------------------------+
//| Format price with correct digits for the symbol                  |
//+------------------------------------------------------------------+
string FormatPrice(string symbol, double price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return DoubleToString(price, digits);
}

//+------------------------------------------------------------------+
//| Format pips with 1 decimal                                       |
//+------------------------------------------------------------------+
string FormatPips(double pips)
{
   return DoubleToString(pips, 1);
}

//+------------------------------------------------------------------+
//| Build new signal Discord embed JSON                              |
//+------------------------------------------------------------------+
string FormatSignalEmbed(SignalData &sig)
{
   string dirEmoji = (sig.direction == "BUY") ? "BUY" : "SELL";
   string title = "SIGNAL --- " + sig.strategy;
   int clr = (sig.direction == "BUY") ? COLOR_GREEN : COLOR_RED;

   double slPips  = PriceToPips(sig.symbol, sig.entry - sig.sl);
   double tp1Pips = PriceToPips(sig.symbol, sig.tp1 - sig.entry);
   double tp2Pips = (sig.tp2 > 0) ? PriceToPips(sig.symbol, sig.tp2 - sig.entry) : 0;

   string slSign  = (sig.direction == "BUY") ? "-" : "-";
   string tpSign  = "+";

   string fields =
      EmbedField("Pair", sig.symbol) + "," +
      EmbedField("Direction", dirEmoji) + "," +
      EmbedField("Entry", FormatPrice(sig.symbol, sig.entry)) + "," +
      EmbedField("SL", FormatPrice(sig.symbol, sig.sl) +
                 " (" + slSign + FormatPips(slPips) + " pips)") + "," +
      EmbedField("TP1", FormatPrice(sig.symbol, sig.tp1) +
                 " (+" + FormatPips(tp1Pips) + " pips)") + ",";

   if(sig.tp2 > 0)
      fields += EmbedField("TP2", FormatPrice(sig.symbol, sig.tp2) +
                " (+" + FormatPips(tp2Pips) + " pips)") + ",";

   fields += EmbedField("Volume", DoubleToString(sig.volume, 2));

   return BuildEmbed(title, clr, fields, "", "");
}

//+------------------------------------------------------------------+
//| Build close result Discord embed JSON                            |
//+------------------------------------------------------------------+
string FormatCloseEmbed(CloseData &cd)
{
   string resultText;
   int clr;

   if(cd.profit >= 0)
   {
      resultText = "+" + FormatPips(cd.profitPips) + " pips / +$" +
                   DoubleToString(cd.profit, 2);
      clr = COLOR_GREEN;
   }
   else
   {
      resultText = FormatPips(cd.profitPips) + " pips / $" +
                   DoubleToString(cd.profit, 2);
      clr = COLOR_RED;
   }

   string title = "CLOSED --- " + cd.strategy + " (" + cd.closeReason + ")";

   //--- Duration formatting
   string durationStr;
   if(cd.durationMin >= 60)
      durationStr = IntegerToString(cd.durationMin / 60) + "h " +
                    IntegerToString(cd.durationMin % 60) + "m";
   else
      durationStr = IntegerToString(cd.durationMin) + "m";

   //--- R:R calculation
   double slDist = PriceToPips(cd.symbol, cd.entry - cd.closePrice);
   double entrySlDist = PriceToPips(cd.symbol,
      (cd.direction == "BUY") ? cd.entry - cd.closePrice : cd.closePrice - cd.entry);
   // Simplified: just show pips result

   string fields =
      EmbedField("Pair", cd.symbol) + "," +
      EmbedField("Result", resultText) + "," +
      EmbedField("Duration", durationStr) + "," +
      EmbedField("Close", cd.closeReason) + "," +
      EmbedField("Entry", FormatPrice(cd.symbol, cd.entry)) + "," +
      EmbedField("Exit", FormatPrice(cd.symbol, cd.closePrice));

   return BuildEmbed(title, clr, fields, "", "");
}

//+------------------------------------------------------------------+
//| Build weekly report embed JSON                                   |
//+------------------------------------------------------------------+
string FormatWeeklyEmbed(string weekEnding, int totalTrades, int wins,
                         int losses, double totalPips, double profitFactor,
                         string bestStrategy, string worstStrategy,
                         string pairBreakdown)
{
   double winRate = (totalTrades > 0) ?
      (double)wins / totalTrades * 100.0 : 0;

   string title = "WEEKLY REPORT --- " + weekEnding;

   string fields =
      EmbedField("Trades", IntegerToString(totalTrades)) + "," +
      EmbedField("Win Rate",
         DoubleToString(winRate, 1) + "% (" +
         IntegerToString(wins) + "W/" +
         IntegerToString(losses) + "L)") + "," +
      EmbedField("Total Pips",
         (totalPips >= 0 ? "+" : "") + FormatPips(totalPips)) + "," +
      EmbedField("Profit Factor",
         DoubleToString(profitFactor, 2)) + "," +
      EmbedField("Best Strategy", bestStrategy) + "," +
      EmbedField("Worst Strategy", worstStrategy);

   if(pairBreakdown != "")
      fields += "," + EmbedField("Pair Breakdown", pairBreakdown, false);

   return BuildEmbed(title, COLOR_BLUE, fields, "OkiSignal Weekly Report", "");
}

#endif

//+------------------------------------------------------------------+
//|                                           ReportGenerator.mqh    |
//|                                              OkiSignal Project   |
//|  Aggregation and stats calculation from trade history            |
//+------------------------------------------------------------------+
#ifndef REPORT_GENERATOR_MQH
#define REPORT_GENERATOR_MQH

#include "CommonDefs.mqh"

//--- Per-strategy stats
struct StrategyStats
{
   string name;
   int    magic;
   int    trades;
   int    wins;
   int    losses;
   double grossProfit;
   double grossLoss;
   double totalPips;
   double profitFactor;
   double winRate;
};

//--- Per-pair stats
struct PairStats
{
   string symbol;
   int    trades;
   int    wins;
   double totalPips;
   double winRate;
};

//+------------------------------------------------------------------+
//| Collect stats from deal history for a date range                 |
//+------------------------------------------------------------------+
void CollectStats(datetime from, datetime to,
                  StrategyStats &stratStats[], int &stratCount,
                  PairStats &pairStats[], int &pairCount,
                  int &totalTrades, int &totalWins, int &totalLosses,
                  double &totalPips, double &totalProfit, double &totalLoss)
{
   //--- Initialize strategy stats
   stratCount = 5;
   ArrayResize(stratStats, stratCount);

   int magics[] = {101, 102, 103, 104, 105};
   string names[] = {"SessionBreakout", "MTFStructure", "RSIDivergence",
                     "EMA_ADR", "OBRetest"};

   for(int i = 0; i < stratCount; i++)
   {
      stratStats[i].name = names[i];
      stratStats[i].magic = magics[i];
      stratStats[i].trades = 0;
      stratStats[i].wins = 0;
      stratStats[i].losses = 0;
      stratStats[i].grossProfit = 0;
      stratStats[i].grossLoss = 0;
      stratStats[i].totalPips = 0;
   }

   //--- Initialize pair stats
   pairCount = ArraySize(g_allowedSymbols);
   ArrayResize(pairStats, pairCount);
   for(int i = 0; i < pairCount; i++)
   {
      pairStats[i].symbol = g_allowedSymbols[i];
      pairStats[i].trades = 0;
      pairStats[i].wins = 0;
      pairStats[i].totalPips = 0;
   }

   totalTrades = 0;
   totalWins = 0;
   totalLosses = 0;
   totalPips = 0;
   totalProfit = 0;
   totalLoss = 0;

   //--- Select history
   if(!HistorySelect(from, to)) return;

   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      int magic = (int)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(!IsOkiMagic(magic)) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT) continue; // only count closes

      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double priceOpen = HistoryDealGetDouble(ticket, DEAL_PRICE);

      //--- Calculate pips (approximate from profit)
      double pips = 0;
      double pipSz = PipSize(symbol);
      if(pipSz > 0)
      {
         double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         double tickVal = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSz  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tickVal > 0 && tickSz > 0 && volume > 0)
         {
            double pointVal = tickVal * SymbolInfoDouble(symbol, SYMBOL_POINT) / tickSz;
            if(pointVal > 0)
               pips = profit / (volume * pointVal * pipSz /
                      SymbolInfoDouble(symbol, SYMBOL_POINT));
         }
      }

      bool isWin = (profit > 0);

      totalTrades++;
      if(isWin) totalWins++;
      else totalLosses++;
      totalPips += pips;
      if(profit > 0) totalProfit += profit;
      else totalLoss += MathAbs(profit);

      //--- Update strategy stats
      for(int s = 0; s < stratCount; s++)
      {
         if(stratStats[s].magic == magic)
         {
            stratStats[s].trades++;
            if(isWin) stratStats[s].wins++;
            else stratStats[s].losses++;
            if(profit > 0) stratStats[s].grossProfit += profit;
            else stratStats[s].grossLoss += MathAbs(profit);
            stratStats[s].totalPips += pips;
            break;
         }
      }

      //--- Update pair stats
      for(int p = 0; p < pairCount; p++)
      {
         if(pairStats[p].symbol == symbol)
         {
            pairStats[p].trades++;
            if(isWin) pairStats[p].wins++;
            pairStats[p].totalPips += pips;
            break;
         }
      }
   }

   //--- Calculate derived stats
   for(int s = 0; s < stratCount; s++)
   {
      if(stratStats[s].trades > 0)
         stratStats[s].winRate = (double)stratStats[s].wins /
                                 stratStats[s].trades * 100.0;
      if(stratStats[s].grossLoss > 0)
         stratStats[s].profitFactor = stratStats[s].grossProfit /
                                      stratStats[s].grossLoss;
      else if(stratStats[s].grossProfit > 0)
         stratStats[s].profitFactor = 999.0;
   }

   for(int p = 0; p < pairCount; p++)
   {
      if(pairStats[p].trades > 0)
         pairStats[p].winRate = (double)pairStats[p].wins /
                                pairStats[p].trades * 100.0;
   }
}

//+------------------------------------------------------------------+
//| Find best/worst strategy by total pips                           |
//+------------------------------------------------------------------+
void FindBestWorst(StrategyStats &stats[], int count,
                   string &best, string &worst)
{
   best = "-";
   worst = "-";
   double bestPips = -999999;
   double worstPips = 999999;

   for(int i = 0; i < count; i++)
   {
      if(stats[i].trades == 0) continue;

      if(stats[i].totalPips > bestPips)
      {
         bestPips = stats[i].totalPips;
         best = stats[i].name + " (+" + DoubleToString(stats[i].totalPips, 1) + ")";
      }
      if(stats[i].totalPips < worstPips)
      {
         worstPips = stats[i].totalPips;
         worst = stats[i].name + " (" + DoubleToString(stats[i].totalPips, 1) + ")";
      }
   }
}

//+------------------------------------------------------------------+
//| Build pair breakdown string for embed                            |
//+------------------------------------------------------------------+
string BuildPairBreakdown(PairStats &stats[], int count)
{
   string result = "";
   for(int i = 0; i < count; i++)
   {
      if(stats[i].trades == 0) continue;
      if(result != "") result += "\\n";
      result += stats[i].symbol + ": " +
                IntegerToString(stats[i].trades) + "T / " +
                DoubleToString(stats[i].winRate, 0) + "% / " +
                (stats[i].totalPips >= 0 ? "+" : "") +
                DoubleToString(stats[i].totalPips, 1) + "p";
   }
   return result;
}

#endif

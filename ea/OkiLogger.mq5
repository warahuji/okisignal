//+------------------------------------------------------------------+
//|                                                 OkiLogger.mq5    |
//|                                              OkiSignal Project   |
//|  Logger EA: monitors all strategy trades, records & distributes  |
//|  Attach to any single chart. Does NOT trade.                     |
//+------------------------------------------------------------------+
#property copyright "OkiSignal"
#property version   "1.00"
#property strict

#include "../include/CommonDefs.mqh"
#include "../include/ATRUtils.mqh"
#include "../include/DiscordWebhook.mqh"
#include "../include/SignalFormat.mqh"
#include "../include/SheetsLogger.mqh"
#include "../include/ReportGenerator.mqh"

//--- Input Parameters
input string InpDiscordWebhook   = "";      // Discord Webhook URL (signals)
input string InpDiscordReportWH  = "";      // Discord Webhook URL (reports)
input string InpSheetsWebhook    = "";      // Google Sheets Webhook URL
input string InpCSVPath          = "OkiSignal\\okisignal";  // CSV base path
input int    InpReportDay        = 5;       // Weekly report day (5=Friday)
input int    InpReportHour       = 20;      // Weekly report hour (server time)

//--- Pending signal queue (for SL/TP timing issue)
#define MAX_QUEUE 10

struct PendingSignal
{
   ulong    dealTicket;
   int      magic;
   string   symbol;
   long     dealType;
   double   price;
   double   volume;
   datetime queueTime;
   int      retries;
};

PendingSignal g_queue[];
int           g_queueSize;

//--- Track known positions to detect closes
struct TrackedPosition
{
   ulong    ticket;
   int      magic;
   string   symbol;
   string   direction;
   double   entry;
   double   sl;
   double   tp;
   double   volume;
   datetime openTime;
};

TrackedPosition g_tracked[];
int             g_trackedCount;

//--- Weekly report flag
datetime g_lastReportDate;

//+------------------------------------------------------------------+
int OnInit()
{
   ArrayResize(g_queue, 0);
   g_queueSize = 0;
   ArrayResize(g_tracked, 0);
   g_trackedCount = 0;
   g_lastReportDate = 0;

   //--- Set 1-second timer for queue processing
   EventSetTimer(1);

   //--- Scan existing positions on startup
   ScanExistingPositions();

   Print("OkiLogger initialized. Discord=",
         (InpDiscordWebhook != "" ? "YES" : "NO"),
         " Sheets=", (InpSheetsWebhook != "" ? "YES" : "NO"));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Scan existing open positions on startup                          |
//+------------------------------------------------------------------+
void ScanExistingPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      if(!IsOkiMagic(magic)) continue;

      TrackPosition(ticket);
   }
   Print("OkiLogger: tracking ", g_trackedCount, " existing positions");
}

//+------------------------------------------------------------------+
//| Add position to tracked list                                     |
//+------------------------------------------------------------------+
void TrackPosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;

   //--- Check not already tracked
   for(int i = 0; i < g_trackedCount; i++)
   {
      if(g_tracked[i].ticket == ticket) return;
   }

   TrackedPosition tp;
   tp.ticket    = ticket;
   tp.magic     = (int)PositionGetInteger(POSITION_MAGIC);
   tp.symbol    = PositionGetString(POSITION_SYMBOL);
   tp.direction = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                  "BUY" : "SELL";
   tp.entry     = PositionGetDouble(POSITION_PRICE_OPEN);
   tp.sl        = PositionGetDouble(POSITION_SL);
   tp.tp        = PositionGetDouble(POSITION_TP);
   tp.volume    = PositionGetDouble(POSITION_VOLUME);
   tp.openTime  = (datetime)PositionGetInteger(POSITION_TIME);

   ArrayResize(g_tracked, g_trackedCount + 1);
   g_tracked[g_trackedCount] = tp;
   g_trackedCount++;
}

//+------------------------------------------------------------------+
//| Remove position from tracked list                                |
//+------------------------------------------------------------------+
void UntrackPosition(ulong ticket)
{
   for(int i = 0; i < g_trackedCount; i++)
   {
      if(g_tracked[i].ticket == ticket)
      {
         //--- Shift remaining elements
         for(int j = i; j < g_trackedCount - 1; j++)
            g_tracked[j] = g_tracked[j + 1];
         g_trackedCount--;
         ArrayResize(g_tracked, g_trackedCount);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Find tracked position by ticket                                  |
//+------------------------------------------------------------------+
int FindTracked(ulong ticket)
{
   for(int i = 0; i < g_trackedCount; i++)
   {
      if(g_tracked[i].ticket == ticket) return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| OnTradeTransaction: detect new entries and closes                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = trans.deal;
   if(dealTicket == 0) return;

   //--- Select the deal in history
   if(!HistoryDealSelect(dealTicket)) return;

   int magic = (int)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(!IsOkiMagic(magic)) return;

   long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   long dealType  = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
   string symbol  = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   double price   = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   double volume  = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);

   if(dealEntry == DEAL_ENTRY_IN)
   {
      //--- New position: queue for processing (SL/TP might not be set yet)
      QueueNewSignal(dealTicket, magic, symbol, dealType, price, volume);
   }
   else if(dealEntry == DEAL_ENTRY_OUT)
   {
      //--- Position closed (partial or full)
      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      ProcessClose(magic, symbol, dealType, price, volume, profit, dealTicket);
   }
}

//+------------------------------------------------------------------+
//| Queue a new signal for delayed processing                        |
//+------------------------------------------------------------------+
void QueueNewSignal(ulong dealTicket, int magic, string symbol,
                    long dealType, double price, double volume)
{
   if(g_queueSize >= MAX_QUEUE) return;

   PendingSignal ps;
   ps.dealTicket = dealTicket;
   ps.magic      = magic;
   ps.symbol     = symbol;
   ps.dealType   = dealType;
   ps.price      = price;
   ps.volume     = volume;
   ps.queueTime  = TimeCurrent();
   ps.retries    = 0;

   ArrayResize(g_queue, g_queueSize + 1);
   g_queue[g_queueSize] = ps;
   g_queueSize++;
}

//+------------------------------------------------------------------+
//| Process queued signals (called from OnTimer)                     |
//+------------------------------------------------------------------+
void ProcessQueue()
{
   for(int i = g_queueSize - 1; i >= 0; i--)
   {
      PendingSignal ps = g_queue[i];

      //--- Try to find the position and read SL/TP
      double sl = 0, tp = 0;
      bool found = false;

      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         ulong posTicket = PositionGetTicket(p);
         if(posTicket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) == ps.magic &&
            PositionGetString(POSITION_SYMBOL) == ps.symbol)
         {
            sl = PositionGetDouble(POSITION_SL);
            tp = PositionGetDouble(POSITION_TP);
            found = true;

            //--- Track this position
            TrackPosition(posTicket);
            break;
         }
      }

      //--- If SL/TP still 0 and < 5 retries, keep in queue
      if(found && sl == 0 && tp == 0 && ps.retries < 5)
      {
         g_queue[i].retries++;
         continue;
      }

      //--- Process the signal
      ProcessNewSignal(ps, sl, tp);

      //--- Remove from queue
      for(int j = i; j < g_queueSize - 1; j++)
         g_queue[j] = g_queue[j + 1];
      g_queueSize--;
      ArrayResize(g_queue, g_queueSize);
   }
}

//+------------------------------------------------------------------+
//| Process a confirmed new signal                                   |
//+------------------------------------------------------------------+
void ProcessNewSignal(PendingSignal &ps, double sl, double tp)
{
   SignalData sig;
   sig.magic     = ps.magic;
   sig.strategy  = StrategyName(ps.magic);
   sig.symbol    = ps.symbol;
   sig.direction = (ps.dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";
   sig.entry     = ps.price;
   sig.sl        = sl;
   sig.tp1       = tp;
   sig.tp2       = 0; // TP2 not known at this point
   sig.volume    = ps.volume;
   sig.time      = ps.queueTime;
   sig.ticket    = ps.dealTicket;

   Print("[Logger] NEW: ", sig.strategy, " ", sig.direction, " ", sig.symbol,
         " @ ", sig.entry, " SL=", sig.sl, " TP=", sig.tp1);

   //--- Discord
   string embed = FormatSignalEmbed(sig);
   SendDiscordWebhook(InpDiscordWebhook, embed);

   //--- Google Sheets
   SheetsLogSignal(InpSheetsWebhook, sig);

   //--- CSV
   WriteCSVEntry(sig);
}

//+------------------------------------------------------------------+
//| Process a position close                                         |
//+------------------------------------------------------------------+
void ProcessClose(int magic, string symbol, long dealType,
                  double closePrice, double volume, double profit,
                  ulong dealTicket)
{
   //--- Find tracked position
   int trackedIdx = -1;
   for(int i = 0; i < g_trackedCount; i++)
   {
      if(g_tracked[i].magic == magic && g_tracked[i].symbol == symbol)
      {
         trackedIdx = i;
         break;
      }
   }

   CloseData cd;
   cd.magic       = magic;
   cd.strategy    = StrategyName(magic);
   cd.symbol      = symbol;
   cd.closePrice  = closePrice;
   cd.profit      = profit;
   cd.volume      = volume;
   cd.ticket      = dealTicket;

   if(trackedIdx >= 0)
   {
      cd.direction   = g_tracked[trackedIdx].direction;
      cd.entry       = g_tracked[trackedIdx].entry;
      cd.openTime    = g_tracked[trackedIdx].openTime;
      cd.durationMin = (int)(TimeCurrent() - cd.openTime) / 60;
   }
   else
   {
      cd.direction   = (dealType == DEAL_TYPE_SELL) ? "BUY" : "SELL"; // close is opposite
      cd.entry       = 0;
      cd.openTime    = 0;
      cd.durationMin = 0;
   }

   //--- Calculate pips
   cd.profitPips = (cd.entry > 0) ?
      PriceToPips(symbol, closePrice - cd.entry) : 0;

   //--- Determine close reason
   if(trackedIdx >= 0)
   {
      double tp = g_tracked[trackedIdx].tp;
      double sl = g_tracked[trackedIdx].sl;
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      if(tp > 0 && MathAbs(closePrice - tp) < PipSize(symbol))
         cd.closeReason = "TP";
      else if(sl > 0 && MathAbs(closePrice - sl) < PipSize(symbol))
         cd.closeReason = "SL";
      else if(profit >= 0 && volume < g_tracked[trackedIdx].volume)
         cd.closeReason = "TP1";
      else
         cd.closeReason = "Manual";
   }
   else
      cd.closeReason = "Unknown";

   Print("[Logger] CLOSE: ", cd.strategy, " ", cd.symbol,
         " ", cd.closeReason, " P/L=", DoubleToString(cd.profit, 2),
         " (", DoubleToString(cd.profitPips, 1), " pips)");

   //--- Discord
   string embed = FormatCloseEmbed(cd);
   SendDiscordWebhook(InpDiscordWebhook, embed);

   //--- Google Sheets
   SheetsLogClose(InpSheetsWebhook, cd);

   //--- CSV
   WriteCSVExit(cd);

   //--- Remove from tracking if fully closed
   bool posStillOpen = false;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong posTicket = PositionGetTicket(p);
      if(posTicket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == magic &&
         PositionGetString(POSITION_SYMBOL) == symbol)
      {
         posStillOpen = true;
         //--- Update tracked volume/TP (after partial close)
         if(trackedIdx >= 0)
         {
            g_tracked[trackedIdx].volume = PositionGetDouble(POSITION_VOLUME);
            g_tracked[trackedIdx].tp = PositionGetDouble(POSITION_TP);
            g_tracked[trackedIdx].sl = PositionGetDouble(POSITION_SL);
         }
         break;
      }
   }

   if(!posStillOpen && trackedIdx >= 0)
      UntrackPosition(g_tracked[trackedIdx].ticket);
}

//+------------------------------------------------------------------+
//| Write entry to CSV                                               |
//+------------------------------------------------------------------+
void WriteCSVEntry(SignalData &sig)
{
   string filename = InpCSVPath + "_entries.csv";
   int handle = FileOpen(filename, FILE_WRITE | FILE_READ | FILE_CSV |
                         FILE_COMMON | FILE_SHARE_READ, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("[CSV] Failed to open ", filename);
      return;
   }

   //--- Write header if new file
   if(FileSize(handle) == 0)
   {
      FileWrite(handle, "DateTime", "Ticket", "Magic", "Strategy",
                "Symbol", "Direction", "Entry", "SL", "TP1", "Volume");
   }

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle,
      TimeToString(sig.time, TIME_DATE | TIME_SECONDS),
      IntegerToString((int)sig.ticket),
      IntegerToString(sig.magic),
      sig.strategy,
      sig.symbol,
      sig.direction,
      DoubleToString(sig.entry, 5),
      DoubleToString(sig.sl, 5),
      DoubleToString(sig.tp1, 5),
      DoubleToString(sig.volume, 2));

   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Write exit to CSV                                                |
//+------------------------------------------------------------------+
void WriteCSVExit(CloseData &cd)
{
   string filename = InpCSVPath + "_exits.csv";
   int handle = FileOpen(filename, FILE_WRITE | FILE_READ | FILE_CSV |
                         FILE_COMMON | FILE_SHARE_READ, ',');
   if(handle == INVALID_HANDLE)
   {
      Print("[CSV] Failed to open ", filename);
      return;
   }

   //--- Write header if new file
   if(FileSize(handle) == 0)
   {
      FileWrite(handle, "DateTime", "Ticket", "Magic", "Strategy",
                "Symbol", "Direction", "Entry", "ClosePrice",
                "Profit", "ProfitPips", "CloseReason",
                "DurationMin", "Volume");
   }

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      IntegerToString((int)cd.ticket),
      IntegerToString(cd.magic),
      cd.strategy,
      cd.symbol,
      cd.direction,
      DoubleToString(cd.entry, 5),
      DoubleToString(cd.closePrice, 5),
      DoubleToString(cd.profit, 2),
      DoubleToString(cd.profitPips, 1),
      cd.closeReason,
      IntegerToString(cd.durationMin),
      DoubleToString(cd.volume, 2));

   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Timer: process queue + check weekly report                       |
//+------------------------------------------------------------------+
void OnTimer()
{
   //--- Process pending signal queue
   ProcessQueue();

   //--- Check weekly report schedule
   CheckWeeklyReport();
}

//+------------------------------------------------------------------+
//| Check if it's time for weekly report                             |
//+------------------------------------------------------------------+
void CheckWeeklyReport()
{
   if(IsBacktest()) return;

   MqlDateTime dt;
   TimeCurrent(dt);

   if(dt.day_of_week != InpReportDay) return;
   if(dt.hour != InpReportHour) return;

   //--- Only once per week
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today <= g_lastReportDate) return;
   g_lastReportDate = today;

   GenerateWeeklyReport();
}

//+------------------------------------------------------------------+
//| Generate and send weekly report                                  |
//+------------------------------------------------------------------+
void GenerateWeeklyReport()
{
   //--- Last 7 days
   datetime to = TimeCurrent();
   datetime from = to - 7 * 24 * 60 * 60;

   StrategyStats stratStats[];
   PairStats pairStats[];
   int stratCount, pairCount;
   int totalTrades, totalWins, totalLosses;
   double totalPips, totalProfit, totalLoss;

   CollectStats(from, to, stratStats, stratCount, pairStats, pairCount,
                totalTrades, totalWins, totalLosses, totalPips,
                totalProfit, totalLoss);

   if(totalTrades == 0)
   {
      Print("[Logger] Weekly report: no trades this week");
      return;
   }

   double pf = (totalLoss > 0) ? totalProfit / totalLoss : 999.0;

   string best, worst;
   FindBestWorst(stratStats, stratCount, best, worst);

   string pairBreakdown = BuildPairBreakdown(pairStats, pairCount);
   string weekEnding = TimeToString(to, TIME_DATE);

   //--- Discord
   string reportWebhook = (InpDiscordReportWH != "") ?
                           InpDiscordReportWH : InpDiscordWebhook;
   string embed = FormatWeeklyEmbed(weekEnding, totalTrades, totalWins,
                                     totalLosses, totalPips, pf,
                                     best, worst, pairBreakdown);
   SendDiscordWebhook(reportWebhook, embed);

   //--- Google Sheets
   double winRate = (double)totalWins / totalTrades * 100.0;
   SheetsLogWeekly(InpSheetsWebhook, weekEnding, totalTrades,
                   winRate, totalPips, pf, best, worst);

   Print("[Logger] Weekly report sent: ", totalTrades, " trades, ",
         DoubleToString(winRate, 1), "% WR, ",
         DoubleToString(totalPips, 1), " pips");
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Logger does not trade. OnTimer handles all work.
}
//+------------------------------------------------------------------+

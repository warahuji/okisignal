//+------------------------------------------------------------------+
//|                                              SMC_FVG_Multi.mq5   |
//|                                              OkiSignal Project   |
//|  Multi-symbol EA: Structure Break + Fair Value Gap entry         |
//|  Attach to one chart -> trades multiple pairs via OnTimer()      |
//+------------------------------------------------------------------+
#property copyright "OkiSignal"
#property version   "1.00"
#property strict

#include <OkiSignal/CommonDefs.mqh>
#include <OkiSignal/ATRUtils.mqh>
#include <OkiSignal/SignalFormat.mqh>
#include <OkiSignal/DiscordWebhook.mqh>

//--- Input Parameters (shared)
input string   InpWebhookUrl    = "";              // Discord Webhook URL
input double   InpRiskPercent   = 1.0;             // Risk %
input double   InpTP1ClosePct   = 50.0;            // TP1 partial close %
input int      InpATRPeriod     = 14;              // ATR period
input int      InpMagicBase     = 106;             // Magic base (per-pair +index)
input bool     InpTradeEnabled  = true;            // Live trade ON/OFF

//--- Per-symbol parameters (CSV, order matches InpSymbols)
input string   InpSymbols       = "USDJPY#,EURUSD#,GBPUSD#,AUDUSD#,GBPJPY#,EURJPY#,AUDJPY#";
input string   InpSwingLens     = "4,8,6,7,7,5,7";
input string   InpSLMults       = "0.75,2.50,1.00,2.25,2.50,2.00,2.50";
input string   InpTP1Mults      = "2.50,2.25,2.50,1.75,2.00,2.50,2.25";
input string   InpTP2Mults      = "3.5,4.5,2.5,5.0,5.0,4.0,3.0";
input string   InpADRMaxRatios  = "0.5,0.7,0.6,0.5,0.6,0.9,0.6";
input string   InpSessionStarts = "6,14,14,14,10,10,6";
input string   InpSessionEnds   = "18,19,19,22,16,17,17";

//--- FVG Zone structure
struct FVGZone
{
   double upper;
   double lower;
   bool   isValid;
};

//--- Per-symbol state
struct SymbolState
{
   string   symbol;
   int      swingLen;
   double   slMult, tp1Mult, tp2Mult, adrMaxRatio;
   int      sessionStart, sessionEnd;
   int      magic;
   // Swing / BOS / FVG
   double   lastSH, lastSL;
   bool     bullishBOS, bearishBOS;
   FVGZone  bullishFVG, bearishFVG;
   // TP management
   double   tp1Level, tp2Level, tp1Lot;
   // New bar detection
   datetime lastBarTime;
};

//--- Globals
SymbolState g_states[];
int         g_numSymbols = 0;

//+------------------------------------------------------------------+
//| CSV parsing helpers                                              |
//+------------------------------------------------------------------+
int ParseCSVString(string csv, string &arr[])
{
   string parts[];
   int n = StringSplit(csv, ',', parts);
   ArrayResize(arr, n);
   for(int i = 0; i < n; i++)
   {
      arr[i] = parts[i];
      StringTrimLeft(arr[i]);
      StringTrimRight(arr[i]);
   }
   return n;
}

int ParseCSVInt(string csv, int &arr[])
{
   string parts[];
   int n = StringSplit(csv, ',', parts);
   ArrayResize(arr, n);
   for(int i = 0; i < n; i++)
   {
      StringTrimLeft(parts[i]);
      StringTrimRight(parts[i]);
      arr[i] = (int)StringToInteger(parts[i]);
   }
   return n;
}

int ParseCSVDouble(string csv, double &arr[])
{
   string parts[];
   int n = StringSplit(csv, ',', parts);
   ArrayResize(arr, n);
   for(int i = 0; i < n; i++)
   {
      StringTrimLeft(parts[i]);
      StringTrimRight(parts[i]);
      arr[i] = StringToDouble(parts[i]);
   }
   return n;
}

//+------------------------------------------------------------------+
int OnInit()
{
   //--- Parse symbol list
   string symbols[];
   g_numSymbols = ParseCSVString(InpSymbols, symbols);
   if(g_numSymbols <= 0)
   {
      Print("ERROR: No symbols specified");
      return INIT_FAILED;
   }

   //--- Parse per-symbol parameters
   int    swingLens[];
   double slMults[], tp1Mults[], tp2Mults[], adrMaxRatios[];
   int    sessStarts[], sessEnds[];

   ParseCSVInt(InpSwingLens, swingLens);
   ParseCSVDouble(InpSLMults, slMults);
   ParseCSVDouble(InpTP1Mults, tp1Mults);
   ParseCSVDouble(InpTP2Mults, tp2Mults);
   ParseCSVDouble(InpADRMaxRatios, adrMaxRatios);
   ParseCSVInt(InpSessionStarts, sessStarts);
   ParseCSVInt(InpSessionEnds, sessEnds);

   //--- Validate array sizes
   if(ArraySize(swingLens)    != g_numSymbols ||
      ArraySize(slMults)      != g_numSymbols ||
      ArraySize(tp1Mults)     != g_numSymbols ||
      ArraySize(tp2Mults)     != g_numSymbols ||
      ArraySize(adrMaxRatios) != g_numSymbols ||
      ArraySize(sessStarts)   != g_numSymbols ||
      ArraySize(sessEnds)     != g_numSymbols)
   {
      Print("ERROR: Parameter array sizes don't match symbol count (",
            g_numSymbols, ")");
      return INIT_FAILED;
   }

   //--- Build states
   ArrayResize(g_states, g_numSymbols);
   for(int i = 0; i < g_numSymbols; i++)
   {
      g_states[i].symbol       = symbols[i];
      g_states[i].swingLen     = swingLens[i];
      g_states[i].slMult       = slMults[i];
      g_states[i].tp1Mult      = tp1Mults[i];
      g_states[i].tp2Mult      = tp2Mults[i];
      g_states[i].adrMaxRatio  = adrMaxRatios[i];
      g_states[i].sessionStart = sessStarts[i];
      g_states[i].sessionEnd   = sessEnds[i];
      g_states[i].magic        = InpMagicBase + i;

      g_states[i].lastSH      = 0;
      g_states[i].lastSL      = 0;
      g_states[i].bullishBOS  = false;
      g_states[i].bearishBOS  = false;
      g_states[i].bullishFVG.isValid = false;
      g_states[i].bearishFVG.isValid = false;
      g_states[i].tp1Level    = 0;
      g_states[i].tp2Level    = 0;
      g_states[i].tp1Lot      = 0;
      g_states[i].lastBarTime = 0;

      Print("SMC_FVG_Multi[", i, "]: ", symbols[i],
            " magic=", g_states[i].magic,
            " swing=", swingLens[i],
            " SL=", slMults[i], "x",
            " TP1=", tp1Mults[i], "x",
            " TP2=", tp2Mults[i], "x",
            " session=", sessStarts[i], "-", sessEnds[i]);
   }

   EventSetTimer(1);
   Print("SMC_FVG_Multi initialized: ", g_numSymbols, " symbols");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| New bar detection per symbol (uses SymbolState.lastBarTime)      |
//+------------------------------------------------------------------+
bool IsNewBarMulti(SymbolState &st)
{
   datetime currentBarTime = iTime(st.symbol, PERIOD_M15, 0);
   if(currentBarTime == 0) return false;

   if(currentBarTime != st.lastBarTime)
   {
      st.lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Swing High detection for a specific symbol                       |
//+------------------------------------------------------------------+
bool IsSwingHigh(string symbol, int shift, int swingLen)
{
   double h = iHigh(symbol, PERIOD_M15, shift);
   if(h == 0) return false;

   for(int i = 1; i <= swingLen; i++)
   {
      if(iHigh(symbol, PERIOD_M15, shift + i) >= h) return false;
      if(iHigh(symbol, PERIOD_M15, shift - i) >= h) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Swing Low detection for a specific symbol                        |
//+------------------------------------------------------------------+
bool IsSwingLow(string symbol, int shift, int swingLen)
{
   double l = iLow(symbol, PERIOD_M15, shift);
   if(l == 0) return false;

   for(int i = 1; i <= swingLen; i++)
   {
      if(iLow(symbol, PERIOD_M15, shift + i) <= l) return false;
      if(iLow(symbol, PERIOD_M15, shift - i) <= l) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Update structure (swing points + BOS) for one symbol             |
//+------------------------------------------------------------------+
void UpdateStructure(SymbolState &st)
{
   int checkBar = st.swingLen;

   if(IsSwingHigh(st.symbol, checkBar, st.swingLen))
   {
      st.lastSH = iHigh(st.symbol, PERIOD_M15, checkBar);
      Print(st.symbol, " Swing High: ", st.lastSH);
   }

   if(IsSwingLow(st.symbol, checkBar, st.swingLen))
   {
      st.lastSL = iLow(st.symbol, PERIOD_M15, checkBar);
      Print(st.symbol, " Swing Low: ", st.lastSL);
   }

   if(st.lastSH > 0 && st.lastSL > 0)
   {
      double close1 = iClose(st.symbol, PERIOD_M15, 1);

      if(close1 > st.lastSH && !st.bullishBOS)
      {
         st.bullishBOS = true;
         st.bearishBOS = false;
         st.bearishFVG.isValid = false;
         Print(st.symbol, " Bullish BOS: ", close1, " > SH ", st.lastSH);
      }
      else if(close1 < st.lastSL && !st.bearishBOS)
      {
         st.bearishBOS = true;
         st.bullishBOS = false;
         st.bullishFVG.isValid = false;
         Print(st.symbol, " Bearish BOS: ", close1, " < SL ", st.lastSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Detect FVG for one symbol                                        |
//+------------------------------------------------------------------+
void DetectFVG(SymbolState &st)
{
   double high0 = iHigh(st.symbol, PERIOD_M15, 0);
   double low0  = iLow(st.symbol, PERIOD_M15, 0);
   double high2 = iHigh(st.symbol, PERIOD_M15, 2);
   double low2  = iLow(st.symbol, PERIOD_M15, 2);

   if(st.bullishBOS && high2 < low0)
   {
      st.bullishFVG.lower   = high2;
      st.bullishFVG.upper   = low0;
      st.bullishFVG.isValid = true;
      Print(st.symbol, " Bullish FVG: ",
            st.bullishFVG.lower, " - ", st.bullishFVG.upper);
   }

   if(st.bearishBOS && low2 > high0)
   {
      st.bearishFVG.upper   = low2;
      st.bearishFVG.lower   = high0;
      st.bearishFVG.isValid = true;
      Print(st.symbol, " Bearish FVG: ",
            st.bearishFVG.lower, " - ", st.bearishFVG.upper);
   }
}

//+------------------------------------------------------------------+
//| Check FVG retest for one symbol                                  |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CheckFVGRetest(SymbolState &st)
{
   if(st.bullishBOS && st.bullishFVG.isValid)
   {
      double bid = SymbolInfoDouble(st.symbol, SYMBOL_BID);
      if(bid >= st.bullishFVG.lower && bid <= st.bullishFVG.upper)
         return SIGNAL_BUY;
   }

   if(st.bearishBOS && st.bearishFVG.isValid)
   {
      double ask = SymbolInfoDouble(st.symbol, SYMBOL_ASK);
      if(ask >= st.bearishFVG.lower && ask <= st.bearishFVG.upper)
         return SIGNAL_SELL;
   }

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Execute entry for one symbol                                     |
//+------------------------------------------------------------------+
void ExecuteEntry(SymbolState &st, ENUM_SIGNAL_DIR dir)
{
   double entryPrice = (dir == SIGNAL_BUY) ?
      SymbolInfoDouble(st.symbol, SYMBOL_ASK) :
      SymbolInfoDouble(st.symbol, SYMBOL_BID);

   OkiLevels lv = CalcLevels(st.symbol, dir, entryPrice,
      InpATRPeriod, st.slMult, st.tp1Mult, st.tp2Mult,
      InpTP1ClosePct, InpRiskPercent);

   if(lv.lotSize <= 0 || lv.atrValue == 0)
   {
      Print(st.symbol, " CalcLevels failed, skipping entry");
      return;
   }

   double initialTP = (lv.tp1Lot > 0) ? lv.tp1 : lv.tp2;
   ulong ticket = 0;

   if(InpTradeEnabled)
   {
      ticket = SendMarketOrder(st.symbol, dir, lv.lotSize, lv.sl,
                               initialTP, st.magic, "OkiFVGMulti");
      if(ticket > 0)
      {
         st.tp1Level = lv.tp1;
         st.tp2Level = lv.tp2;
         st.tp1Lot   = lv.tp1Lot;
      }
   }

   //--- Invalidate used FVG
   if(dir == SIGNAL_BUY)
      st.bullishFVG.isValid = false;
   else
      st.bearishFVG.isValid = false;

   //--- Discord notification
   SignalData sig;
   sig.magic     = st.magic;
   sig.strategy  = "SMC_FVG";
   sig.symbol    = st.symbol;
   sig.direction = (dir == SIGNAL_BUY) ? "BUY" : "SELL";
   sig.entry     = entryPrice;
   sig.sl        = lv.sl;
   sig.tp1       = lv.tp1;
   sig.tp2       = lv.tp2;
   sig.volume    = lv.lotSize;
   sig.time      = TimeCurrent();
   sig.ticket    = ticket;

   string embed = FormatSignalEmbed(sig);
   SendDiscordWebhook(InpWebhookUrl, embed);

   Print("SMC_FVG_Multi entry: ", sig.direction, " ", st.symbol,
         " @ ", entryPrice, " SL=", lv.sl,
         " TP1=", lv.tp1, " TP2=", lv.tp2,
         " lot=", lv.lotSize, " magic=", st.magic);
}

//+------------------------------------------------------------------+
//| Process one symbol (called from OnTimer)                         |
//+------------------------------------------------------------------+
void ProcessSymbol(SymbolState &st)
{
   //--- FVG retest check (no position required)
   if(!HasOpenPosition(st.symbol, st.magic))
   {
      ENUM_SIGNAL_DIR sig = CheckFVGRetest(st);
      if(sig != SIGNAL_NONE)
      {
         //--- Session filter (GMT hour)
         MqlDateTime dt;
         TimeGMT(dt);
         bool inSession;
         if(st.sessionStart < st.sessionEnd)
            inSession = (dt.hour >= st.sessionStart && dt.hour < st.sessionEnd);
         else
            inSession = (dt.hour >= st.sessionStart || dt.hour < st.sessionEnd);

         if(!inSession)
            sig = SIGNAL_NONE;

         //--- ADR filter
         if(sig != SIGNAL_NONE &&
            ADRRatio(st.symbol, 20) < st.adrMaxRatio)
         {
            ExecuteEntry(st, sig);
         }
      }
   }

   //--- New bar processing
   if(!IsNewBarMulti(st)) return;

   UpdateStructure(st);
   DetectFVG(st);
}

//+------------------------------------------------------------------+
//| Timer: main loop for all symbols (1-second interval)             |
//+------------------------------------------------------------------+
void OnTimer()
{
   for(int i = 0; i < g_numSymbols; i++)
      ProcessSymbol(g_states[i]);
}

//+------------------------------------------------------------------+
//| Tick: TP1 management for all symbols (high-frequency)            |
//+------------------------------------------------------------------+
void OnTick()
{
   for(int i = 0; i < g_numSymbols; i++)
   {
      if(!HasOpenPosition(g_states[i].symbol, g_states[i].magic) ||
         g_states[i].tp1Lot <= 0)
         continue;

      ManageTP1(g_states[i].symbol, g_states[i].magic,
                g_states[i].tp1Level, g_states[i].tp2Level,
                g_states[i].tp1Lot);

      //--- Check if TP1 already managed
      ulong posTicket = GetPositionTicket(g_states[i].symbol,
                                          g_states[i].magic);
      if(posTicket > 0 && PositionSelectByTicket(posTicket))
      {
         double currentTP = PositionGetDouble(POSITION_TP);
         int digits = (int)SymbolInfoInteger(g_states[i].symbol,
                                             SYMBOL_DIGITS);
         if(NormalizeDouble(currentTP, digits) ==
            NormalizeDouble(g_states[i].tp2Level, digits))
         {
            g_states[i].tp1Lot = 0;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Find SymbolState index by magic number (-1 if not found)         |
//+------------------------------------------------------------------+
int FindStateByMagic(int magic)
{
   for(int i = 0; i < g_numSymbols; i++)
   {
      if(g_states[i].magic == magic)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Trade transaction handler for close notifications                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = trans.deal;
   if(dealTicket == 0) return;
   if(!HistoryDealSelect(dealTicket)) return;

   long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   int stIdx = FindStateByMagic((int)dealMagic);
   if(stIdx < 0) return;

   long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_OUT_BY) return;

   string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   if(dealSymbol != g_states[stIdx].symbol) return;

   //--- Build close data
   double closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   double profit     = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double volume     = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);

   long posId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   double entryPrice = 0;
   datetime openTime = 0;
   string direction  = "";

   HistorySelectByPosition(posId);
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong hTicket = HistoryDealGetTicket(i);
      if(hTicket == 0) continue;
      long hEntry = HistoryDealGetInteger(hTicket, DEAL_ENTRY);
      if(hEntry == DEAL_ENTRY_IN)
      {
         entryPrice = HistoryDealGetDouble(hTicket, DEAL_PRICE);
         openTime   = (datetime)HistoryDealGetInteger(hTicket, DEAL_TIME);
         long hType = HistoryDealGetInteger(hTicket, DEAL_TYPE);
         direction  = (hType == DEAL_TYPE_BUY) ? "BUY" : "SELL";
         break;
      }
   }

   //--- Determine close reason
   string closeReason = "Manual";
   double profitPips = PriceToPips(dealSymbol, closePrice - entryPrice);
   if(direction == "SELL")
      profitPips = PriceToPips(dealSymbol, entryPrice - closePrice);

   int digits = (int)SymbolInfoInteger(dealSymbol, SYMBOL_DIGITS);
   double tp1Lv = g_states[stIdx].tp1Level;
   double tp2Lv = g_states[stIdx].tp2Level;

   if(profit < 0)
   {
      closeReason = "SL";
      profitPips = -profitPips;
   }
   else if(NormalizeDouble(closePrice, digits) ==
           NormalizeDouble(tp1Lv, digits))
   {
      closeReason = "TP1";
   }
   else if(NormalizeDouble(closePrice, digits) ==
           NormalizeDouble(tp2Lv, digits))
   {
      closeReason = "TP2";
   }
   else if(profit >= 0 && entryPrice > 0 &&
           NormalizeDouble(closePrice, digits) ==
           NormalizeDouble(entryPrice, digits))
   {
      closeReason = "BE";
   }

   //--- Send close notification
   CloseData cd;
   cd.magic       = (int)dealMagic;
   cd.strategy    = "SMC_FVG";
   cd.symbol      = dealSymbol;
   cd.direction   = direction;
   cd.entry       = entryPrice;
   cd.closePrice  = closePrice;
   cd.profit      = profit;
   cd.profitPips  = profitPips;
   cd.closeReason = closeReason;
   cd.volume      = volume;
   cd.openTime    = openTime;
   cd.closeTime   = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
   cd.durationMin = (int)((cd.closeTime - cd.openTime) / 60);
   cd.ticket      = dealTicket;

   string embed = FormatCloseEmbed(cd);
   SendDiscordWebhook(InpWebhookUrl, embed);

   Print("SMC_FVG_Multi closed: ", closeReason, " ", dealSymbol,
         " profit=", profit, " pips=", profitPips,
         " magic=", dealMagic);
}
//+------------------------------------------------------------------+

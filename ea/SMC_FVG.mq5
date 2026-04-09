//+------------------------------------------------------------------+
//|                                                    SMC_FVG.mq5   |
//|                                              OkiSignal Project   |
//|  Strategy: Structure Break (BOS) + Fair Value Gap entry          |
//|  Magic: 106                                                       |
//+------------------------------------------------------------------+
#property copyright "OkiSignal"
#property version   "1.00"
#property strict

#include "../include/CommonDefs.mqh"
#include "../include/ATRUtils.mqh"
#include "../include/SignalFormat.mqh"
#include "../include/DiscordWebhook.mqh"

//--- Input Parameters
input string   InpWebhookUrl    = "";              // Discord Webhook URL
input double   InpRiskPercent   = 1.0;             // リスク%
input int      InpSwingLen      = 5;               // Swing判定バー数（片側）
input double   InpSLMult        = 1.5;             // SL = ATR × この値
input double   InpTP1Mult       = 1.5;             // TP1 = ATR × この値
input double   InpTP2Mult       = 3.0;             // TP2 = ATR × この値
input double   InpTP1ClosePct   = 50.0;            // TP1で決済する割合(%)
input int      InpATRPeriod     = 14;              // ATR期間
input double   InpADRMaxRatio   = 0.8;             // ADR消費率上限
input int      InpMagic         = MAGIC_SMC_FVG;   // Magic Number
input bool     InpTradeEnabled  = true;            // 実トレードON/OFF

//--- FVG Zone structure
struct FVGZone
{
   double upper;    // zone upper boundary
   double lower;    // zone lower boundary
   bool   isValid;
};

//--- Structure state
double g_lastSH = 0;       // last Swing High price
double g_lastSL = 0;       // last Swing Low price
bool   g_bullishBOS = false;
bool   g_bearishBOS = false;
FVGZone g_bullishFVG = {};
FVGZone g_bearishFVG = {};

//--- TP1 management
double g_tp1Level = 0;
double g_tp2Level = 0;
double g_tp1Lot   = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   g_lastSH = 0;
   g_lastSL = 0;
   g_bullishBOS = false;
   g_bearishBOS = false;
   g_bullishFVG.isValid = false;
   g_bearishFVG.isValid = false;
   g_tp1Level = 0;
   g_tp2Level = 0;
   g_tp1Lot   = 0;

   Print("SMC_FVG initialized: ", _Symbol,
         " SwingLen=", InpSwingLen,
         " SL=", InpSLMult, "xATR",
         " TP1=", InpTP1Mult, " TP2=", InpTP2Mult);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| Detect Swing High at bar[shift] (needs SwingLen bars each side)  |
//+------------------------------------------------------------------+
bool IsSwingHigh(int shift)
{
   double h = iHigh(_Symbol, PERIOD_M15, shift);
   if(h == 0) return false;

   for(int i = 1; i <= InpSwingLen; i++)
   {
      if(iHigh(_Symbol, PERIOD_M15, shift + i) >= h) return false;
      if(iHigh(_Symbol, PERIOD_M15, shift - i) >= h) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Detect Swing Low at bar[shift]                                   |
//+------------------------------------------------------------------+
bool IsSwingLow(int shift)
{
   double l = iLow(_Symbol, PERIOD_M15, shift);
   if(l == 0) return false;

   for(int i = 1; i <= InpSwingLen; i++)
   {
      if(iLow(_Symbol, PERIOD_M15, shift + i) <= l) return false;
      if(iLow(_Symbol, PERIOD_M15, shift - i) <= l) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Update Swing Points and detect BOS                               |
//+------------------------------------------------------------------+
void UpdateStructure()
{
   //--- Check bar[InpSwingLen] for confirmed swing point
   int checkBar = InpSwingLen;

   if(IsSwingHigh(checkBar))
   {
      g_lastSH = iHigh(_Symbol, PERIOD_M15, checkBar);
      Print("Swing High detected: ", g_lastSH, " at bar[", checkBar, "]");
   }

   if(IsSwingLow(checkBar))
   {
      g_lastSL = iLow(_Symbol, PERIOD_M15, checkBar);
      Print("Swing Low detected: ", g_lastSL, " at bar[", checkBar, "]");
   }

   //--- BOS detection on bar[1] (last closed bar)
   if(g_lastSH > 0 && g_lastSL > 0)
   {
      double close1 = iClose(_Symbol, PERIOD_M15, 1);

      if(close1 > g_lastSH && !g_bullishBOS)
      {
         g_bullishBOS = true;
         g_bearishBOS = false;
         g_bearishFVG.isValid = false;  // invalidate opposite FVG
         Print("Bullish BOS: close ", close1, " > SH ", g_lastSH);
      }
      else if(close1 < g_lastSL && !g_bearishBOS)
      {
         g_bearishBOS = true;
         g_bullishBOS = false;
         g_bullishFVG.isValid = false;
         Print("Bearish BOS: close ", close1, " < SL ", g_lastSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Detect FVG on recent bars                                        |
//+------------------------------------------------------------------+
void DetectFVG()
{
   double high0 = iHigh(_Symbol, PERIOD_M15, 0);
   double low0  = iLow(_Symbol, PERIOD_M15, 0);
   double high2 = iHigh(_Symbol, PERIOD_M15, 2);
   double low2  = iLow(_Symbol, PERIOD_M15, 2);

   //--- Bullish FVG: bar[2].high < bar[0].low (gap up)
   if(g_bullishBOS && high2 < low0)
   {
      g_bullishFVG.lower   = high2;
      g_bullishFVG.upper   = low0;
      g_bullishFVG.isValid = true;
      Print("Bullish FVG: ", g_bullishFVG.lower, " - ", g_bullishFVG.upper);
   }

   //--- Bearish FVG: bar[2].low > bar[0].high (gap down)
   if(g_bearishBOS && low2 > high0)
   {
      g_bearishFVG.upper   = low2;
      g_bearishFVG.lower   = high0;
      g_bearishFVG.isValid = true;
      Print("Bearish FVG: ", g_bearishFVG.lower, " - ", g_bearishFVG.upper);
   }
}

//+------------------------------------------------------------------+
//| Check FVG retest and return signal direction                     |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CheckFVGRetest()
{
   //--- Bullish: bid enters FVG zone
   if(g_bullishBOS && g_bullishFVG.isValid)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid >= g_bullishFVG.lower && bid <= g_bullishFVG.upper)
         return SIGNAL_BUY;
   }

   //--- Bearish: ask enters FVG zone
   if(g_bearishBOS && g_bearishFVG.isValid)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(ask >= g_bearishFVG.lower && ask <= g_bearishFVG.upper)
         return SIGNAL_SELL;
   }

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Execute entry and send Discord notification                      |
//+------------------------------------------------------------------+
void ExecuteEntry(ENUM_SIGNAL_DIR dir)
{
   double entryPrice = (dir == SIGNAL_BUY) ?
      SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
      SymbolInfoDouble(_Symbol, SYMBOL_BID);

   OkiLevels lv = CalcLevels(_Symbol, dir, entryPrice,
      InpATRPeriod, InpSLMult, InpTP1Mult, InpTP2Mult,
      InpTP1ClosePct, InpRiskPercent);

   if(lv.lotSize <= 0 || lv.atrValue == 0)
   {
      Print("CalcLevels failed, skipping entry");
      return;
   }

   //--- Determine initial TP (TP1 if partial close possible, else TP2)
   double initialTP = (lv.tp1Lot > 0) ? lv.tp1 : lv.tp2;
   ulong ticket = 0;

   if(InpTradeEnabled)
   {
      ticket = SendMarketOrder(_Symbol, dir, lv.lotSize, lv.sl, initialTP,
                               InpMagic, "OkiFVG");
      if(ticket > 0)
      {
         g_tp1Level = lv.tp1;
         g_tp2Level = lv.tp2;
         g_tp1Lot   = lv.tp1Lot;
      }
   }

   //--- Invalidate used FVG
   if(dir == SIGNAL_BUY)
      g_bullishFVG.isValid = false;
   else
      g_bearishFVG.isValid = false;

   //--- Discord notification
   SignalData sig;
   sig.magic     = InpMagic;
   sig.strategy  = StrategyName(InpMagic);
   sig.symbol    = _Symbol;
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

   Print("SMC_FVG entry: ", sig.direction, " ", _Symbol,
         " @ ", entryPrice, " SL=", lv.sl,
         " TP1=", lv.tp1, " TP2=", lv.tp2,
         " lot=", lv.lotSize);
}

//+------------------------------------------------------------------+
void OnTick()
{
   //--- TP1 management (every tick)
   if(HasOpenPosition(_Symbol, InpMagic) && g_tp1Lot > 0)
   {
      ManageTP1(_Symbol, InpMagic, g_tp1Level, g_tp2Level, g_tp1Lot);

      //--- Check if TP1 already managed (TP changed to TP2)
      ulong posTicket = GetPositionTicket(_Symbol, InpMagic);
      if(posTicket > 0 && PositionSelectByTicket(posTicket))
      {
         double currentTP = PositionGetDouble(POSITION_TP);
         int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
         if(NormalizeDouble(currentTP, digits) == NormalizeDouble(g_tp2Level, digits))
            g_tp1Lot = 0;
      }
   }

   //--- FVG retest check (every tick, no position required)
   if(!HasOpenPosition(_Symbol, InpMagic))
   {
      ENUM_SIGNAL_DIR sig = CheckFVGRetest();
      if(sig != SIGNAL_NONE)
      {
         //--- ADR filter
         if(ADRRatio(_Symbol, 20) < InpADRMaxRatio)
            ExecuteEntry(sig);
         else
            Print("ADR filter blocked entry: ratio=",
                  DoubleToString(ADRRatio(_Symbol, 20), 2));
      }
   }

   //--- New bar processing: update structure and detect FVGs
   if(!IsNewBar(_Symbol, PERIOD_M15)) return;

   UpdateStructure();
   DetectFVG();
}

//+------------------------------------------------------------------+
//| Trade transaction handler for close notifications                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   //--- Get deal info
   ulong dealTicket = trans.deal;
   if(dealTicket == 0) return;

   if(!HistoryDealSelect(dealTicket)) return;

   long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(dealMagic != InpMagic) return;

   long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_OUT_BY) return;

   string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   if(dealSymbol != _Symbol) return;

   //--- Build close data
   long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
   double closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   double profit     = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double volume     = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);

   //--- Find matching position for entry price and open time
   long posId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   double entryPrice = 0;
   datetime openTime = 0;
   string direction  = "";

   //--- Search history for the entry deal
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
   if(profit < 0)
   {
      closeReason = "SL";
      profitPips = -profitPips;
   }
   else if(NormalizeDouble(closePrice, digits) == NormalizeDouble(g_tp1Level, digits))
   {
      closeReason = "TP1";
   }
   else if(NormalizeDouble(closePrice, digits) == NormalizeDouble(g_tp2Level, digits))
   {
      closeReason = "TP2";
   }
   else if(profit >= 0 && entryPrice > 0 &&
           NormalizeDouble(closePrice, digits) == NormalizeDouble(entryPrice, digits))
   {
      closeReason = "BE";
   }

   //--- Build and send close notification
   CloseData cd;
   cd.magic       = InpMagic;
   cd.strategy    = StrategyName(InpMagic);
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

   Print("SMC_FVG closed: ", closeReason, " ", dealSymbol,
         " profit=", profit, " pips=", profitPips);
}
//+------------------------------------------------------------------+

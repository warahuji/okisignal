//+------------------------------------------------------------------+
//|                                                   ATRUtils.mqh   |
//|                                              OkiSignal Project   |
//+------------------------------------------------------------------+
#ifndef ATR_UTILS_MQH
#define ATR_UTILS_MQH

#include "CommonDefs.mqh"

//--- TP/SL Levels Structure
struct OkiLevels
{
   double sl;
   double tp1;
   double tp2;
   double atrValue;
   double lotSize;
   double tp1Lot;    // partial close lot at TP1
   double tp2Lot;    // remaining lot after TP1
   double slPips;
   double tp1Pips;
   double tp2Pips;
};

//+------------------------------------------------------------------+
//| Calculate ATR value for given symbol and timeframe               |
//+------------------------------------------------------------------+
double GetATR(string symbol, ENUM_TIMEFRAMES tf, int period, int shift = 0)
{
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE)
   {
      Print("ATR handle creation failed for ", symbol);
      return 0;
   }

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0)
   {
      IndicatorRelease(handle);
      Print("ATR CopyBuffer failed for ", symbol);
      return 0;
   }

   double val = buf[0];
   IndicatorRelease(handle);
   return val;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percent and SL distance         |
//+------------------------------------------------------------------+
double CalcLotSize(string symbol, double entryPrice, double slPrice,
                   double riskPercent)
{
   double slDistancePoints = MathAbs(entryPrice - slPrice) /
                             SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(slDistancePoints == 0) return 0;

   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointVal  = tickValue * SymbolInfoDouble(symbol, SYMBOL_POINT) / tickSize;
   if(pointVal == 0) return 0;

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * riskPercent / 100.0;
   double lot = riskMoney / (slDistancePoints * pointVal);

   //--- Normalize to broker constraints
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   lot = MathMax(minLot, MathMin(maxLot, lot));
   lot = MathFloor(lot / lotStep) * lotStep;
   lot = NormalizeDouble(lot, 2);

   return lot;
}

//+------------------------------------------------------------------+
//| Calculate TP/SL levels, lot size, and partial close split        |
//+------------------------------------------------------------------+
OkiLevels CalcLevels(string symbol, ENUM_SIGNAL_DIR dir, double entryPrice,
                     int atrPeriod, double slMult, double tp1Mult,
                     double tp2Mult, double tp1ClosePct, double riskPercent)
{
   OkiLevels lv = {};

   lv.atrValue = GetATR(symbol, PERIOD_M15, atrPeriod, 1); // use closed bar ATR
   if(lv.atrValue == 0)
   {
      Print("ATR is zero, cannot calculate levels for ", symbol);
      return lv;
   }

   double atr = lv.atrValue;

   if(dir == SIGNAL_BUY)
   {
      lv.sl  = entryPrice - atr * slMult;
      lv.tp1 = entryPrice + atr * tp1Mult;
      lv.tp2 = entryPrice + atr * tp2Mult;
   }
   else if(dir == SIGNAL_SELL)
   {
      lv.sl  = entryPrice + atr * slMult;
      lv.tp1 = entryPrice - atr * tp1Mult;
      lv.tp2 = entryPrice - atr * tp2Mult;
   }

   //--- Normalize prices
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   lv.sl  = NormalizeDouble(lv.sl, digits);
   lv.tp1 = NormalizeDouble(lv.tp1, digits);
   lv.tp2 = NormalizeDouble(lv.tp2, digits);

   //--- Pip calculations
   lv.slPips  = PriceToPips(symbol, entryPrice - lv.sl);
   lv.tp1Pips = PriceToPips(symbol, lv.tp1 - entryPrice);
   lv.tp2Pips = PriceToPips(symbol, lv.tp2 - entryPrice);

   //--- Lot sizing
   lv.lotSize = CalcLotSize(symbol, entryPrice, lv.sl, riskPercent);

   //--- Split lots for TP1 partial close
   double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   lv.tp1Lot = lv.lotSize * tp1ClosePct / 100.0;
   lv.tp1Lot = MathFloor(lv.tp1Lot / lotStep) * lotStep;
   lv.tp1Lot = NormalizeDouble(MathMax(minLot, lv.tp1Lot), 2);

   lv.tp2Lot = NormalizeDouble(lv.lotSize - lv.tp1Lot, 2);

   //--- If can't split (remaining less than minLot), use single TP2
   if(lv.tp2Lot < minLot)
   {
      lv.tp1Lot = 0;
      lv.tp2Lot = lv.lotSize;
   }

   return lv;
}

//+------------------------------------------------------------------+
//| Check if position has open position for given magic and symbol   |
//+------------------------------------------------------------------+
bool HasOpenPosition(string symbol, int magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == magic &&
         PositionGetString(POSITION_SYMBOL) == symbol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get position ticket for given magic and symbol                   |
//+------------------------------------------------------------------+
ulong GetPositionTicket(string symbol, int magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == magic &&
         PositionGetString(POSITION_SYMBOL) == symbol)
         return ticket;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| New bar detection (static per-symbol)                            |
//+------------------------------------------------------------------+
bool IsNewBar(string symbol, ENUM_TIMEFRAMES tf)
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(symbol, tf, 0);

   if(currentBarTime == 0) return false;

   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Send market order                                                |
//+------------------------------------------------------------------+
ulong SendMarketOrder(string symbol, ENUM_SIGNAL_DIR dir, double lot,
                      double sl, double tp, int magic, string comment = "")
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action   = TRADE_ACTION_DEAL;
   req.symbol   = symbol;
   req.volume   = lot;
   req.sl       = sl;
   req.tp       = tp;
   req.magic    = magic;
   req.comment  = comment;
   req.deviation = 30; // 3 pips slippage allowance

   if(dir == SIGNAL_BUY)
   {
      req.type  = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
   }
   else if(dir == SIGNAL_SELL)
   {
      req.type  = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(symbol, SYMBOL_BID);
   }
   else
      return 0;

   req.price = NormalizeDouble(req.price,
               (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));

   if(!OrderSend(req, res))
   {
      Print("OrderSend failed: ", res.retcode, " - ", res.comment,
            " | ", symbol, " ", (dir == SIGNAL_BUY ? "BUY" : "SELL"),
            " lot=", lot, " sl=", sl, " tp=", tp);
      return 0;
   }

   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED)
   {
      Print("Order not executed: ", res.retcode, " - ", res.comment);
      return 0;
   }

   Print("Order OK: ", symbol, " ", (dir == SIGNAL_BUY ? "BUY" : "SELL"),
         " lot=", lot, " @ ", res.price, " sl=", sl, " tp=", tp,
         " ticket=", res.order);
   return res.order;
}

//+------------------------------------------------------------------+
//| Partial close position                                           |
//+------------------------------------------------------------------+
bool PartialClose(ulong posTicket, double closeLot)
{
   if(!PositionSelectByTicket(posTicket)) return false;

   string symbol = PositionGetString(POSITION_SYMBOL);
   long   type   = PositionGetInteger(POSITION_TYPE);
   int    magic  = (int)PositionGetInteger(POSITION_MAGIC);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action   = TRADE_ACTION_DEAL;
   req.position = posTicket;
   req.symbol   = symbol;
   req.volume   = closeLot;
   req.magic    = magic;
   req.deviation = 30;

   if(type == POSITION_TYPE_BUY)
   {
      req.type  = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(symbol, SYMBOL_BID);
   }
   else
   {
      req.type  = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
   }

   if(!OrderSend(req, res))
   {
      Print("PartialClose failed: ", res.retcode, " ticket=", posTicket);
      return false;
   }

   return (res.retcode == TRADE_RETCODE_DONE);
}

//+------------------------------------------------------------------+
//| Modify position SL and TP                                        |
//+------------------------------------------------------------------+
bool ModifyPosition(ulong posTicket, double newSL, double newTP)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action   = TRADE_ACTION_SLTP;
   req.position = posTicket;

   if(!PositionSelectByTicket(posTicket)) return false;
   req.symbol = PositionGetString(POSITION_SYMBOL);

   int digits = (int)SymbolInfoInteger(req.symbol, SYMBOL_DIGITS);
   req.sl = NormalizeDouble(newSL, digits);
   req.tp = NormalizeDouble(newTP, digits);

   if(!OrderSend(req, res))
   {
      Print("ModifyPosition failed: ", res.retcode, " ticket=", posTicket);
      return false;
   }

   return (res.retcode == TRADE_RETCODE_DONE);
}

//+------------------------------------------------------------------+
//| Manage TP1 partial close and SL to breakeven                     |
//| Call this in OnTick() for each strategy EA                       |
//+------------------------------------------------------------------+
void ManageTP1(string symbol, int magic, double tp1Level, double tp2Level,
               double tp1Lot)
{
   ulong ticket = GetPositionTicket(symbol, magic);
   if(ticket == 0) return;
   if(tp1Lot <= 0) return;

   if(!PositionSelectByTicket(ticket)) return;

   double currentTP = PositionGetDouble(POSITION_TP);
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   long   posType = PositionGetInteger(POSITION_TYPE);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   //--- Check if TP1 is still the target (not yet partially closed)
   if(NormalizeDouble(currentTP, digits) != NormalizeDouble(tp1Level, digits))
      return; // already managed or different TP

   //--- Check if TP1 hit
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   bool tp1Hit = false;

   if(posType == POSITION_TYPE_BUY && bid >= tp1Level)
      tp1Hit = true;
   else if(posType == POSITION_TYPE_SELL && ask <= tp1Level)
      tp1Hit = true;

   if(!tp1Hit) return;

   //--- Execute partial close
   if(PartialClose(ticket, tp1Lot))
   {
      Print("TP1 hit: partial close ", tp1Lot, " lots on ", symbol);

      //--- Move SL to breakeven, set TP to TP2
      Sleep(500); // brief wait for position update
      ModifyPosition(ticket, entryPrice, tp2Level);
      Print("SL moved to BE (", entryPrice, "), TP set to TP2 (", tp2Level, ")");
   }
}

//+------------------------------------------------------------------+
//| Calculate Average Daily Range                                    |
//+------------------------------------------------------------------+
double CalcADR(string symbol, int period)
{
   double sum = 0;
   for(int i = 1; i <= period; i++) // skip today (incomplete)
   {
      double h = iHigh(symbol, PERIOD_D1, i);
      double l = iLow(symbol, PERIOD_D1, i);
      if(h == 0 || l == 0) continue;
      sum += (h - l);
   }
   return (period > 0) ? sum / period : 0;
}

//+------------------------------------------------------------------+
//| Get today's consumed range                                       |
//+------------------------------------------------------------------+
double TodayConsumedRange(string symbol)
{
   double h = iHigh(symbol, PERIOD_D1, 0);
   double l = iLow(symbol, PERIOD_D1, 0);
   return h - l;
}

//+------------------------------------------------------------------+
//| ADR consumption ratio (0.0 - 1.0+)                               |
//+------------------------------------------------------------------+
double ADRRatio(string symbol, int adrPeriod)
{
   double adr = CalcADR(symbol, adrPeriod);
   if(adr == 0) return 1.0; // unknown = assume exhausted
   return TodayConsumedRange(symbol) / adr;
}

#endif

//+------------------------------------------------------------------+
//|                                          SMC_FVG_Standalone.mq5  |
//|                                              OkiSignal Project   |
//|  Standalone multi-symbol EA: Structure Break + Fair Value Gap    |
//|  All includes merged into a single file (no external deps)      |
//+------------------------------------------------------------------+
#property copyright "OkiSignal"
#property version   "1.00"

//====================================================================
//  CommonDefs (merged)
//====================================================================

//--- Magic Numbers
#define MAGIC_SESSION_BREAKOUT  101
#define MAGIC_MTF_STRUCTURE     102
#define MAGIC_RSI_DIVERGENCE    103
#define MAGIC_EMA_ADR           104
#define MAGIC_OB_RETEST         105
#define MAGIC_SMC_FVG           106
#define MAGIC_LOGGER            999

//--- Signal Direction
enum ENUM_SIGNAL_DIR
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = 2
};

//--- Strategy Name from Magic Number
string StrategyName(int magic)
{
   switch(magic)
   {
      case MAGIC_SESSION_BREAKOUT: return "SessionBreakout";
      case MAGIC_MTF_STRUCTURE:    return "MTFStructure";
      case MAGIC_RSI_DIVERGENCE:   return "RSIDivergence";
      case MAGIC_EMA_ADR:          return "EMA_ADR";
      case MAGIC_OB_RETEST:        return "OBRetest";
      case MAGIC_SMC_FVG:          return "SMC_FVG";
      default:                     return "Unknown";
   }
}

//--- Allowed Symbols
string g_allowedSymbols[] = {
   "USDJPY", "EURUSD", "GBPUSD", "AUDUSD",
   "GBPJPY", "EURJPY", "AUDJPY", "XAUUSD"
};

//--- Signal Data Structure (used by Logger)
struct SignalData
{
   int      magic;
   string   strategy;
   string   symbol;
   string   direction;
   double   entry;
   double   sl;
   double   tp1;
   double   tp2;
   double   volume;
   datetime time;
   ulong    ticket;
};

//--- Close Data Structure (used by Logger)
struct CloseData
{
   int      magic;
   string   strategy;
   string   symbol;
   string   direction;
   double   entry;
   double   closePrice;
   double   profit;
   double   profitPips;
   string   closeReason;  // "TP1", "TP2", "SL", "BE", "Manual"
   double   volume;
   datetime openTime;
   datetime closeTime;
   int      durationMin;
   ulong    ticket;
};

//--- Check if magic number belongs to OkiSignal
bool IsOkiMagic(int magic)
{
   return (magic >= MAGIC_SESSION_BREAKOUT && magic <= MAGIC_SMC_FVG);
}

//--- Check if currently in Strategy Tester
bool IsBacktest()
{
   return (bool)MQLInfoInteger(MQL_TESTER);
}

//--- Pip value for a symbol (handles XAUUSD correctly)
double PipSize(string symbol)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5)
      return SymbolInfoDouble(symbol, SYMBOL_POINT) * 10.0;
   else
      return SymbolInfoDouble(symbol, SYMBOL_POINT);
}

//--- Convert price difference to pips
double PriceToPips(string symbol, double priceDiff)
{
   double pipSz = PipSize(symbol);
   if(pipSz == 0) return 0;
   return MathAbs(priceDiff) / pipSz;
}

//====================================================================
//  ATRUtils (merged)
//====================================================================

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

   //--- Auto-detect filling mode
   long fillType = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((fillType & SYMBOL_FILLING_FOK) != 0)
      req.type_filling = ORDER_FILLING_FOK;
   else if((fillType & SYMBOL_FILLING_IOC) != 0)
      req.type_filling = ORDER_FILLING_IOC;
   else
      req.type_filling = ORDER_FILLING_RETURN;

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

   //--- Auto-detect filling mode
   long fillType = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((fillType & SYMBOL_FILLING_FOK) != 0)
      req.type_filling = ORDER_FILLING_FOK;
   else if((fillType & SYMBOL_FILLING_IOC) != 0)
      req.type_filling = ORDER_FILLING_IOC;
   else
      req.type_filling = ORDER_FILLING_RETURN;

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

//====================================================================
//  DiscordWebhook (merged)
//====================================================================

//--- Color constants for embeds
#define COLOR_GREEN  3066993
#define COLOR_RED    15158332
#define COLOR_BLUE   3447003
#define COLOR_GOLD   15844367

//+------------------------------------------------------------------+
//| Send raw JSON payload to Discord webhook                         |
//+------------------------------------------------------------------+
bool SendDiscordWebhook(string webhookUrl, string jsonPayload)
{
   if(webhookUrl == "" || StringLen(webhookUrl) < 10) return false;

   if((bool)MQLInfoInteger(MQL_TESTER))
   {
      Print("[Discord] Skipped in backtest: ", StringSubstr(jsonPayload, 0, 100));
      return true;
   }

   char post[];
   char result[];
   string headers = "Content-Type: application/json\r\n";

   int len = StringToCharArray(jsonPayload, post, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(post, len - 1);

   string resultHeaders;
   int res = WebRequest("POST", webhookUrl, headers, 5000, post,
                        result, resultHeaders);

   if(res == 200 || res == 204)
      return true;

   if(res == 429)
   {
      Print("[Discord] Rate limited. Retrying in 2 seconds...");
      Sleep(2000);
      res = WebRequest("POST", webhookUrl, headers, 5000, post,
                       result, resultHeaders);
      if(res == 200 || res == 204) return true;
   }

   string errBody = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   Print("[Discord] Webhook failed: HTTP ", res, " | ", errBody);
   return false;
}

//+------------------------------------------------------------------+
//| Escape JSON string                                               |
//+------------------------------------------------------------------+
string JsonEscape(string s)
{
   string r = s;
   StringReplace(r, "\\", "\\\\");
   StringReplace(r, "\"", "\\\"");
   StringReplace(r, "\n", "\\n");
   StringReplace(r, "\r", "");
   StringReplace(r, "\t", "\\t");
   return r;
}

//+------------------------------------------------------------------+
//| Build a simple embed JSON with fields                            |
//+------------------------------------------------------------------+
string BuildEmbed(string title, int clr, string fieldsJson, string footer, string timestamp)
{
   if(footer == "") footer = "OkiSignal - M15";
   if(timestamp == "")
      timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);

   string iso = timestamp;
   StringReplace(iso, ".", "-");
   if(StringFind(iso, "T") < 0)
      StringReplace(iso, " ", "T");
   if(StringFind(iso, "Z") < 0)
      iso += "Z";

   string json = "{\"embeds\":[{";
   json += "\"title\":\"" + JsonEscape(title) + "\",";
   json += "\"color\":" + IntegerToString(clr) + ",";
   json += "\"fields\":[" + fieldsJson + "],";
   json += "\"footer\":{\"text\":\"" + JsonEscape(footer) + "\"},";
   json += "\"timestamp\":\"" + iso + "\"";
   json += "}]}";

   return json;
}

//+------------------------------------------------------------------+
//| Build a single embed field JSON                                  |
//+------------------------------------------------------------------+
string EmbedField(string name, string value, bool isInline = true)
{
   string inl = "true";
   if(!isInline) inl = "false";
   return "{\"name\":\"" + JsonEscape(name) + "\"," +
          "\"value\":\"" + JsonEscape(value) + "\"," +
          "\"inline\":" + inl + "}";
}

//====================================================================
//  SignalFormat (merged)
//====================================================================

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

//====================================================================
//  SMC_FVG_Multi EA body
//====================================================================

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

//+------------------------------------------------------------------+
//|                                            SessionBreakout.mq5   |
//|                                              OkiSignal Project   |
//|  Strategy: London/NY session first-hour range breakout (OCO)     |
//|  Magic: 101                                                       |
//+------------------------------------------------------------------+
#property copyright "OkiSignal"
#property version   "1.00"
#property strict

#include "../include/CommonDefs.mqh"
#include "../include/ATRUtils.mqh"

//--- Input Parameters: Strategy
input int    InpLondonHour      = 10;      // London range start (server hour)
input int    InpNYHour          = 16;      // NY range start (server hour)
input int    InpRangeMinutes    = 60;      // Range period (minutes)
input double InpBreakoutBuffer  = 2.0;     // Breakout buffer (points)
input double InpMaxRangeATRMult = 1.5;     // Max range width (ATR multiple)
input int    InpExpiryBars      = 8;       // Pending order expiry (M15 bars)

//--- Input Parameters: Risk & Levels
input double InpRiskPercent     = 1.0;     // Risk per trade (%)
input int    InpATRPeriod       = 14;      // ATR Period
input double InpSLMult          = 1.5;     // SL multiplier (ATR)
input double InpTP1Mult         = 1.0;     // TP1 multiplier (ATR)
input double InpTP2Mult         = 2.0;     // TP2 multiplier (ATR)
input double InpTP1ClosePct     = 50.0;    // TP1 partial close (%)

//--- Input Parameters: Trading
input int    InpMagic           = MAGIC_SESSION_BREAKOUT;
input string InpTradeComment    = "OkiSB";

//--- State
double g_rangeHigh;
double g_rangeLow;
bool   g_rangeCalculated;
int    g_sessionType;        // 0=none, 1=London, 2=NY
ulong  g_buyStopTicket;
ulong  g_sellStopTicket;
int    g_barsSinceRange;

//--- TP1 management state
double g_tp1Level;
double g_tp2Level;
double g_tp1Lot;

//+------------------------------------------------------------------+
int OnInit()
{
   ResetState();
   Print("SessionBreakout initialized: ", _Symbol,
         " London=", InpLondonHour, " NY=", InpNYHour);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeletePendingOrders();
}

//+------------------------------------------------------------------+
void ResetState()
{
   g_rangeHigh = 0;
   g_rangeLow = DBL_MAX;
   g_rangeCalculated = false;
   g_sessionType = 0;
   g_buyStopTicket = 0;
   g_sellStopTicket = 0;
   g_barsSinceRange = 0;
   g_tp1Level = 0;
   g_tp2Level = 0;
   g_tp1Lot = 0;
}

//+------------------------------------------------------------------+
//| Calculate range from the M15 bars of the first hour              |
//+------------------------------------------------------------------+
bool CalcSessionRange(int sessionStartHour)
{
   //--- Find the 4 M15 bars that make up the first hour
   datetime serverTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(serverTime, dt);

   //--- Check if the range hour just completed
   int currentHour = dt.hour;
   int currentMin  = dt.min;

   //--- Range completes when we're at sessionStartHour+1
   int rangeEndHour = sessionStartHour + (InpRangeMinutes / 60);
   if(currentHour != rangeEndHour || currentMin > 15) return false;

   //--- Scan bars to find the range
   int barsInRange = InpRangeMinutes / 15; // 4 bars for 60min
   g_rangeHigh = 0;
   g_rangeLow = DBL_MAX;

   for(int i = 1; i <= barsInRange; i++)
   {
      double h = iHigh(_Symbol, PERIOD_M15, i);
      double l = iLow(_Symbol, PERIOD_M15, i);
      if(h > g_rangeHigh) g_rangeHigh = h;
      if(l < g_rangeLow)  g_rangeLow = l;
   }

   if(g_rangeHigh <= g_rangeLow) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Place OCO pending orders above and below the range               |
//+------------------------------------------------------------------+
bool PlacePendingOrders()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double buffer = InpBreakoutBuffer * point;

   double buyEntry  = NormalizeDouble(g_rangeHigh + buffer, digits);
   double sellEntry = NormalizeDouble(g_rangeLow - buffer, digits);

   //--- Calculate levels for BUY
   OkiLevels buyLv = CalcLevels(_Symbol, SIGNAL_BUY, buyEntry,
                                 InpATRPeriod, InpSLMult, InpTP1Mult,
                                 InpTP2Mult, InpTP1ClosePct, InpRiskPercent);

   //--- BUY SL: range low or ATR-based, whichever is wider
   double buySL = MathMin(g_rangeLow, buyEntry - buyLv.atrValue * InpSLMult);
   buySL = NormalizeDouble(buySL, digits);

   //--- Calculate levels for SELL
   OkiLevels sellLv = CalcLevels(_Symbol, SIGNAL_SELL, sellEntry,
                                  InpATRPeriod, InpSLMult, InpTP1Mult,
                                  InpTP2Mult, InpTP1ClosePct, InpRiskPercent);

   double sellSL = MathMax(g_rangeHigh, sellEntry + sellLv.atrValue * InpSLMult);
   sellSL = NormalizeDouble(sellSL, digits);

   //--- Recalculate lot sizes with actual SL distances
   double buyLot = CalcLotSize(_Symbol, buyEntry, buySL, InpRiskPercent);
   double sellLot = CalcLotSize(_Symbol, sellEntry, sellSL, InpRiskPercent);

   //--- TP levels
   double buyTP1  = NormalizeDouble(buyEntry + buyLv.atrValue * InpTP1Mult, digits);
   double sellTP1 = NormalizeDouble(sellEntry - sellLv.atrValue * InpTP1Mult, digits);

   //--- Expiry time
   datetime expiry = TimeCurrent() + InpExpiryBars * PeriodSeconds(PERIOD_M15);

   //--- Place BUY STOP
   g_buyStopTicket = PlaceStopOrder(ORDER_TYPE_BUY_STOP, buyEntry, buySL,
                                     buyTP1, buyLot, expiry);

   //--- Place SELL STOP
   g_sellStopTicket = PlaceStopOrder(ORDER_TYPE_SELL_STOP, sellEntry, sellSL,
                                      sellTP1, sellLot, expiry);

   if(g_buyStopTicket > 0 || g_sellStopTicket > 0)
   {
      //--- Save TP2 levels for management
      g_tp1Level = buyTP1; // will be updated when order triggers
      g_tp2Level = NormalizeDouble(buyEntry + buyLv.atrValue * InpTP2Mult, digits);

      Print("Pending orders placed: BUY STOP=", buyEntry,
            " SELL STOP=", sellEntry, " Range=",
            DoubleToString(g_rangeHigh - g_rangeLow, digits));
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
ulong PlaceStopOrder(ENUM_ORDER_TYPE type, double price, double sl,
                     double tp, double lot, datetime expiry)
{
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action     = TRADE_ACTION_PENDING;
   req.symbol     = _Symbol;
   req.type       = type;
   req.price      = price;
   req.sl         = sl;
   req.tp         = tp;
   req.volume     = lot;
   req.magic      = InpMagic;
   req.comment    = InpTradeComment;
   req.type_time  = ORDER_TIME_SPECIFIED;
   req.expiration = expiry;

   if(!OrderSend(req, res))
   {
      Print("PlaceStopOrder failed: ", res.retcode, " ", res.comment,
            " type=", EnumToString(type), " price=", price);
      return 0;
   }

   if(res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED)
   {
      Print("Stop order not placed: ", res.retcode);
      return 0;
   }

   return res.order;
}

//+------------------------------------------------------------------+
//| Delete remaining pending order when one triggers (OCO)           |
//+------------------------------------------------------------------+
void DeletePendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action = TRADE_ACTION_REMOVE;
      req.order  = ticket;
      OrderSend(req, res);
   }
}

//+------------------------------------------------------------------+
//| Check if a pending order was triggered, delete the other         |
//+------------------------------------------------------------------+
void CheckOCO()
{
   if(g_buyStopTicket == 0 && g_sellStopTicket == 0) return;

   bool posOpen = HasOpenPosition(_Symbol, InpMagic);
   if(!posOpen) return;

   //--- A position opened, determine direction and update TP state
   ulong posTicket = GetPositionTicket(_Symbol, InpMagic);
   if(posTicket > 0 && PositionSelectByTicket(posTicket))
   {
      long posType = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

      double atr = GetATR(_Symbol, PERIOD_M15, InpATRPeriod, 1);

      if(posType == POSITION_TYPE_BUY)
      {
         g_tp1Level = NormalizeDouble(entry + atr * InpTP1Mult, digits);
         g_tp2Level = NormalizeDouble(entry + atr * InpTP2Mult, digits);
      }
      else
      {
         g_tp1Level = NormalizeDouble(entry - atr * InpTP1Mult, digits);
         g_tp2Level = NormalizeDouble(entry - atr * InpTP2Mult, digits);
      }

      //--- Calculate partial lot
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double vol = PositionGetDouble(POSITION_VOLUME);

      g_tp1Lot = vol * InpTP1ClosePct / 100.0;
      g_tp1Lot = MathFloor(g_tp1Lot / lotStep) * lotStep;
      g_tp1Lot = NormalizeDouble(MathMax(minLot, g_tp1Lot), 2);
      if(NormalizeDouble(vol - g_tp1Lot, 2) < minLot)
         g_tp1Lot = 0;
   }

   //--- Delete remaining pending orders
   DeletePendingOrders();
   g_buyStopTicket = 0;
   g_sellStopTicket = 0;

   Print("OCO triggered, remaining pending orders deleted");
}

//+------------------------------------------------------------------+
void OnTrade()
{
   CheckOCO();
}

//+------------------------------------------------------------------+
void OnTick()
{
   //--- TP1 management
   if(HasOpenPosition(_Symbol, InpMagic) && g_tp1Lot > 0)
   {
      ManageTP1(_Symbol, InpMagic, g_tp1Level, g_tp2Level, g_tp1Lot);
      ulong posTicket = GetPositionTicket(_Symbol, InpMagic);
      if(posTicket > 0 && PositionSelectByTicket(posTicket))
      {
         double currentTP = PositionGetDouble(POSITION_TP);
         int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
         if(NormalizeDouble(currentTP, digits) == NormalizeDouble(g_tp2Level, digits))
            g_tp1Lot = 0;
      }
   }

   //--- Signal evaluation only on new M15 bar
   if(!IsNewBar(_Symbol, PERIOD_M15)) return;

   //--- Skip if already in position or pending orders active
   if(HasOpenPosition(_Symbol, InpMagic)) return;
   if(g_buyStopTicket > 0 || g_sellStopTicket > 0)
   {
      g_barsSinceRange++;
      return;
   }

   //--- Check if a session range just completed
   bool londonRange = CalcSessionRange(InpLondonHour);
   bool nyRange = (!londonRange) ? CalcSessionRange(InpNYHour) : false;

   if(!londonRange && !nyRange) return;

   g_sessionType = londonRange ? 1 : 2;
   g_rangeCalculated = true;
   g_barsSinceRange = 0;

   //--- Filter: range too wide
   double atr = GetATR(_Symbol, PERIOD_M15, InpATRPeriod, 1);
   double rangeWidth = g_rangeHigh - g_rangeLow;

   if(atr > 0 && rangeWidth > atr * InpMaxRangeATRMult)
   {
      Print("Range too wide: ", DoubleToString(rangeWidth, _Digits),
            " > ", DoubleToString(atr * InpMaxRangeATRMult, _Digits), " — skip");
      ResetState();
      return;
   }

   //--- Place OCO pending orders
   Print("Session ", (g_sessionType == 1 ? "London" : "NY"),
         " range: H=", g_rangeHigh, " L=", g_rangeLow);
   PlacePendingOrders();
}
//+------------------------------------------------------------------+

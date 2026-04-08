//+------------------------------------------------------------------+
//|                                                  OBRetest.mq5    |
//|                                              OkiSignal Project   |
//|  Strategy: Order Block detection + retest entry                  |
//|  Magic: 105                                                       |
//+------------------------------------------------------------------+
#property copyright "OkiSignal"
#property version   "1.00"
#property strict

#include "../include/CommonDefs.mqh"
#include "../include/ATRUtils.mqh"

//--- Input Parameters: Strategy
input double InpImpulseATRMult = 1.5;    // Min impulse move (ATR multiple)
input int    InpMaxRetestBars  = 20;     // Max bars to wait for retest
input double InpOBBodyPct      = 50.0;   // Min OB candle body (% of range)
input int    InpMaxActiveOBs   = 3;      // Max tracked OBs per direction

//--- Input Parameters: Risk & Levels
input double InpRiskPercent    = 1.0;
input int    InpATRPeriod      = 14;
input double InpSLMult         = 1.5;
input double InpTP1Mult        = 1.0;
input double InpTP2Mult        = 2.0;
input double InpTP1ClosePct    = 50.0;

//--- Input Parameters: Trading
input int    InpMagic          = MAGIC_OB_RETEST;
input string InpTradeComment   = "OkiOB";

//--- Order Block structure
struct OrderBlock
{
   double   zoneHigh;
   double   zoneLow;
   double   impulseTarget;  // end of impulse move (for TP2 reference)
   datetime createTime;
   int      barAge;
   bool     isBullish;
   bool     isValid;
};

//--- Tracked OBs
OrderBlock g_bullishOBs[];
OrderBlock g_bearishOBs[];

//--- TP1 management
double g_tp1Level;
double g_tp2Level;
double g_tp1Lot;

//+------------------------------------------------------------------+
int OnInit()
{
   ArrayResize(g_bullishOBs, 0);
   ArrayResize(g_bearishOBs, 0);
   g_tp1Level = 0;
   g_tp2Level = 0;
   g_tp1Lot   = 0;

   Print("OBRetest initialized: ", _Symbol,
         " ImpulseATR=", InpImpulseATRMult,
         " MaxRetest=", InpMaxRetestBars);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| Check if candle has solid body (not doji)                        |
//+------------------------------------------------------------------+
bool IsSolidCandle(int shift)
{
   double open  = iOpen(_Symbol, PERIOD_M15, shift);
   double close = iClose(_Symbol, PERIOD_M15, shift);
   double high  = iHigh(_Symbol, PERIOD_M15, shift);
   double low   = iLow(_Symbol, PERIOD_M15, shift);

   double range = high - low;
   if(range == 0) return false;

   double body = MathAbs(close - open);
   return (body / range * 100.0) >= InpOBBodyPct;
}

//+------------------------------------------------------------------+
//| Check if bar is bearish                                          |
//+------------------------------------------------------------------+
bool IsBearishBar(int shift)
{
   return iClose(_Symbol, PERIOD_M15, shift) < iOpen(_Symbol, PERIOD_M15, shift);
}

//+------------------------------------------------------------------+
//| Check if bar is bullish                                          |
//+------------------------------------------------------------------+
bool IsBullishBar(int shift)
{
   return iClose(_Symbol, PERIOD_M15, shift) > iOpen(_Symbol, PERIOD_M15, shift);
}

//+------------------------------------------------------------------+
//| Scan for new order blocks                                        |
//+------------------------------------------------------------------+
void ScanForOBs()
{
   double atr = GetATR(_Symbol, PERIOD_M15, InpATRPeriod, 1);
   if(atr == 0) return;

   double impulseMin = atr * InpImpulseATRMult;

   //--- Scan recent bars for impulse moves
   for(int i = 2; i < 30; i++)
   {
      //--- Check for bullish impulse (strong up move)
      double moveUp = iHigh(_Symbol, PERIOD_M15, 1) - iLow(_Symbol, PERIOD_M15, i);
      if(moveUp >= impulseMin)
      {
         //--- Find the last bearish candle before the impulse = bullish OB
         for(int j = i; j < i + 5 && j < 35; j++)
         {
            if(IsBearishBar(j) && IsSolidCandle(j))
            {
               OrderBlock ob;
               ob.zoneHigh = iOpen(_Symbol, PERIOD_M15, j);
               ob.zoneLow  = iLow(_Symbol, PERIOD_M15, j);
               ob.impulseTarget = iHigh(_Symbol, PERIOD_M15, 1);
               ob.createTime = iTime(_Symbol, PERIOD_M15, j);
               ob.barAge = 0;
               ob.isBullish = true;
               ob.isValid = true;

               AddOB(g_bullishOBs, ob);
               break;
            }
         }
         break; // only look for one impulse per scan
      }

      //--- Check for bearish impulse
      double moveDown = iHigh(_Symbol, PERIOD_M15, i) - iLow(_Symbol, PERIOD_M15, 1);
      if(moveDown >= impulseMin)
      {
         for(int j = i; j < i + 5 && j < 35; j++)
         {
            if(IsBullishBar(j) && IsSolidCandle(j))
            {
               OrderBlock ob;
               ob.zoneHigh = iHigh(_Symbol, PERIOD_M15, j);
               ob.zoneLow  = iOpen(_Symbol, PERIOD_M15, j);
               ob.impulseTarget = iLow(_Symbol, PERIOD_M15, 1);
               ob.createTime = iTime(_Symbol, PERIOD_M15, j);
               ob.barAge = 0;
               ob.isBullish = false;
               ob.isValid = true;

               AddOB(g_bearishOBs, ob);
               break;
            }
         }
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Add OB to array (FIFO, max size limited)                         |
//+------------------------------------------------------------------+
void AddOB(OrderBlock &arr[], OrderBlock &ob)
{
   //--- Check for duplicate (same zone)
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   for(int i = 0; i < ArraySize(arr); i++)
   {
      if(NormalizeDouble(arr[i].zoneHigh, digits) == NormalizeDouble(ob.zoneHigh, digits) &&
         NormalizeDouble(arr[i].zoneLow, digits) == NormalizeDouble(ob.zoneLow, digits))
         return; // already tracked
   }

   int size = ArraySize(arr);
   if(size >= InpMaxActiveOBs)
   {
      //--- Remove oldest (FIFO)
      for(int i = 0; i < size - 1; i++)
         arr[i] = arr[i + 1];
      ArrayResize(arr, size); // keep same size
      arr[size - 1] = ob;
   }
   else
   {
      ArrayResize(arr, size + 1);
      arr[size] = ob;
   }
}

//+------------------------------------------------------------------+
//| Age all OBs and invalidate expired ones                          |
//+------------------------------------------------------------------+
void AgeOBs()
{
   for(int i = ArraySize(g_bullishOBs) - 1; i >= 0; i--)
   {
      g_bullishOBs[i].barAge++;
      if(g_bullishOBs[i].barAge > InpMaxRetestBars)
         g_bullishOBs[i].isValid = false;
   }

   for(int i = ArraySize(g_bearishOBs) - 1; i >= 0; i--)
   {
      g_bearishOBs[i].barAge++;
      if(g_bearishOBs[i].barAge > InpMaxRetestBars)
         g_bearishOBs[i].isValid = false;
   }
}

//+------------------------------------------------------------------+
//| Check for retest entries                                         |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CheckRetest(double &slLevel, double &impulseEnd)
{
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double low1   = iLow(_Symbol, PERIOD_M15, 1);
   double high1  = iHigh(_Symbol, PERIOD_M15, 1);

   //--- Bullish OB retest: price wicks into zone and closes above
   for(int i = 0; i < ArraySize(g_bullishOBs); i++)
   {
      if(!g_bullishOBs[i].isValid) continue;

      if(low1 <= g_bullishOBs[i].zoneHigh && close1 > g_bullishOBs[i].zoneHigh)
      {
         Print("Bullish OB retest: zone [", g_bullishOBs[i].zoneLow,
               " - ", g_bullishOBs[i].zoneHigh, "]");
         slLevel = g_bullishOBs[i].zoneLow;
         impulseEnd = g_bullishOBs[i].impulseTarget;
         g_bullishOBs[i].isValid = false; // consumed
         return SIGNAL_BUY;
      }
   }

   //--- Bearish OB retest: price wicks into zone and closes below
   for(int i = 0; i < ArraySize(g_bearishOBs); i++)
   {
      if(!g_bearishOBs[i].isValid) continue;

      if(high1 >= g_bearishOBs[i].zoneLow && close1 < g_bearishOBs[i].zoneLow)
      {
         Print("Bearish OB retest: zone [", g_bearishOBs[i].zoneLow,
               " - ", g_bearishOBs[i].zoneHigh, "]");
         slLevel = g_bearishOBs[i].zoneHigh;
         impulseEnd = g_bearishOBs[i].impulseTarget;
         g_bearishOBs[i].isValid = false;
         return SIGNAL_SELL;
      }
   }

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
void ExecuteEntry(ENUM_SIGNAL_DIR dir, double structureSL, double impulseEnd)
{
   double entryPrice = (dir == SIGNAL_BUY) ?
      SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
      SymbolInfoDouble(_Symbol, SYMBOL_BID);

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double atr = GetATR(_Symbol, PERIOD_M15, InpATRPeriod, 1);

   //--- SL: beyond OB zone + 0.3 ATR buffer
   double slBuffer = atr * 0.3;
   double sl;
   if(dir == SIGNAL_BUY)
      sl = structureSL - slBuffer;
   else
      sl = structureSL + slBuffer;

   //--- Ensure minimum SL distance
   if(MathAbs(entryPrice - sl) < atr * 1.0)
   {
      if(dir == SIGNAL_BUY) sl = entryPrice - atr * 1.0;
      else sl = entryPrice + atr * 1.0;
   }
   sl = NormalizeDouble(sl, digits);

   //--- Lot size
   double lot = CalcLotSize(_Symbol, entryPrice, sl, InpRiskPercent);
   if(lot <= 0) return;

   //--- TP levels
   double tp1 = (dir == SIGNAL_BUY) ?
      NormalizeDouble(entryPrice + atr * InpTP1Mult, digits) :
      NormalizeDouble(entryPrice - atr * InpTP1Mult, digits);

   double tp2 = (dir == SIGNAL_BUY) ?
      NormalizeDouble(entryPrice + atr * InpTP2Mult, digits) :
      NormalizeDouble(entryPrice - atr * InpTP2Mult, digits);

   //--- Split lots
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double tp1LotCalc = lot * InpTP1ClosePct / 100.0;
   tp1LotCalc = MathFloor(tp1LotCalc / lotStep) * lotStep;
   tp1LotCalc = NormalizeDouble(MathMax(minLot, tp1LotCalc), 2);
   if(NormalizeDouble(lot - tp1LotCalc, 2) < minLot)
      tp1LotCalc = 0;

   double initialTP = (tp1LotCalc > 0) ? tp1 : tp2;
   ulong ticket = SendMarketOrder(_Symbol, dir, lot, sl, initialTP,
                                   InpMagic, InpTradeComment);
   if(ticket > 0)
   {
      g_tp1Level = tp1;
      g_tp2Level = tp2;
      g_tp1Lot   = tp1LotCalc;
   }
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

   if(!IsNewBar(_Symbol, PERIOD_M15)) return;
   if(HasOpenPosition(_Symbol, InpMagic)) return;

   g_tp1Level = 0;
   g_tp2Level = 0;
   g_tp1Lot   = 0;

   //--- Age existing OBs
   AgeOBs();

   //--- Scan for new OBs
   ScanForOBs();

   //--- Check for retest entry
   double slLevel = 0, impulseEnd = 0;
   ENUM_SIGNAL_DIR signal = CheckRetest(slLevel, impulseEnd);
   if(signal == SIGNAL_NONE) return;

   Print("OBRetest signal: ", (signal == SIGNAL_BUY ? "BUY" : "SELL"),
         " on ", _Symbol);
   ExecuteEntry(signal, slLevel, impulseEnd);
}
//+------------------------------------------------------------------+

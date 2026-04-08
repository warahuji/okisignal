//+------------------------------------------------------------------+
//|                                                     EMA_ADR.mq5  |
//|                                              OkiSignal Project   |
//|  Strategy: EMA crossover + ADX + RSI + Pullback + Time filter    |
//|  Magic: 104                                                       |
//+------------------------------------------------------------------+
#property copyright "OkiSignal"
#property version   "2.00"
#property strict

#include <OkiSignal/CommonDefs.mqh>
#include <OkiSignal/ATRUtils.mqh>

//--- Input Parameters: EMA
input int    InpFastEMA        = 9;        // Fast EMA Period
input int    InpSlowEMA        = 21;       // Slow EMA Period

//--- Input Parameters: Filters
input int    InpADXPeriod      = 14;       // ADX Period
input double InpADXMin         = 20.0;     // ADX minimum (trend strength)
input int    InpRSIPeriod      = 14;       // RSI Period
input double InpRSIBuyMin      = 50.0;     // RSI min for BUY
input double InpRSISellMax     = 50.0;     // RSI max for SELL
input int    InpADRPeriod      = 14;       // ADR Period (days)
input double InpADRThreshold   = 70.0;     // Max ADR Consumed (%)
input int    InpStartHour      = 7;        // Trading start hour (server)
input int    InpEndHour        = 21;       // Trading end hour (server)

//--- Input Parameters: Entry Mode
input bool   InpUsePullback    = true;     // Use pullback entry (vs immediate)
input int    InpPullbackBars   = 5;        // Max bars to wait for pullback

//--- Input Parameters: Risk & Levels
input double InpRiskPercent    = 1.0;      // Risk per trade (%)
input int    InpATRPeriod      = 14;       // ATR Period
input double InpSLMult         = 1.0;      // SL multiplier (ATR)
input double InpTP1Mult        = 1.5;      // TP1 multiplier (ATR)
input double InpTP2Mult        = 3.0;      // TP2 multiplier (ATR)
input double InpTP1ClosePct    = 50.0;     // TP1 partial close (%)

//--- Input Parameters: Trading
input int    InpMagic          = MAGIC_EMA_ADR;
input string InpTradeComment   = "OkiEMA";

//--- Indicator Handles
int g_fastEMAHandle;
int g_slowEMAHandle;
int g_adxHandle;
int g_rsiHandle;

//--- Crossover state for pullback entry
int    g_crossDirection;    // 1=golden, -1=dead, 0=none
int    g_crossBarCount;     // bars since crossover

//--- TP1 management state
double g_tp1Level;
double g_tp2Level;
double g_tp1Lot;

//+------------------------------------------------------------------+
int OnInit()
{
   g_fastEMAHandle = iMA(_Symbol, PERIOD_M15, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_slowEMAHandle = iMA(_Symbol, PERIOD_M15, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_adxHandle     = iADX(_Symbol, PERIOD_M15, InpADXPeriod);
   g_rsiHandle     = iRSI(_Symbol, PERIOD_M15, InpRSIPeriod, PRICE_CLOSE);

   if(g_fastEMAHandle == INVALID_HANDLE || g_slowEMAHandle == INVALID_HANDLE ||
      g_adxHandle == INVALID_HANDLE || g_rsiHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }

   g_crossDirection = 0;
   g_crossBarCount  = 0;
   g_tp1Level = 0;
   g_tp2Level = 0;
   g_tp1Lot   = 0;

   Print("EMA_ADR v2 initialized: ", _Symbol,
         " EMA=", InpFastEMA, "/", InpSlowEMA,
         " ADX>", InpADXMin, " RSI=", InpRSIBuyMin,
         " Pullback=", InpUsePullback);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_fastEMAHandle != INVALID_HANDLE) IndicatorRelease(g_fastEMAHandle);
   if(g_slowEMAHandle != INVALID_HANDLE) IndicatorRelease(g_slowEMAHandle);
   if(g_adxHandle != INVALID_HANDLE)     IndicatorRelease(g_adxHandle);
   if(g_rsiHandle != INVALID_HANDLE)     IndicatorRelease(g_rsiHandle);
}

//+------------------------------------------------------------------+
//| Check for EMA crossover on just-closed bars                      |
//+------------------------------------------------------------------+
int DetectCrossover()
{
   double fastBuf[], slowBuf[];
   ArraySetAsSeries(fastBuf, true);
   ArraySetAsSeries(slowBuf, true);

   if(CopyBuffer(g_fastEMAHandle, 0, 1, 2, fastBuf) < 2) return 0;
   if(CopyBuffer(g_slowEMAHandle, 0, 1, 2, slowBuf) < 2) return 0;

   //--- Golden cross
   if(fastBuf[1] <= slowBuf[1] && fastBuf[0] > slowBuf[0])
      return 1;

   //--- Dead cross
   if(fastBuf[1] >= slowBuf[1] && fastBuf[0] < slowBuf[0])
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Check ADX filter (true = trend is strong enough)                 |
//+------------------------------------------------------------------+
bool CheckADX()
{
   double adxBuf[];
   ArraySetAsSeries(adxBuf, true);
   if(CopyBuffer(g_adxHandle, 0, 1, 1, adxBuf) < 1) return false;

   if(adxBuf[0] < InpADXMin)
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Check RSI filter                                                 |
//+------------------------------------------------------------------+
bool CheckRSI(int direction)
{
   double rsiBuf[];
   ArraySetAsSeries(rsiBuf, true);
   if(CopyBuffer(g_rsiHandle, 0, 1, 1, rsiBuf) < 1) return false;

   if(direction == 1 && rsiBuf[0] < InpRSIBuyMin)
      return false;
   if(direction == -1 && rsiBuf[0] > InpRSISellMax)
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Check ADR exhaustion filter                                      |
//+------------------------------------------------------------------+
bool CheckADRFilter()
{
   double ratio = ADRRatio(_Symbol, InpADRPeriod);
   if(ratio * 100.0 > InpADRThreshold)
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Check time filter                                                |
//+------------------------------------------------------------------+
bool CheckTimeFilter()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour)
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Check pullback: price touches fast EMA after crossover           |
//+------------------------------------------------------------------+
bool CheckPullback(int direction)
{
   if(!InpUsePullback) return true;

   double fastBuf[];
   ArraySetAsSeries(fastBuf, true);
   if(CopyBuffer(g_fastEMAHandle, 0, 1, 1, fastBuf) < 1) return false;

   double low1   = iLow(_Symbol, PERIOD_M15, 1);
   double high1  = iHigh(_Symbol, PERIOD_M15, 1);
   double close1 = iClose(_Symbol, PERIOD_M15, 1);

   if(direction == 1)
   {
      //--- BUY: price dipped to or below fast EMA, then closed above
      if(low1 <= fastBuf[0] && close1 > fastBuf[0])
         return true;
   }
   else if(direction == -1)
   {
      //--- SELL: price spiked to or above fast EMA, then closed below
      if(high1 >= fastBuf[0] && close1 < fastBuf[0])
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check all filters                                                |
//+------------------------------------------------------------------+
bool PassAllFilters(int direction)
{
   if(!CheckTimeFilter())   return false;
   if(!CheckADX())          return false;
   if(!CheckRSI(direction)) return false;
   if(!CheckADRFilter())    return false;
   return true;
}

//+------------------------------------------------------------------+
void ExecuteEntry(ENUM_SIGNAL_DIR dir)
{
   double entryPrice = (dir == SIGNAL_BUY) ?
      SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
      SymbolInfoDouble(_Symbol, SYMBOL_BID);

   OkiLevels lv = CalcLevels(_Symbol, dir, entryPrice,
                              InpATRPeriod, InpSLMult, InpTP1Mult,
                              InpTP2Mult, InpTP1ClosePct, InpRiskPercent);

   if(lv.lotSize <= 0 || lv.atrValue == 0) return;

   double initialTP = (lv.tp1Lot > 0) ? lv.tp1 : lv.tp2;
   ulong ticket = SendMarketOrder(_Symbol, dir, lv.lotSize,
                                   lv.sl, initialTP, InpMagic, InpTradeComment);

   if(ticket > 0)
   {
      g_tp1Level = lv.tp1;
      g_tp2Level = lv.tp2;
      g_tp1Lot   = lv.tp1Lot;

      Print("EMA_ADR v2 entry: ", (dir == SIGNAL_BUY ? "BUY" : "SELL"),
            " ", _Symbol, " @ ", entryPrice,
            " SL=", lv.sl, "(", DoubleToString(lv.slPips, 1), "p)",
            " TP1=", lv.tp1, "(", DoubleToString(lv.tp1Pips, 1), "p)",
            " TP2=", lv.tp2, "(", DoubleToString(lv.tp2Pips, 1), "p)");
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   //--- TP1 management (every tick)
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

   //--- New bar only
   if(!IsNewBar(_Symbol, PERIOD_M15)) return;

   //--- Skip if in position
   if(HasOpenPosition(_Symbol, InpMagic)) return;

   //--- Reset TP state
   g_tp1Level = 0;
   g_tp2Level = 0;
   g_tp1Lot   = 0;

   //--- Detect new crossover
   int cross = DetectCrossover();
   if(cross != 0)
   {
      g_crossDirection = cross;
      g_crossBarCount = 0;

      //--- Immediate entry mode (no pullback)
      if(!InpUsePullback)
      {
         if(PassAllFilters(cross))
         {
            ENUM_SIGNAL_DIR dir = (cross == 1) ? SIGNAL_BUY : SIGNAL_SELL;
            ExecuteEntry(dir);
            g_crossDirection = 0;
         }
         return;
      }
   }

   //--- Pullback entry mode: wait for pullback after crossover
   if(g_crossDirection != 0)
   {
      g_crossBarCount++;

      //--- Expired
      if(g_crossBarCount > InpPullbackBars)
      {
         g_crossDirection = 0;
         return;
      }

      //--- Check pullback + all filters
      if(CheckPullback(g_crossDirection) && PassAllFilters(g_crossDirection))
      {
         ENUM_SIGNAL_DIR dir = (g_crossDirection == 1) ? SIGNAL_BUY : SIGNAL_SELL;
         Print("Pullback entry after ", g_crossBarCount, " bars");
         ExecuteEntry(dir);
         g_crossDirection = 0;
      }
   }
}
//+------------------------------------------------------------------+

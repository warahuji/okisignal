//+------------------------------------------------------------------+
//|                                              MTFStructure.mq5    |
//|                                              OkiSignal Project   |
//|  Strategy: H4 trend + M15 structure break (BOS) for trend entry  |
//|  Magic: 102                                                       |
//+------------------------------------------------------------------+
#property copyright "OkiSignal"
#property version   "1.00"
#property strict

#include "../include/CommonDefs.mqh"
#include "../include/ATRUtils.mqh"

//--- Input Parameters: Strategy
input int    InpH4EMAPeriod   = 50;      // H4 EMA Period (trend filter)
input int    InpSwingBars     = 5;       // Swing detection bars (left/right)
input int    InpMaxSwingAge   = 50;      // Max bars to look back for swings

//--- Input Parameters: Risk & Levels
input double InpRiskPercent   = 1.0;
input int    InpATRPeriod     = 14;
input double InpSLMult        = 1.5;
input double InpTP1Mult       = 1.0;
input double InpTP2Mult       = 2.0;
input double InpTP1ClosePct   = 50.0;

//--- Input Parameters: Trading
input int    InpMagic         = MAGIC_MTF_STRUCTURE;
input string InpTradeComment  = "OkiMTF";

//--- Handles
int g_h4EMAHandle;

//--- Swing tracking
double g_lastSwingHigh;
double g_lastSwingLow;
double g_prevSwingHigh;
double g_prevSwingLow;

//--- TP1 management
double g_tp1Level;
double g_tp2Level;
double g_tp1Lot;

//+------------------------------------------------------------------+
int OnInit()
{
   g_h4EMAHandle = iMA(_Symbol, PERIOD_H4, InpH4EMAPeriod, 0,
                        MODE_EMA, PRICE_CLOSE);
   if(g_h4EMAHandle == INVALID_HANDLE)
   {
      Print("Failed to create H4 EMA handle");
      return INIT_FAILED;
   }

   g_lastSwingHigh = 0;
   g_lastSwingLow  = 0;
   g_prevSwingHigh = 0;
   g_prevSwingLow  = 0;
   g_tp1Level = 0;
   g_tp2Level = 0;
   g_tp1Lot   = 0;

   Print("MTFStructure initialized: ", _Symbol, " H4 EMA=", InpH4EMAPeriod,
         " SwingBars=", InpSwingBars);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_h4EMAHandle != INVALID_HANDLE) IndicatorRelease(g_h4EMAHandle);
}

//+------------------------------------------------------------------+
//| Get H4 trend direction: 1=bullish, -1=bearish, 0=unknown        |
//+------------------------------------------------------------------+
int GetH4Trend()
{
   double emaBuf[];
   ArraySetAsSeries(emaBuf, true);
   if(CopyBuffer(g_h4EMAHandle, 0, 0, 1, emaBuf) < 1) return 0;

   double h4Close = iClose(_Symbol, PERIOD_H4, 0);
   if(h4Close == 0) return 0;

   if(h4Close > emaBuf[0]) return 1;   // bullish
   if(h4Close < emaBuf[0]) return -1;  // bearish
   return 0;
}

//+------------------------------------------------------------------+
//| Detect swing highs and lows on M15                               |
//+------------------------------------------------------------------+
void DetectSwings()
{
   int lookback = InpSwingBars + 1; // the swing bar itself needs N bars after it

   for(int i = lookback; i < InpMaxSwingAge; i++)
   {
      //--- Check swing high
      double high_i = iHigh(_Symbol, PERIOD_M15, i);
      bool isSwingHigh = true;

      for(int j = 1; j <= InpSwingBars; j++)
      {
         if(iHigh(_Symbol, PERIOD_M15, i - j) >= high_i ||
            iHigh(_Symbol, PERIOD_M15, i + j) >= high_i)
         {
            isSwingHigh = false;
            break;
         }
      }

      if(isSwingHigh && high_i > 0)
      {
         if(g_lastSwingHigh == 0)
            g_lastSwingHigh = high_i;
         else if(high_i != g_lastSwingHigh && g_prevSwingHigh == 0)
         {
            g_prevSwingHigh = high_i;
         }
      }

      //--- Check swing low
      double low_i = iLow(_Symbol, PERIOD_M15, i);
      bool isSwingLow = true;

      for(int j = 1; j <= InpSwingBars; j++)
      {
         if(iLow(_Symbol, PERIOD_M15, i - j) <= low_i ||
            iLow(_Symbol, PERIOD_M15, i + j) <= low_i)
         {
            isSwingLow = false;
            break;
         }
      }

      if(isSwingLow && low_i > 0)
      {
         if(g_lastSwingLow == 0)
            g_lastSwingLow = low_i;
         else if(low_i != g_lastSwingLow && g_prevSwingLow == 0)
         {
            g_prevSwingLow = low_i;
         }
      }

      //--- Stop if we have both pairs
      if(g_prevSwingHigh > 0 && g_prevSwingLow > 0) break;
   }
}

//+------------------------------------------------------------------+
//| Check for Break of Structure (BOS)                               |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CheckBOS(int h4Trend)
{
   double close1 = iClose(_Symbol, PERIOD_M15, 1); // just closed bar

   //--- Bullish BOS: H4 bullish + M15 close above last swing high
   //    Pullback condition: last swing high < prev swing high
   if(h4Trend == 1 && g_lastSwingHigh > 0 && g_prevSwingHigh > 0)
   {
      if(g_lastSwingHigh < g_prevSwingHigh && close1 > g_lastSwingHigh)
      {
         Print("Bullish BOS: close ", close1, " > swing high ", g_lastSwingHigh,
               " (pullback from ", g_prevSwingHigh, ")");
         return SIGNAL_BUY;
      }
   }

   //--- Bearish BOS: H4 bearish + M15 close below last swing low
   if(h4Trend == -1 && g_lastSwingLow > 0 && g_prevSwingLow > 0)
   {
      if(g_lastSwingLow > g_prevSwingLow && close1 < g_lastSwingLow)
      {
         Print("Bearish BOS: close ", close1, " < swing low ", g_lastSwingLow,
               " (pullback from ", g_prevSwingLow, ")");
         return SIGNAL_SELL;
      }
   }

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
void ExecuteEntry(ENUM_SIGNAL_DIR dir)
{
   double entryPrice = (dir == SIGNAL_BUY) ?
      SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
      SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- SL at swing level
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double atr = GetATR(_Symbol, PERIOD_M15, InpATRPeriod, 1);
   double structureSL;

   if(dir == SIGNAL_BUY)
      structureSL = g_lastSwingLow > 0 ? g_lastSwingLow : entryPrice - atr * InpSLMult;
   else
      structureSL = g_lastSwingHigh > 0 ? g_lastSwingHigh : entryPrice + atr * InpSLMult;

   //--- Ensure minimum SL distance of 1.0x ATR
   double minSLDist = atr * 1.0;
   if(MathAbs(entryPrice - structureSL) < minSLDist)
   {
      if(dir == SIGNAL_BUY)
         structureSL = entryPrice - minSLDist;
      else
         structureSL = entryPrice + minSLDist;
   }

   OkiLevels lv = CalcLevels(_Symbol, dir, entryPrice,
                              InpATRPeriod, InpSLMult, InpTP1Mult,
                              InpTP2Mult, InpTP1ClosePct, InpRiskPercent);
   if(lv.lotSize <= 0) return;

   //--- Override SL with structure-based SL
   lv.sl = NormalizeDouble(structureSL, digits);
   lv.lotSize = CalcLotSize(_Symbol, entryPrice, lv.sl, InpRiskPercent);
   if(lv.lotSize <= 0) return;

   double initialTP = (lv.tp1Lot > 0) ? lv.tp1 : lv.tp2;
   ulong ticket = SendMarketOrder(_Symbol, dir, lv.lotSize,
                                   lv.sl, initialTP, InpMagic, InpTradeComment);
   if(ticket > 0)
   {
      g_tp1Level = lv.tp1;
      g_tp2Level = lv.tp2;
      g_tp1Lot   = lv.tp1Lot;
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

   //--- Reset TP state
   g_tp1Level = 0;
   g_tp2Level = 0;
   g_tp1Lot   = 0;

   //--- Get H4 trend
   int h4Trend = GetH4Trend();
   if(h4Trend == 0) return;

   //--- Detect M15 swings
   g_lastSwingHigh = 0;
   g_lastSwingLow  = 0;
   g_prevSwingHigh = 0;
   g_prevSwingLow  = 0;
   DetectSwings();

   //--- Check BOS
   ENUM_SIGNAL_DIR signal = CheckBOS(h4Trend);
   if(signal == SIGNAL_NONE) return;

   Print("MTFStructure signal: ", (signal == SIGNAL_BUY ? "BUY" : "SELL"),
         " H4 trend=", h4Trend, " on ", _Symbol);
   ExecuteEntry(signal);
}
//+------------------------------------------------------------------+

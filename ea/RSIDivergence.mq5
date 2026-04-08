//+------------------------------------------------------------------+
//|                                             RSIDivergence.mq5    |
//|                                              OkiSignal Project   |
//|  Strategy: RSI divergence at S/R levels with candle confirmation |
//|  Magic: 103                                                       |
//+------------------------------------------------------------------+
#property copyright "OkiSignal"
#property version   "1.00"
#property strict

#include "../include/CommonDefs.mqh"
#include "../include/ATRUtils.mqh"

//--- Input Parameters: Strategy
input int    InpRSIPeriod      = 14;       // RSI Period
input double InpRSIOverbought  = 70.0;     // RSI Overbought level
input double InpRSIOversold    = 30.0;     // RSI Oversold level
input double InpRSITolerance   = 5.0;      // RSI zone tolerance
input int    InpSRLookback     = 100;      // S/R detection lookback (bars)
input int    InpSRMinTouches   = 2;        // Min touches for S/R
input double InpSRZoneATRMult  = 0.5;      // S/R zone width (ATR mult)
input int    InpDivLookback    = 20;       // Max bars for divergence detection
input int    InpSwingBars      = 3;        // Swing detection bars

//--- Input Parameters: Risk & Levels
input double InpRiskPercent    = 1.0;
input int    InpATRPeriod      = 14;
input double InpSLMult         = 1.5;
input double InpTP1Mult        = 1.0;
input double InpTP2Mult        = 2.0;
input double InpTP1ClosePct    = 50.0;

//--- Input Parameters: Trading
input int    InpMagic          = MAGIC_RSI_DIVERGENCE;
input string InpTradeComment   = "OkiRSI";

//--- Handles
int g_rsiHandle;

//--- S/R levels
#define MAX_SR_LEVELS 10
double g_supportLevels[];
double g_resistanceLevels[];

//--- TP1 management
double g_tp1Level;
double g_tp2Level;
double g_tp1Lot;

//+------------------------------------------------------------------+
int OnInit()
{
   g_rsiHandle = iRSI(_Symbol, PERIOD_M15, InpRSIPeriod, PRICE_CLOSE);
   if(g_rsiHandle == INVALID_HANDLE)
   {
      Print("Failed to create RSI handle");
      return INIT_FAILED;
   }

   ArrayResize(g_supportLevels, 0);
   ArrayResize(g_resistanceLevels, 0);
   g_tp1Level = 0;
   g_tp2Level = 0;
   g_tp1Lot   = 0;

   Print("RSIDivergence initialized: ", _Symbol, " RSI=", InpRSIPeriod,
         " OB=", InpRSIOverbought, " OS=", InpRSIOversold);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
}

//+------------------------------------------------------------------+
//| Detect S/R levels from swing points                              |
//+------------------------------------------------------------------+
void DetectSRLevels()
{
   ArrayResize(g_supportLevels, 0);
   ArrayResize(g_resistanceLevels, 0);

   double atr = GetATR(_Symbol, PERIOD_M15, InpATRPeriod, 1);
   if(atr == 0) return;

   double zoneWidth = atr * InpSRZoneATRMult;

   //--- Collect all swing highs and lows
   double swingHighs[];
   double swingLows[];
   ArrayResize(swingHighs, 0);
   ArrayResize(swingLows, 0);

   for(int i = InpSwingBars; i < InpSRLookback - InpSwingBars; i++)
   {
      double high_i = iHigh(_Symbol, PERIOD_M15, i);
      double low_i  = iLow(_Symbol, PERIOD_M15, i);

      //--- Swing high check
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
      if(isSwingHigh)
      {
         int sz = ArraySize(swingHighs);
         ArrayResize(swingHighs, sz + 1);
         swingHighs[sz] = high_i;
      }

      //--- Swing low check
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
      if(isSwingLow)
      {
         int sz = ArraySize(swingLows);
         ArrayResize(swingLows, sz + 1);
         swingLows[sz] = low_i;
      }
   }

   //--- Cluster swing highs into resistance levels
   ClusterLevels(swingHighs, g_resistanceLevels, zoneWidth);

   //--- Cluster swing lows into support levels
   ClusterLevels(swingLows, g_supportLevels, zoneWidth);
}

//+------------------------------------------------------------------+
//| Cluster nearby price levels into S/R zones                       |
//+------------------------------------------------------------------+
void ClusterLevels(double &points[], double &levels[], double zoneWidth)
{
   ArrayResize(levels, 0);
   int pointCount = ArraySize(points);
   if(pointCount < InpSRMinTouches) return;

   bool used[];
   ArrayResize(used, pointCount);
   ArrayInitialize(used, false);

   for(int i = 0; i < pointCount; i++)
   {
      if(used[i]) continue;

      double sum = points[i];
      int count = 1;
      used[i] = true;

      for(int j = i + 1; j < pointCount; j++)
      {
         if(used[j]) continue;
         if(MathAbs(points[j] - points[i]) <= zoneWidth)
         {
            sum += points[j];
            count++;
            used[j] = true;
         }
      }

      if(count >= InpSRMinTouches)
      {
         int sz = ArraySize(levels);
         if(sz >= MAX_SR_LEVELS) break;
         ArrayResize(levels, sz + 1);
         levels[sz] = sum / count; // average of cluster
      }
   }
}

//+------------------------------------------------------------------+
//| Check if price is near an S/R level                              |
//| Returns: 1=near support, -1=near resistance, 0=neither          |
//+------------------------------------------------------------------+
int NearSRLevel(double price, double &srLevel)
{
   double atr = GetATR(_Symbol, PERIOD_M15, InpATRPeriod, 1);
   double proximity = atr * InpSRZoneATRMult;

   //--- Check support
   for(int i = 0; i < ArraySize(g_supportLevels); i++)
   {
      if(MathAbs(price - g_supportLevels[i]) <= proximity)
      {
         srLevel = g_supportLevels[i];
         return 1; // near support
      }
   }

   //--- Check resistance
   for(int i = 0; i < ArraySize(g_resistanceLevels); i++)
   {
      if(MathAbs(price - g_resistanceLevels[i]) <= proximity)
      {
         srLevel = g_resistanceLevels[i];
         return -1; // near resistance
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Find swing low index in RSI/Price within lookback                |
//+------------------------------------------------------------------+
bool FindSwingLow(double &priceBuf[], double &rsiBuf[], int startBar,
                  int lookback, int &idx1, int &idx2)
{
   //--- Find two most recent swing lows in price
   idx1 = -1;
   idx2 = -1;

   for(int i = 1; i < lookback - 1; i++)
   {
      if(priceBuf[i] < priceBuf[i - 1] && priceBuf[i] < priceBuf[i + 1])
      {
         if(idx1 == -1) idx1 = i;
         else if(idx2 == -1) { idx2 = i; break; }
      }
   }

   return (idx1 >= 0 && idx2 >= 0);
}

//+------------------------------------------------------------------+
//| Find swing high index in RSI/Price within lookback               |
//+------------------------------------------------------------------+
bool FindSwingHigh(double &priceBuf[], double &rsiBuf[], int startBar,
                   int lookback, int &idx1, int &idx2)
{
   idx1 = -1;
   idx2 = -1;

   for(int i = 1; i < lookback - 1; i++)
   {
      if(priceBuf[i] > priceBuf[i - 1] && priceBuf[i] > priceBuf[i + 1])
      {
         if(idx1 == -1) idx1 = i;
         else if(idx2 == -1) { idx2 = i; break; }
      }
   }

   return (idx1 >= 0 && idx2 >= 0);
}

//+------------------------------------------------------------------+
//| Check for RSI divergence                                         |
//| Returns SIGNAL_BUY (bullish div) / SIGNAL_SELL (bearish div)     |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CheckDivergence()
{
   double rsiBuf[], closeBuf[];
   ArraySetAsSeries(rsiBuf, true);
   ArraySetAsSeries(closeBuf, true);

   int bars = InpDivLookback + 2;
   if(CopyBuffer(g_rsiHandle, 0, 1, bars, rsiBuf) < bars) return SIGNAL_NONE;
   if(CopyClose(_Symbol, PERIOD_M15, 1, bars, closeBuf) < bars) return SIGNAL_NONE;

   //--- Bullish divergence: price lower low + RSI higher low (at support)
   int pIdx1, pIdx2;
   if(FindSwingLow(closeBuf, rsiBuf, 0, InpDivLookback, pIdx1, pIdx2))
   {
      if(closeBuf[pIdx1] < closeBuf[pIdx2] && // price lower low
         rsiBuf[pIdx1] > rsiBuf[pIdx2])        // RSI higher low
      {
         //--- RSI should be near oversold
         if(rsiBuf[pIdx1] <= InpRSIOversold + InpRSITolerance)
            return SIGNAL_BUY;
      }
   }

   //--- Bearish divergence: price higher high + RSI lower high (at resistance)
   if(FindSwingHigh(closeBuf, rsiBuf, 0, InpDivLookback, pIdx1, pIdx2))
   {
      if(closeBuf[pIdx1] > closeBuf[pIdx2] && // price higher high
         rsiBuf[pIdx1] < rsiBuf[pIdx2])        // RSI lower high
      {
         if(rsiBuf[pIdx1] >= InpRSIOverbought - InpRSITolerance)
            return SIGNAL_SELL;
      }
   }

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Check for reversal candle confirmation (engulfing or pin bar)    |
//+------------------------------------------------------------------+
bool IsReversalCandle(ENUM_SIGNAL_DIR dir)
{
   double open1  = iOpen(_Symbol, PERIOD_M15, 1);
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double high1  = iHigh(_Symbol, PERIOD_M15, 1);
   double low1   = iLow(_Symbol, PERIOD_M15, 1);
   double open2  = iOpen(_Symbol, PERIOD_M15, 2);
   double close2 = iClose(_Symbol, PERIOD_M15, 2);

   double body1 = MathAbs(close1 - open1);
   double range1 = high1 - low1;
   if(range1 == 0) return false;

   if(dir == SIGNAL_BUY)
   {
      //--- Bullish engulfing
      bool engulfing = (close1 > open1 && close2 < open2 &&
                        close1 > open2 && open1 < close2);

      //--- Bullish pin bar (long lower wick)
      double lowerWick = MathMin(open1, close1) - low1;
      bool pinBar = (lowerWick > body1 * 2.0 && close1 > open1);

      return (engulfing || pinBar);
   }
   else
   {
      //--- Bearish engulfing
      bool engulfing = (close1 < open1 && close2 > open2 &&
                        close1 < open2 && open1 > close2);

      //--- Bearish pin bar (long upper wick)
      double upperWick = high1 - MathMax(open1, close1);
      bool pinBar = (upperWick > body1 * 2.0 && close1 < open1);

      return (engulfing || pinBar);
   }
}

//+------------------------------------------------------------------+
void ExecuteEntry(ENUM_SIGNAL_DIR dir, double srLevel)
{
   double entryPrice = (dir == SIGNAL_BUY) ?
      SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
      SymbolInfoDouble(_Symbol, SYMBOL_BID);

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double atr = GetATR(_Symbol, PERIOD_M15, InpATRPeriod, 1);

   //--- SL: beyond S/R level
   double sl;
   if(dir == SIGNAL_BUY)
      sl = srLevel - atr * 0.5;
   else
      sl = srLevel + atr * 0.5;

   //--- Minimum SL distance
   if(MathAbs(entryPrice - sl) < atr * 1.0)
   {
      if(dir == SIGNAL_BUY) sl = entryPrice - atr * 1.0;
      else sl = entryPrice + atr * 1.0;
   }
   sl = NormalizeDouble(sl, digits);

   double lot = CalcLotSize(_Symbol, entryPrice, sl, InpRiskPercent);
   if(lot <= 0) return;

   //--- Conservative TP for counter-trend
   double tp1 = (dir == SIGNAL_BUY) ?
      NormalizeDouble(entryPrice + atr * InpTP1Mult, digits) :
      NormalizeDouble(entryPrice - atr * InpTP1Mult, digits);
   double tp2 = (dir == SIGNAL_BUY) ?
      NormalizeDouble(entryPrice + atr * InpTP2Mult, digits) :
      NormalizeDouble(entryPrice - atr * InpTP2Mult, digits);

   //--- Lot split
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

   //--- Update S/R levels periodically (every 20 bars)
   static int barCount = 0;
   barCount++;
   if(barCount >= 20 || ArraySize(g_supportLevels) == 0)
   {
      DetectSRLevels();
      barCount = 0;
   }

   //--- Check if price is near an S/R level
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double srLevel = 0;
   int nearSR = NearSRLevel(close1, srLevel);
   if(nearSR == 0) return;

   //--- Check divergence
   ENUM_SIGNAL_DIR divSignal = CheckDivergence();

   //--- Validate: bullish divergence at support, bearish at resistance
   if(nearSR == 1 && divSignal != SIGNAL_BUY) return;
   if(nearSR == -1 && divSignal != SIGNAL_SELL) return;

   //--- Confirmation candle
   if(!IsReversalCandle(divSignal)) return;

   Print("RSIDivergence signal: ", (divSignal == SIGNAL_BUY ? "BUY" : "SELL"),
         " at S/R ", srLevel, " on ", _Symbol);
   ExecuteEntry(divSignal, srLevel);
}
//+------------------------------------------------------------------+

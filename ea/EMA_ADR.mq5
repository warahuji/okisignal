//+------------------------------------------------------------------+
//|                                                     EMA_ADR.mq5  |
//|                                              OkiSignal Project   |
//|  Strategy: EMA 20/50 crossover with ADR exhaustion filter        |
//|  Magic: 104                                                       |
//+------------------------------------------------------------------+
#property copyright "OkiSignal"
#property version   "1.00"
#property strict

#include "../include/CommonDefs.mqh"
#include "../include/ATRUtils.mqh"

//--- Input Parameters: Strategy
input int    InpFastEMA        = 20;       // Fast EMA Period
input int    InpSlowEMA        = 50;       // Slow EMA Period
input int    InpADRPeriod      = 14;       // ADR Period (days)
input double InpADRThreshold   = 70.0;     // Max ADR Consumed (%)
input double InpEMASpacingMult = 0.1;      // Min EMA Spacing (ATR multiple)

//--- Input Parameters: Risk & Levels
input double InpRiskPercent    = 1.0;      // Risk per trade (%)
input int    InpATRPeriod      = 14;       // ATR Period
input double InpSLMult         = 1.5;      // SL multiplier (ATR)
input double InpTP1Mult        = 1.0;      // TP1 multiplier (ATR)
input double InpTP2Mult        = 2.0;      // TP2 multiplier (ATR)
input double InpTP1ClosePct    = 50.0;     // TP1 partial close (%)

//--- Input Parameters: Trading
input int    InpMagic          = MAGIC_EMA_ADR; // Magic Number
input string InpTradeComment   = "OkiEMA";      // Order Comment

//--- Indicator Handles
int g_fastEMAHandle;
int g_slowEMAHandle;

//--- State for TP1 management
double g_tp1Level;
double g_tp2Level;
double g_tp1Lot;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_fastEMAHandle = iMA(_Symbol, PERIOD_M15, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_slowEMAHandle = iMA(_Symbol, PERIOD_M15, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(g_fastEMAHandle == INVALID_HANDLE || g_slowEMAHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA handles");
      return INIT_FAILED;
   }

   g_tp1Level = 0;
   g_tp2Level = 0;
   g_tp1Lot   = 0;

   Print("EMA_ADR initialized: ", _Symbol, " M15",
         " FastEMA=", InpFastEMA, " SlowEMA=", InpSlowEMA,
         " ADR%=", InpADRThreshold);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_fastEMAHandle != INVALID_HANDLE) IndicatorRelease(g_fastEMAHandle);
   if(g_slowEMAHandle != INVALID_HANDLE) IndicatorRelease(g_slowEMAHandle);
}

//+------------------------------------------------------------------+
//| Get EMA values for bar index                                     |
//+------------------------------------------------------------------+
bool GetEMAValues(int shift, double &fastEMA, double &slowEMA)
{
   double fastBuf[], slowBuf[];
   ArraySetAsSeries(fastBuf, true);
   ArraySetAsSeries(slowBuf, true);

   if(CopyBuffer(g_fastEMAHandle, 0, shift, 2, fastBuf) < 2) return false;
   if(CopyBuffer(g_slowEMAHandle, 0, shift, 2, slowBuf) < 2) return false;

   fastEMA = fastBuf[0];
   slowEMA = slowBuf[0];
   return true;
}

//+------------------------------------------------------------------+
//| Check for EMA crossover                                          |
//| Returns SIGNAL_BUY / SIGNAL_SELL / SIGNAL_NONE                  |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CheckCrossover()
{
   double fastBuf[], slowBuf[];
   ArraySetAsSeries(fastBuf, true);
   ArraySetAsSeries(slowBuf, true);

   //--- Need 2 bars: bar[1] (just closed) and bar[2] (previous)
   if(CopyBuffer(g_fastEMAHandle, 0, 1, 2, fastBuf) < 2) return SIGNAL_NONE;
   if(CopyBuffer(g_slowEMAHandle, 0, 1, 2, slowBuf) < 2) return SIGNAL_NONE;

   double fastPrev = fastBuf[1]; // bar[2]
   double slowPrev = slowBuf[1];
   double fastCurr = fastBuf[0]; // bar[1] (just closed)
   double slowCurr = slowBuf[0];

   //--- Golden cross: fast crosses above slow
   if(fastPrev <= slowPrev && fastCurr > slowCurr)
      return SIGNAL_BUY;

   //--- Dead cross: fast crosses below slow
   if(fastPrev >= slowPrev && fastCurr < slowCurr)
      return SIGNAL_SELL;

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Check ADR filter (true = OK to trade, false = skip)              |
//+------------------------------------------------------------------+
bool CheckADRFilter()
{
   double ratio = ADRRatio(_Symbol, InpADRPeriod);
   double pct = ratio * 100.0;

   if(pct > InpADRThreshold)
   {
      Print("ADR filter: consumed ", DoubleToString(pct, 1),
            "% > threshold ", DoubleToString(InpADRThreshold, 1), "% — skip");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check EMA spacing filter (true = OK, false = EMAs too close)     |
//+------------------------------------------------------------------+
bool CheckEMASpacing()
{
   double fastEMA, slowEMA;
   if(!GetEMAValues(1, fastEMA, slowEMA)) return false;

   double atr = GetATR(_Symbol, PERIOD_M15, InpATRPeriod, 1);
   if(atr == 0) return false;

   double spacing = MathAbs(fastEMA - slowEMA);
   double minSpacing = atr * InpEMASpacingMult;

   if(spacing < minSpacing)
   {
      Print("EMA spacing filter: ", DoubleToString(spacing, _Digits),
            " < min ", DoubleToString(minSpacing, _Digits), " — skip");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Execute entry                                                    |
//+------------------------------------------------------------------+
void ExecuteEntry(ENUM_SIGNAL_DIR dir)
{
   double entryPrice;
   if(dir == SIGNAL_BUY)
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   else
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   OkiLevels lv = CalcLevels(_Symbol, dir, entryPrice,
                              InpATRPeriod, InpSLMult, InpTP1Mult,
                              InpTP2Mult, InpTP1ClosePct, InpRiskPercent);

   if(lv.lotSize <= 0 || lv.atrValue == 0)
   {
      Print("CalcLevels failed — no trade");
      return;
   }

   //--- Set initial TP to TP1 (Logger will see this)
   double initialTP = lv.tp1;
   if(lv.tp1Lot <= 0) // can't split, use TP2 directly
      initialTP = lv.tp2;

   ulong ticket = SendMarketOrder(_Symbol, dir, lv.lotSize,
                                   lv.sl, initialTP, InpMagic, InpTradeComment);

   if(ticket > 0)
   {
      //--- Save state for TP1 management
      g_tp1Level = lv.tp1;
      g_tp2Level = lv.tp2;
      g_tp1Lot   = lv.tp1Lot;

      Print("EMA_ADR entry: ", (dir == SIGNAL_BUY ? "BUY" : "SELL"),
            " ", _Symbol, " @ ", entryPrice,
            " SL=", lv.sl, " (", DoubleToString(lv.slPips, 1), " pips)",
            " TP1=", lv.tp1, " (", DoubleToString(lv.tp1Pips, 1), " pips)",
            " TP2=", lv.tp2, " (", DoubleToString(lv.tp2Pips, 1), " pips)",
            " Lot=", lv.lotSize);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- TP1 management (every tick)
   if(HasOpenPosition(_Symbol, InpMagic) && g_tp1Lot > 0)
   {
      ManageTP1(_Symbol, InpMagic, g_tp1Level, g_tp2Level, g_tp1Lot);

      //--- Check if partial close happened (tp1Lot becomes 0)
      ulong posTicket = GetPositionTicket(_Symbol, InpMagic);
      if(posTicket > 0 && PositionSelectByTicket(posTicket))
      {
         double currentTP = PositionGetDouble(POSITION_TP);
         int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
         if(NormalizeDouble(currentTP, digits) == NormalizeDouble(g_tp2Level, digits))
            g_tp1Lot = 0; // TP1 already managed
      }
   }

   //--- Signal evaluation only on new M15 bar
   if(!IsNewBar(_Symbol, PERIOD_M15)) return;

   //--- Skip if already in position
   if(HasOpenPosition(_Symbol, InpMagic)) return;

   //--- Reset TP1 state
   g_tp1Level = 0;
   g_tp2Level = 0;
   g_tp1Lot   = 0;

   //--- Check crossover
   ENUM_SIGNAL_DIR signal = CheckCrossover();
   if(signal == SIGNAL_NONE) return;

   //--- Apply filters
   if(!CheckADRFilter()) return;
   if(!CheckEMASpacing()) return;

   //--- Execute
   Print("EMA_ADR signal: ", (signal == SIGNAL_BUY ? "BUY" : "SELL"),
         " on ", _Symbol);
   ExecuteEntry(signal);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                  CommonDefs.mqh  |
//|                                              OkiSignal Project   |
//+------------------------------------------------------------------+
#ifndef COMMON_DEFS_MQH
#define COMMON_DEFS_MQH

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

#endif

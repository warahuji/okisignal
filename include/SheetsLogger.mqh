//+------------------------------------------------------------------+
//|                                              SheetsLogger.mqh    |
//|                                              OkiSignal Project   |
//|  WebRequest to Google Apps Script for Sheets logging             |
//+------------------------------------------------------------------+
#ifndef SHEETS_LOGGER_MQH
#define SHEETS_LOGGER_MQH

#include "CommonDefs.mqh"
#include "DiscordWebhook.mqh" // for JsonEscape()

//+------------------------------------------------------------------+
//| Send data to Google Apps Script webhook                          |
//+------------------------------------------------------------------+
bool SendToSheets(string sheetsUrl, string jsonPayload)
{
   if(sheetsUrl == "" || StringLen(sheetsUrl) < 10) return false;

   //--- Skip in backtest
   if((bool)MQLInfoInteger(MQL_TESTER))
   {
      Print("[Sheets] Skipped in backtest");
      return true;
   }

   char post[];
   char result[];
   string headers = "Content-Type: application/json\r\n";

   int len = StringToCharArray(jsonPayload, post, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(post, len - 1);

   string resultHeaders;
   int res = WebRequest("POST", sheetsUrl, headers, 10000, post,
                        result, resultHeaders);

   //--- Google Apps Script returns 302 redirect on success sometimes
   if(res == 200 || res == 302)
      return true;

   string errBody = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   Print("[Sheets] Failed: HTTP ", res, " | ", errBody);
   return false;
}

//+------------------------------------------------------------------+
//| Log new signal to Google Sheets                                  |
//+------------------------------------------------------------------+
bool SheetsLogSignal(string sheetsUrl, SignalData &sig)
{
   string ts = TimeToString(sig.time, TIME_DATE | TIME_SECONDS);

   string json = "{"
      "\"action\":\"new_signal\","
      "\"timestamp\":\"" + JsonEscape(ts) + "\","
      "\"ticket\":\"" + IntegerToString((int)sig.ticket) + "\","
      "\"magic\":" + IntegerToString(sig.magic) + ","
      "\"strategy\":\"" + JsonEscape(sig.strategy) + "\","
      "\"symbol\":\"" + JsonEscape(sig.symbol) + "\","
      "\"direction\":\"" + JsonEscape(sig.direction) + "\","
      "\"entry\":" + DoubleToString(sig.entry, 5) + ","
      "\"sl\":" + DoubleToString(sig.sl, 5) + ","
      "\"tp1\":" + DoubleToString(sig.tp1, 5) + ","
      "\"tp2\":" + DoubleToString(sig.tp2, 5) + ","
      "\"volume\":" + DoubleToString(sig.volume, 2) +
      "}";

   return SendToSheets(sheetsUrl, json);
}

//+------------------------------------------------------------------+
//| Log signal close to Google Sheets                                |
//+------------------------------------------------------------------+
bool SheetsLogClose(string sheetsUrl, CloseData &cd)
{
   string json = "{"
      "\"action\":\"close_signal\","
      "\"ticket\":\"" + IntegerToString((int)cd.ticket) + "\","
      "\"closePrice\":" + DoubleToString(cd.closePrice, 5) + ","
      "\"profit\":" + DoubleToString(cd.profit, 2) + ","
      "\"profitPips\":" + DoubleToString(cd.profitPips, 1) + ","
      "\"closeReason\":\"" + JsonEscape(cd.closeReason) + "\","
      "\"duration\":" + IntegerToString(cd.durationMin) +
      "}";

   return SendToSheets(sheetsUrl, json);
}

//+------------------------------------------------------------------+
//| Log weekly report to Google Sheets                               |
//+------------------------------------------------------------------+
bool SheetsLogWeekly(string sheetsUrl, string weekEnding,
                     int totalTrades, double winRate,
                     double totalPips, double profitFactor,
                     string bestStrat, string worstStrat)
{
   string json = "{"
      "\"action\":\"weekly_report\","
      "\"weekEnding\":\"" + JsonEscape(weekEnding) + "\","
      "\"totalTrades\":" + IntegerToString(totalTrades) + ","
      "\"winRate\":" + DoubleToString(winRate, 1) + ","
      "\"totalPips\":" + DoubleToString(totalPips, 1) + ","
      "\"profitFactor\":" + DoubleToString(profitFactor, 2) + ","
      "\"bestStrategy\":\"" + JsonEscape(bestStrat) + "\","
      "\"worstStrategy\":\"" + JsonEscape(worstStrat) + "\""
      "}";

   return SendToSheets(sheetsUrl, json);
}

#endif

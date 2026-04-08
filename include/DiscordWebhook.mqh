//+------------------------------------------------------------------+
//|                                            DiscordWebhook.mqh    |
//|                                              OkiSignal Project   |
//|  WebRequest wrapper for Discord webhook                          |
//+------------------------------------------------------------------+
#ifndef DISCORD_WEBHOOK_MQH
#define DISCORD_WEBHOOK_MQH

//--- Color constants for embeds
#define COLOR_GREEN  3066993   // #2ECC71 — buy / profit
#define COLOR_RED    15158332  // #E74C3C — sell / loss
#define COLOR_BLUE   3447003   // #3498DB — info / report
#define COLOR_GOLD   15844367  // #F1C40F — warning

//+------------------------------------------------------------------+
//| Send raw JSON payload to Discord webhook                         |
//+------------------------------------------------------------------+
bool SendDiscordWebhook(string webhookUrl, string jsonPayload)
{
   if(webhookUrl == "" || StringLen(webhookUrl) < 10) return false;

   //--- Skip in backtest
   if((bool)MQLInfoInteger(MQL_TESTER))
   {
      Print("[Discord] Skipped in backtest: ", StringSubstr(jsonPayload, 0, 100));
      return true;
   }

   char post[];
   char result[];
   string headers = "Content-Type: application/json\r\n";

   //--- Convert string to char array (remove trailing null)
   int len = StringToCharArray(jsonPayload, post, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(post, len - 1);

   string resultHeaders;
   int res = WebRequest("POST", webhookUrl, headers, 5000, post,
                        result, resultHeaders);

   if(res == 200 || res == 204)
      return true;

   //--- Rate limit handling
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
//| Escape JSON string (minimal: quotes and backslashes)             |
//+------------------------------------------------------------------+
string JsonEscape(string s)
{
   string result = s;
   StringReplace(result, "\\", "\\\\");
   StringReplace(result, "\"", "\\\"");
   StringReplace(result, "\n", "\\n");
   StringReplace(result, "\r", "");
   StringReplace(result, "\t", "\\t");
   return result;
}

//+------------------------------------------------------------------+
//| Build a simple embed JSON with fields                            |
//+------------------------------------------------------------------+
string BuildEmbed(string title, int color, string fieldsJson,
                  string footer = "OkiSignal • M15", string timestamp = "")
{
   if(timestamp == "")
      timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);

   //--- Format timestamp to ISO 8601
   string iso = timestamp;
   StringReplace(iso, ".", "-");
   // "2026-04-08 14:30:00" → "2026-04-08T14:30:00Z"
   if(StringFind(iso, "T") < 0)
      StringReplace(iso, " ", "T");
   if(StringFind(iso, "Z") < 0)
      iso += "Z";

   string json = "{\"embeds\":[{"
      "\"title\":\"" + JsonEscape(title) + "\","
      "\"color\":" + IntegerToString(color) + ","
      "\"fields\":[" + fieldsJson + "],"
      "\"footer\":{\"text\":\"" + JsonEscape(footer) + "\"},"
      "\"timestamp\":\"" + iso + "\""
      "}]}";

   return json;
}

//+------------------------------------------------------------------+
//| Build a single embed field JSON                                  |
//+------------------------------------------------------------------+
string EmbedField(string name, string value, bool isInline = true)
{
   return "{\"name\":\"" + JsonEscape(name) + "\","
          "\"value\":\"" + JsonEscape(value) + "\","
          "\"inline\":" + (isInline ? "true" : "false") + "}";
}

#endif

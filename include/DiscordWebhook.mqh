//+------------------------------------------------------------------+
//|                                            DiscordWebhook.mqh    |
//|                                              OkiSignal Project   |
//|  WebRequest wrapper for Discord webhook                          |
//+------------------------------------------------------------------+
#ifndef DISCORD_WEBHOOK_MQH
#define DISCORD_WEBHOOK_MQH

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

#endif

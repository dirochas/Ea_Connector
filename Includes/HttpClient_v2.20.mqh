//+------------------------------------------------------------------+
//|                                                   HttpClient.mqh |
//| Cliente HTTP para comunicação com Supabase                       |
//+------------------------------------------------------------------+

#include "Logger_v2.20.mqh" //update to Version v2.20

//+------------------------------------------------------------------+
// Enviar dados para Supabase
//+------------------------------------------------------------------+
void SendToSupabase(string jsonData, string serverURL)
{
   bool isIdle = (StringFind(jsonData, "\"status\":\"IDLE\"") >= 0);
   
   // Logs do envio apenas se necessário
   if(!isIdle || g_LoggingLevel >= LOG_ALL)
   {
      if(!isIdle) LogSubSeparator("ENVIO SUPABASE");
      LogPrint(isIdle ? LOG_ALL : LOG_ALL, "HTTP", "URL: " + serverURL);
      LogPrint(isIdle ? LOG_ALL : LOG_ALL, "HTTP", "Tamanho dos dados: " + IntegerToString(StringLen(jsonData)) + " caracteres");
      LogPrint(isIdle ? LOG_ALL : LOG_ALL, "HTTP", "Fazendo requisição HTTP POST...");
   }
   
   string headers = "Content-Type: application/json\r\n";
   
   char post[];
   char result[];
   string resultHeaders;
   
   // Converter string para array de bytes
   StringToCharArray(jsonData, post, 0, WHOLE_ARRAY);
   ArrayResize(post, ArraySize(post) - 1); // Remove null terminator
   
   // Fazer requisição HTTP POST
   int timeout = 10000; // 10 segundos
   int res = WebRequest("POST", serverURL, headers, timeout, post, result, resultHeaders);
   
   // LOG INTELIGENTE DE CONEXÃO
   LogConnectionSmart(res == 200, res, "Envio para Supabase");
   
   if(res == 200)
   {
      if(g_LoggingLevel >= LOG_ALL)
      {
         string response = CharArrayToString(result);
         LogPrint(LOG_ALL, "RESPONSE", "Resposta do servidor: " + response);
      }
   }
   else if(res == -1)
   {
      LogPrint(LOG_CRITICAL, "ERROR", "URL não permitida no WebRequest!");
      LogPrint(LOG_CRITICAL, "SOLUTION", "Adicione esta URL nas configurações:");
      LogPrint(LOG_CRITICAL, "SOLUTION", "Ferramentas → Opções → Expert Advisors → WebRequest");
      LogPrint(LOG_CRITICAL, "SOLUTION", "URL: https://kgrlcsimdszbrkcwjpke.supabase.co");
   }
   else if(res == 0)
   {
      LogPrint(LOG_CRITICAL, "ERROR", "Timeout ou sem conexão com internet");
   }
   else
   {
      LogPrint(LOG_CRITICAL, "ERROR", "Erro HTTP: " + IntegerToString(res));
      LogPrint(LOG_ALL, "DEBUG", "Headers de resposta: " + resultHeaders);
      if(ArraySize(result) > 0)
      {
         string errorResponse = CharArrayToString(result);
         LogPrint(LOG_ALL, "DEBUG", "Resposta de erro: " + errorResponse);
      }
   }
}


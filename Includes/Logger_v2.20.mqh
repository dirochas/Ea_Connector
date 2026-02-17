//+------------------------------------------------------------------+
//|                                                       Logger.mqh |
//| Sistema de logging inteligente para EA             Version v2.20 |
//+------------------------------------------------------------------+


// SISTEMA DE LOGS MELHORADO
enum LogLevel {
   LOG_NONE = 0,           // Sem logs
   LOG_ERRORS_ONLY = 1,    // Apenas erros e eventos críticos
   LOG_ESSENTIAL = 2,      // Logs essenciais + erros
   LOG_CRITICAL = 3,       // Logs críticos + essenciais + erros
   LOG_ALL = 4             // Todos os logs
};

// Variável global interna do Logger
LogLevel g_LoggingLevel = LOG_ERRORS_ONLY;

// SISTEMA INTELIGENTE ANTI-SPAM
datetime g_lastHeartbeat = 0;
datetime g_lastConnectionLog = 0;
datetime g_lastTimerLog = 0;
bool g_connectionEstablished = false;
bool g_firstRunCompleted = false;
bool g_initialStatusShown = false;
string g_lastAccountStatus = "";
int g_consecutiveSuccesses = 0;

//+------------------------------------------------------------------+
// Função para definir o nível de logging
//+------------------------------------------------------------------+
void SetLoggingLevel(LogLevel level)
{
   g_LoggingLevel = level;
}

//+------------------------------------------------------------------+
// SISTEMA DE LOGGING ULTRA-INTELIGENTE
//+------------------------------------------------------------------+
void LogPrint(LogLevel level, string category, string message)
{
   if(g_LoggingLevel == LOG_NONE) return;
   if(level > g_LoggingLevel) return;
   
   string prefix = "";
   switch(level) {
      case LOG_ERRORS_ONLY: prefix = "🚨 "; break;
      case LOG_ESSENTIAL:   prefix = "📌 "; break;
      case LOG_CRITICAL:    prefix = "🚨 "; break;
      case LOG_ALL:         prefix = "💬 "; break;
   }
   
   Print(prefix + "[" + category + "] " + message);
}

//+------------------------------------------------------------------+
// LOG PARA INICIALIZAÇÃO (sempre mostra informações básicas)
//+------------------------------------------------------------------+
void LogInitialization(string eaName, string version, int timerSeconds)
{
   if(g_LoggingLevel == LOG_NONE) return;
   
   LogSeparator("EA INICIALIZAÇÃO");
   LogPrint(LOG_ERRORS_ONLY, "INIT", "EA Trading Data Sender INICIADO");
   LogPrint(LOG_ERRORS_ONLY, "INIT", "Versão: " + version + " - Sistema Inteligente MQL5");
   LogPrint(LOG_ERRORS_ONLY, "TIMER", "Timer configurado para " + IntegerToString(timerSeconds) + " segundos");
   LogPrint(LOG_ERRORS_ONLY, "INIT", "Compilado dados iniciais...");
}

//+------------------------------------------------------------------+
// LOG PARA STATUS INICIAL DE CONEXÃO
//+------------------------------------------------------------------+
void LogInitialConnectionStatus()
{
   if(g_LoggingLevel == LOG_NONE) return;
   if(g_initialStatusShown) return;
   
   LogPrint(LOG_ERRORS_ONLY, "INIT", "Conexão status: Envio e recebimento OK");
   LogPrint(LOG_ERRORS_ONLY, "SYSTEM", "✅ A partir de agora apenas erros críticos e comandos remotos serão exibidos");
   g_initialStatusShown = true;
}

//+------------------------------------------------------------------+
// LOG INTELIGENTE PARA TIMER (ultra-silencioso em ERRORS_ONLY)
//+------------------------------------------------------------------+
void LogTimerSmart(string message)
{
   if(g_LoggingLevel >= LOG_ALL)
   {
      LogPrint(LOG_ALL, "TIMER", message);
   }
   else if(g_LoggingLevel >= LOG_ESSENTIAL && (!g_firstRunCompleted || TimeCurrent() - g_lastTimerLog >= 600)) // 10 minutos
   {
      LogPrint(LOG_ESSENTIAL, "TIMER", message);
      g_lastTimerLog = TimeCurrent();
   }
   // ERRORS_ONLY: Completamente silencioso para timer
}

//+------------------------------------------------------------------+
// LOG INTELIGENTE PARA CONEXÃO (ultra-silencioso em ERRORS_ONLY)
//+------------------------------------------------------------------+
void LogConnectionSmart(bool success, int responseCode, string context)
{
   if(!success || responseCode != 200)
   {
      // SEMPRE mostrar erros (todos os níveis)
      LogPrint(LOG_ERRORS_ONLY, "ERROR", "❌ " + context + " FALHOU - Código: " + IntegerToString(responseCode));
      g_consecutiveSuccesses = 0;
      g_connectionEstablished = false;
   }
   else
   {
      g_consecutiveSuccesses++;
      
      if(!g_connectionEstablished)
      {
         // Primeira conexão bem-sucedida
         if(g_LoggingLevel >= LOG_ESSENTIAL)
         {
            LogPrint(LOG_ESSENTIAL, "SUCCESS", "✅ Conexão estabelecida com sucesso!");
            LogPrint(LOG_ESSENTIAL, "SUCCESS", "Sistema funcionando normalmente - logs reduzidos ativados");
         }
         
         // Para ERRORS_ONLY, mostrar status inicial mais limpo
         LogInitialConnectionStatus();
         
         g_connectionEstablished = true;
         g_lastConnectionLog = TimeCurrent();
      }
      else if(g_LoggingLevel >= LOG_ALL)
      {
         // Mostrar todos os sucessos apenas em modo DEBUG
         LogPrint(LOG_ALL, "SUCCESS", context + " - OK");
      }
      else if(g_LoggingLevel >= LOG_ESSENTIAL && TimeCurrent() - g_lastConnectionLog >= 600) // Heartbeat a cada 10 minutos
      {
         LogPrint(LOG_ESSENTIAL, "HEARTBEAT", "💓 Sistema ativo - " + IntegerToString(g_consecutiveSuccesses) + " envios consecutivos OK");
         g_lastConnectionLog = TimeCurrent();
         g_consecutiveSuccesses = 0; // Reset contador
      }
      // ERRORS_ONLY: Silencioso após conexão inicial
   }
}

//+------------------------------------------------------------------+
// LOG INTELIGENTE PARA CONTA (silencioso em ERRORS_ONLY)
//+------------------------------------------------------------------+
void LogAccountSmart(string accountInfo)
{
   if(g_LoggingLevel >= LOG_ALL)
   {
      LogPrint(LOG_ALL, "ACCOUNT", accountInfo);
   }
   else if(g_LoggingLevel >= LOG_ESSENTIAL && (g_lastAccountStatus != accountInfo || !g_firstRunCompleted))
   {
      LogPrint(LOG_ESSENTIAL, "ACCOUNT", accountInfo);
      g_lastAccountStatus = accountInfo;
   }
   // ERRORS_ONLY: Silencioso para dados de conta
}

//+------------------------------------------------------------------+
// LOG INTELIGENTE PARA COMANDOS (silencioso em ERRORS_ONLY, exceto comandos importantes)
//+------------------------------------------------------------------+
void LogCommandSmart(string message, bool isImportant = false)
{
   if(isImportant)
   {
      // Comandos importantes sempre aparecem (todos os níveis)
      LogPrint(LOG_ERRORS_ONLY, "COMMANDS", message);
   }
   else if(g_LoggingLevel >= LOG_ALL)
   {
      LogPrint(LOG_ALL, "COMMANDS", message);
   }
   else if(g_LoggingLevel >= LOG_ESSENTIAL && !g_firstRunCompleted)
   {
      LogPrint(LOG_ESSENTIAL, "COMMANDS", message);
   }
   // ERRORS_ONLY: Silencioso para verificações rotineiras
}

//+------------------------------------------------------------------+
// LOG PARA FECHAMENTO REMOTO (sempre visível)
//+------------------------------------------------------------------+
void LogRemoteCloseCommand(string commandId, int totalPositions)
{
   if(g_LoggingLevel == LOG_NONE) return;
   
   LogPrint(LOG_ERRORS_ONLY, "COMMAND", "🎯 Fechamento remoto detectado");
   LogPrint(LOG_ERRORS_ONLY, "COMMAND", "Fechando " + IntegerToString(totalPositions) + " ordens");
   LogPrint(LOG_ERRORS_ONLY, "COMMAND", "ID do comando: " + commandId);
}

//+------------------------------------------------------------------+
// LOG PARA RESULTADO DO FECHAMENTO (sempre visível)
//+------------------------------------------------------------------+
void LogRemoteCloseResult(int closedCount, int failedCount, int totalCount)
{
   if(g_LoggingLevel == LOG_NONE) return;
   
   if(failedCount == 0)
   {
      LogPrint(LOG_ERRORS_ONLY, "SUCCESS", "✅ Fechamento concluído com " + IntegerToString(closedCount) + "/" + IntegerToString(totalCount) + " ordens - TODAS FECHADAS!");
   }
   else if(closedCount > 0)
   {
      LogPrint(LOG_ERRORS_ONLY, "PARTIAL", "⚠️ Fechamento parcialmente concluído com " + IntegerToString(closedCount) + "/" + IntegerToString(totalCount) + " ordens");
   }
   else
   {
      LogPrint(LOG_ERRORS_ONLY, "ERROR", "❌ Fechamento falhou - 0/" + IntegerToString(totalCount) + " ordens fechadas");
   }
}

//+------------------------------------------------------------------+
// MARCAR PRIMEIRA EXECUÇÃO COMO COMPLETA
//+------------------------------------------------------------------+
void MarkFirstRunCompleted()
{
   if(!g_firstRunCompleted)
   {
      g_firstRunCompleted = true;
      if(g_LoggingLevel >= LOG_ESSENTIAL)
      {
         LogPrint(LOG_ESSENTIAL, "SYSTEM", "🎯 Primeira execução completa - sistema otimizado ativado");
      }
   }
}

void LogSeparator(string category)
{
   if(g_LoggingLevel == LOG_NONE) return;
   if(g_LoggingLevel >= LOG_ESSENTIAL || !g_firstRunCompleted)
   {
      Print("═══════════════════════════════════════════════════════════");
      Print("                    " + category);
      Print("═══════════════════════════════════════════════════════════");
   }
}

void LogSubSeparator(string subcategory)
{
   if(g_LoggingLevel == LOG_NONE) return;
   if(g_LoggingLevel >= LOG_ALL || !g_firstRunCompleted)
   {
      Print("─────────────── " + subcategory + " ───────────────");
   }
}


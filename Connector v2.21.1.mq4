//+-------------------------------+
//|              EA_Connector.mq4 |
//|                 Versão 2.21.1 |
//|   COMANDOS REMOTOS CORRIGIDOS |
//+-------------------------------+

#property copyright  "MrBot © 2025"
#property version    "2.21"
#define   EA_VERSION "2.21.1" // ✅ COMANDOS REMOTOS CORRIGIDOS
#property strict

#include "Includes/VpsIdentifier_MQL4_v2.20.mqh"  // BIBLIOTECA VPS

input string ServerURL_MT2 = "https://kgrlcsimdszbrkcwjpke.supabase.co";// Adicione esta URL em configurações → WebRequest
string ServerURL = "https://kgrlcsimdszbrkcwjpke.supabase.co/functions/v1/trading-data";

// NOVA VARIÁVEL PARA IDENTIFICAÇÃO DO USUÁRIO
input string UserEmail = "usuario@exemplo.com"; // Email do usuário para vinculação da conta

input bool UseTimer = true; // Usar Timer (true) ou Ticks (false)	

// INTERVALOS DINÂMICOS BASEADOS EM ORDENS ABERTAS
input int SendIntervalYesOrders = 6; // Intervalo quando há ordens abertas (segundos)
input int SendIntervalNoOrders = 240; // Intervalo quando não há ordens (segundos) - 4 minutos

// Variável dinâmica que será atualizada baseada na existência de ordens
int SendIntervalSeconds = 6;

// NOVAS VARIÁVEIS PARA POLLING DE COMANDOS
input bool EnableCommandPolling = true; // Habilitar polling de comandos
input int CommandCheckIntervalSeconds = 7; // Intervalo para verificar comandos (segundos)
input int IdleCommandCheckIntervalSeconds = 400; // Intervalo quando não há ordens (segundos)

// SISTEMA DE LOGS MELHORADO - VERSÃO 2.21
enum LogLevel
{
    LOG_NONE = 0,           // Sem logs
    LOG_ERRORS_ONLY = 1,    // Apenas erros críticos e comandos remotos
    LOG_ESSENTIAL = 2,      // Logs essenciais
    LOG_CRITICAL = 3,       // Logs críticos + essenciais
    LOG_ALL = 4             // Todos os logs
};

input LogLevel LoggingLevel = LOG_ERRORS_ONLY; // Nível de logging

// VARIÁVEL NOVA PARA VPS
bool EnableVpsIdentification = true; // Habilitar identificação de VPS

datetime lastSendTime = 0;
datetime lastCommandCheck = 0;
datetime lastIdleLog = 0;
datetime lastConnectionLog = 0;
datetime lastHeartbeat = 0;
bool lastHadOrders = false; // Para detectar mudanças de estado
int lastOrderCount = -1;    // Para detectar mudanças na quantidade de ordens

// SISTEMA INTELIGENTE ANTI-SPAM
bool idleLogAlreadyShown = false;
bool activeLogAlreadyShown = false;
bool connectionEstablished = false;
int consecutiveSuccessfulSends = 0;
int consecutiveFailures = 0;

bool enviadoZeroOrdens = false;

// VARIÁVEIS GLOBAIS PARA VPS - v2.21 EXPANDIDO
string g_VpsId = "";
string g_VpsHostname = "";  
string g_VpsPublicIP = "";  

// 🆕 NOVA VARIÁVEL PARA CONTROLE DE EXECUÇÃO ÚNICA DE COMANDOS
string lastProcessedCommandId = "";

//+------------------------------------------------------------------+
// 💰 NOVAS FUNÇÕES v2.21.1 - PROFITNET E CASH
//+------------------------------------------------------------------+

//+--------------+
// 🔧 FUNÇÃO CORRIGIDA: Converter string para minúsculas (Warning Fix)
//+--------------+
string StringToLowerFixed(string str)
{
    string result = "";
    for(int i = 0; i < StringLen(str); i++)
    {
        string ch = StringSubstr(str, i, 1);
        int charCode = StringGetChar(ch, 0);
        if(charCode >= 65 && charCode <= 90) // A-Z
            charCode += 32; // Converter para minúscula
        result += CharToStr(charCode);
    }
    return result;
}

//+--------------+
// 🔧 NOVA FUNÇÃO: Mapear tipos de deal para tipos normalizados
//+--------------+
string MapDealTypeToNormalized(double profit, string comment)
{
    // Converter comment para minúsculas (MQL4 compatible) - WARNING CORRIGIDO
    string commentLower = StringToLowerFixed(comment);
    
    string result = "";
    
    if(profit >= 0)
    {
        if(StringFind(commentLower, "deposit") >= 0) result = "DEPOSIT";
        else if(StringFind(commentLower, "bonus") >= 0) result = "BONUS";
        else if(StringFind(commentLower, "credit") >= 0) result = "BONUS";
        else result = "DEPOSIT";
    }
    else
    {
        if(StringFind(commentLower, "withdraw") >= 0) result = "WITHDRAWAL";
        else if(StringFind(commentLower, "charge") >= 0) result = "CHARGE";
        else result = "WITHDRAWAL";
    }
    
    return result;
}

//+--------------+
// 🔧 NOVA FUNÇÃO: Verificar se é evento de caixa (MQL4 - baseado em comentário)
//+--------------+
bool IsCashDeal(string comment, double profit)
{
    string commentLower = StringToLowerFixed(comment); // WARNING CORRIGIDO
    
    return (StringFind(commentLower, "deposit") >= 0 || 
            StringFind(commentLower, "withdrawal") >= 0 ||
            StringFind(commentLower, "withdraw") >= 0 ||
            StringFind(commentLower, "bonus") >= 0 ||
            StringFind(commentLower, "credit") >= 0 ||
            StringFind(commentLower, "charge") >= 0 ||
            StringFind(commentLower, "balance") >= 0 ||
            StringFind(commentLower, "correction") >= 0);
}

//+--------------+
// 🔧 FUNÇÃO CORRIGIDA: Escape JSON robusto
//+--------------+
string JsonEscape(string s)
{
    string out = s;
    StringReplace(out, "\\", "\\\\");
    StringReplace(out, "\"", "\\\"");
    StringReplace(out, "\r", "\\r");
    StringReplace(out, "\n", "\\n");
    StringReplace(out, "\t", "\\t");
    return out;
}

//+--------------+
// 💰 NOVA FUNÇÃO: Construir item de histórico JSON com profitNet (MQL4)
//+--------------+
string BuildHistoryItemJson(int ticket)
{
    if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
        return "";
    
    double profit = OrderProfit();
    string comment = OrderComment();
    int expertId = OrderMagicNumber();
    datetime dealTime = OrderCloseTime();
    
    // 💰 NOVO: Calcular profit líquido (profit + commission + swap)
    double commission = OrderCommission();
    double swap = OrderSwap();
    double profitNet = profit + commission + swap;
    
    bool isTrade = (OrderType() == OP_BUY || OrderType() == OP_SELL);
    bool isCash = IsCashDeal(comment, profit);
    
    if(!isTrade && !isCash) 
    {
        return ""; // Ignorar outros tipos
    }
    
    string json = "{";
    json += "\"ticket\":" + IntegerToString(ticket) + ",";
    
    if(isCash)
    {
        // 🆕 EVENTO DE CAIXA - profitNet = profit (sem swap/comissão)
        string normType = MapDealTypeToNormalized(profit, comment);
        
        json += "\"symbol\":\"CASH\",";
        json += "\"type\":\"" + normType + "\",";
        json += "\"volume\":0,";
        json += "\"openPrice\":0,";
        json += "\"closePrice\":0,";
        json += "\"profit\":" + DoubleToString(profit, 2) + ",";
        json += "\"profitNet\":" + DoubleToString(profit, 2) + ","; // 💰 CASH: profitNet = profit
        json += "\"openTime\":\"" + TimeToString(dealTime, TIME_DATE|TIME_MINUTES) + "\",";
        json += "\"closeTime\":\"" + TimeToString(dealTime, TIME_DATE|TIME_MINUTES) + "\",";
    }
    else
    {
        // 🔄 TRADE NORMAL (BUY/SELL) - profitNet inclui swap e comissão
        string typeStr = (OrderType() == OP_BUY ? "BUY" : "SELL");
        double price = OrderClosePrice();
        json += "\"symbol\":\"" + OrderSymbol() + "\",";
        json += "\"type\":\"" + typeStr + "\",";
        json += "\"volume\":" + DoubleToString(OrderLots(), 2) + ",";
        json += "\"openPrice\":" + DoubleToString(OrderOpenPrice(), 5) + ",";
        json += "\"closePrice\":" + DoubleToString(price, 5) + ",";
        json += "\"profit\":" + DoubleToString(profit, 2) + ",";
        json += "\"profitNet\":" + DoubleToString(profitNet, 2) + ","; // 💰 TRADE: profit + commission + swap
        json += "\"openTime\":\"" + TimeToString(OrderOpenTime(), TIME_DATE|TIME_MINUTES) + "\",";
        json += "\"closeTime\":\"" + TimeToString(OrderCloseTime(), TIME_DATE|TIME_MINUTES) + "\",";
    }
    
    // Campos finais
    string escapedComment = JsonEscape(comment);
    json += "\"comment\":\"" + escapedComment + "\",";
    json += "\"expertId\":" + IntegerToString(expertId);
    json += "}";
    
    return json;
}

//+------------------------------------------------------------------+
// SISTEMA DE LOGGING INTELIGENTE - MANTIDO v2.21
//+------------------------------------------------------------------+
void LogPrint(LogLevel level, string category, string message)
{
    if(LoggingLevel == LOG_NONE)
        return;
    if(level > LoggingLevel)
        return;

    string prefix = "";
    switch(level)
    {
        case LOG_ERRORS_ONLY:
            prefix = "🚨 ";
            break;
        case LOG_ESSENTIAL:
            prefix = "📌 ";
            break;
        case LOG_CRITICAL:
            prefix = "🚨 ";
            break;
        case LOG_ALL:
            prefix = "💬 ";
            break;
    }

    Print(prefix + "[" + category + "] " + message);
}

//+--------------+
void VPS_LogPrint(int level, string category, string message)
{
    LogLevel logLevel;
    switch(level)
    {
        case 1: logLevel = LOG_ERRORS_ONLY; break;
        case 2: logLevel = LOG_ESSENTIAL; break;
        case 3: logLevel = LOG_CRITICAL; break;
        case 4: logLevel = LOG_ALL; break;
        default: logLevel = LOG_ALL; break;
    }
    
    LogPrint(logLevel, category, message);
}

//+--------------+
void LogSeparator(string category)
{
    if(LoggingLevel <= LOG_ERRORS_ONLY)
        return;
    Print("═══════════════════════════════════════════════════════════");
    Print("                    " + category);
    Print("═══════════════════════════════════════════════════════════");
}

//+--------------+
void LogSubSeparator(string subcategory)
{
    if(LoggingLevel <= LOG_ERRORS_ONLY)
        return;
    Print("─────────────── " + subcategory + " ───────────────");
}

// FUNÇÕES INTELIGENTES PARA LOGS ESPECÍFICOS (MANTIDAS)
void LogConnectionSmart(bool success, int responseCode, string operation)
{
    if(success && responseCode == 200)
    {
        consecutiveSuccessfulSends++;
        consecutiveFailures = 0;

        if(!connectionEstablished)
        {
            LogPrint(LOG_ERRORS_ONLY, "INIT", "Conexão status: Envio e recebimento OK");
            LogPrint(LOG_ERRORS_ONLY, "SYSTEM", "✅ A partir de agora apenas erros críticos e comandos remotos serão exibidos");
            connectionEstablished = true;
            lastConnectionLog = TimeCurrent();
        }
        else if(LoggingLevel >= LOG_ALL)
        {
            LogPrint(LOG_ALL, "HTTP", "Código de resposta: " + IntegerToString(responseCode));
        }
    }
    else
    {
        consecutiveFailures++;
        consecutiveSuccessfulSends = 0;
        LogPrint(LOG_ERRORS_ONLY, "ERROR", "❌ " + operation + " FALHOU - Código: " + IntegerToString(responseCode));

        if(consecutiveFailures >= 3)
        {
            LogPrint(LOG_ERRORS_ONLY, "ERROR", "❌ " + IntegerToString(consecutiveFailures) + " falhas consecutivas - verificar conexão");
        }
    }

    if(connectionEstablished && TimeCurrent() - lastHeartbeat >= 600 && consecutiveSuccessfulSends >= 200)
    {
        LogPrint(LOG_ERRORS_ONLY, "HEARTBEAT", "💓 Sistema ativo - " + IntegerToString(consecutiveSuccessfulSends) + " envios consecutivos OK");
        lastHeartbeat = TimeCurrent();
    }
}

//+--------------+
void LogRemoteCloseCommand(string commandId, int totalOrders)
{
    LogPrint(LOG_ERRORS_ONLY, "COMMAND", "🎯 Fechamento remoto detectado");
    LogPrint(LOG_ERRORS_ONLY, "COMMAND", "Fechando " + IntegerToString(totalOrders) + " ordens");
    if(commandId != "")
        LogPrint(LOG_ERRORS_ONLY, "COMMAND", "ID do comando: " + commandId);
}

//+--------------+
void LogRemoteCloseResult(int closed, int failed, int total)
{
    if(failed == 0)
    {
        LogPrint(LOG_ERRORS_ONLY, "SUCCESS", "✅ Fechamento concluído com " + IntegerToString(closed) + "/" + IntegerToString(total) + " ordens - TODAS FECHADAS!");
    }
    else if(closed > 0)
    {
        LogPrint(LOG_ERRORS_ONLY, "PARTIAL", "⚠️ Fechamento parcialmente concluído com " + IntegerToString(closed) + "/" + IntegerToString(total) + " ordens");
    }
    else
    {
        LogPrint(LOG_ERRORS_ONLY, "ERROR", "❌ Fechamento falhou - 0/" + IntegerToString(total) + " ordens fechadas");
    }
}

//+------------------------------------------------------------------+
// 💰 FUNÇÃO PRINCIPAL ATUALIZADA: BuildJsonData COM PROFITNET v2.21.1
//+------------------------------------------------------------------+
string BuildJsonData()
{
    LogPrint(LOG_ALL, "JSON", "Construindo dados JSON v2.21.1...");

    string json = "{";

    // 💰 Account Info COM holderName
    json += "\"account\":{";
    json += "\"balance\":" + DoubleToString(AccountBalance(), 2) + ",";
    json += "\"equity\":" + DoubleToString(AccountEquity(), 2) + ",";
    json += "\"profit\":" + DoubleToString(AccountProfit(), 2) + ",";
    json += "\"accountNumber\":\"" + IntegerToString(AccountNumber()) + "\",";
    json += "\"server\":\"" + JsonEscape(AccountServer()) + "\",";
    json += "\"leverage\":" + IntegerToString(AccountLeverage()) + ",";
    json += "\"brokerTimezone\":\"" + GetBrokerTimezone() + "\",";
    json += "\"holderName\":\"" + JsonEscape(AccountName()) + "\""; // 💰 NOVO CAMPO
    json += "},";

    // LOG INTELIGENTE DA CONTA
    if(!connectionEstablished || LoggingLevel >= LOG_ESSENTIAL)
    {
        LogPrint(LOG_ESSENTIAL, "ACCOUNT", "Conta: " + IntegerToString(AccountNumber()) + " | Balance: $" + DoubleToString(AccountBalance(), 2));
    }

    // Margin Info - COM TRATAMENTO DE OVERFLOW
    double marginUsed = AccountMargin();
    double marginFree = AccountFreeMargin();
    double marginLevel = AccountMargin() == 0 ? 0 : (AccountEquity()/AccountMargin()*100);
    
    // 🚀 TRATAMENTO DE OVERFLOW: Limitar valores muito grandes
    if(marginUsed > 999999999.99) marginUsed = 999999999.99;
    if(marginFree > 999999999.99) marginFree = 999999999.99;
    if(marginLevel > 999999.99) marginLevel = 999999.99;
    
    marginUsed = NormalizeDouble(marginUsed, 2);
    marginFree = NormalizeDouble(marginFree, 2);
    marginLevel = NormalizeDouble(marginLevel, 2);
    
    json += "\"margin\":{";
    json += "\"used\":" + DoubleToString(marginUsed, 2) + ",";
    json += "\"free\":" + DoubleToString(marginFree, 2) + ",";
    json += "\"level\":" + DoubleToString(marginLevel, 2);
    json += "},";

    LogPrint(LOG_ALL, "MARGIN", "Usada: $" + DoubleToString(marginUsed, 2) + " | Livre: $" + DoubleToString(marginFree, 2));

    // 💰 Open Positions COM PROFITNET
    json += "\"positions\":[";
    int posCount = 0;
    int totalOrders = OrdersTotal();
    for(int i = 0; i < totalOrders; i++)
    {
        if(OrderSelect(i, SELECT_BY_POS) && OrderType() <= 1) // Only BUY/SELL
        {
            // 💰 NOVO: Calcular profit líquido para posições abertas
            double profitGross = OrderProfit();
            double commission = OrderCommission();
            double swap = OrderSwap();
            double profitNet = profitGross + commission + swap;
            
            if(posCount > 0)
                json += ",";
            json += "{";
            json += "\"ticket\":" + IntegerToString(OrderTicket()) + ",";
            json += "\"symbol\":\"" + JsonEscape(OrderSymbol()) + "\",";
            json += "\"type\":\"" + (OrderType() == OP_BUY ? "BUY" : "SELL") + "\",";
            json += "\"volume\":" + DoubleToString(OrderLots(), 2) + ",";
            json += "\"openPrice\":" + DoubleToString(OrderOpenPrice(), 5) + ",";
            json += "\"currentPrice\":" + DoubleToString(OrderType() == OP_BUY ? MarketInfo(OrderSymbol(), MODE_BID) : MarketInfo(OrderSymbol(), MODE_ASK), 5) + ",";
            json += "\"profit\":" + DoubleToString(profitGross, 2) + ",";
            json += "\"profitNet\":" + DoubleToString(profitNet, 2) + ","; // 💰 NOVO CAMPO
            json += "\"openTime\":\"" + TimeToString(OrderOpenTime(), TIME_DATE|TIME_MINUTES) + "\"";
            json += "}";
            posCount++;
        }
    }
    json += "],";

    // LOG INTELIGENTE DAS POSIÇÕES
    if(!connectionEstablished || LoggingLevel >= LOG_ESSENTIAL)
    {
        LogPrint(LOG_ESSENTIAL, "POSITIONS", "Posições abertas: " + IntegerToString(posCount));
    }

    // 💰 Trade History EXPANDIDO - 50 ITENS COM PROFITNET E CASH
    json += "\"history\":[";
    int histCount = 0;
    
    for(int i = OrdersHistoryTotal() - 1; i >= 0 && histCount < 50; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
        {
            double profit = OrderProfit();
            string comment = OrderComment();
            bool isTrade = (OrderType() == OP_BUY || OrderType() == OP_SELL);
            bool isCash = IsCashDeal(comment, profit);
            
            if(!isTrade && !isCash) continue;
            
            if(histCount > 0)
                json += ",";
            
            // 💰 NOVO: Calcular profit líquido no histórico
            double commission = OrderCommission();
            double swap = OrderSwap();
            double profitNet = isCash ? profit : (profit + commission + swap); // Cash não tem swap/comissão
            
            json += "{";
            json += "\"ticket\":" + IntegerToString(OrderTicket()) + ",";
            
            if(isCash)
            {
                string normType = MapDealTypeToNormalized(profit, comment);
                json += "\"symbol\":\"CASH\",";
                json += "\"type\":\"" + normType + "\",";
                json += "\"volume\":0,";
                json += "\"openPrice\":0,";
                json += "\"closePrice\":0,";
            }
            else
            {
                json += "\"symbol\":\"" + JsonEscape(OrderSymbol()) + "\",";
                json += "\"type\":\"" + (OrderType() == OP_BUY ? "BUY" : "SELL") + "\",";
                json += "\"volume\":" + DoubleToString(OrderLots(), 2) + ",";
                json += "\"openPrice\":" + DoubleToString(OrderOpenPrice(), 5) + ",";
                json += "\"closePrice\":" + DoubleToString(OrderClosePrice(), 5) + ",";
            }
            
            json += "\"profit\":" + DoubleToString(profit, 2) + ",";
            json += "\"profitNet\":" + DoubleToString(profitNet, 2) + ","; // 💰 NOVO CAMPO
            json += "\"openTime\":\"" + TimeToString(OrderOpenTime(), TIME_DATE|TIME_MINUTES) + "\",";
            json += "\"closeTime\":\"" + TimeToString(OrderCloseTime(), TIME_DATE|TIME_MINUTES) + "\",";
            json += "\"comment\":\"" + JsonEscape(comment) + "\",";
            json += "\"expertId\":" + IntegerToString(OrderMagicNumber());
            json += "}";
            histCount++;
        }
    }
    json += "],";

    // User Email
    json += "\"userEmail\":\"" + UserEmail + "\"";

    // ADICIONAR VPS ID SE DISPONÍVEL
    if(EnableVpsIdentification && g_VpsId != "")
    {
        json += ",\"vpsId\":\"" + g_VpsId + "\"";
    }

    // ✅ CAMPOS v2.21.1
    json += ",\"connectorVersion\":\"v" + EA_VERSION + "\"";
    if(EnableVpsIdentification)
    {
        json += ",\"hostname\":\"" + JsonEscape(g_VpsHostname) + "\"";
        json += ",\"publicIp\":\"" + JsonEscape(g_VpsPublicIP) + "\"";
    }

    json += "}";

    LogPrint(LOG_ALL, "HISTORY", "Histórico expandido: " + IntegerToString(histCount) + " itens (incluindo CASH)");
    LogPrint(LOG_ALL, "JSON", "JSON v2.21.1 construído com sucesso");

    return json;
}

//+------------------------------------------------------------------+
// 💰 FUNÇÃO IDLE ATUALIZADA COM PROFITNET v2.21.1
//+------------------------------------------------------------------+
void SendIdleStatusToSupabase()
{
    if(!idleLogAlreadyShown || LoggingLevel >= LOG_ALL)
    {
        LogPrint(LOG_ALL, "IDLE", "📡 Enviando status idle V" + EA_VERSION + " para servidor (mantendo conexão)...");
    }

    string jsonData = "{";
    
    // 💰 Account com holderName
    jsonData += "\"account\":{";
    jsonData += "\"balance\":" + DoubleToString(AccountBalance(), 2) + ",";
    jsonData += "\"equity\":" + DoubleToString(AccountEquity(), 2) + ",";
    jsonData += "\"profit\":0.00,";
    jsonData += "\"accountNumber\":\"" + IntegerToString(AccountNumber()) + "\",";
    jsonData += "\"server\":\"" + JsonEscape(AccountServer()) + "\",";
    jsonData += "\"leverage\":" + IntegerToString(AccountLeverage()) + ",";
    jsonData += "\"brokerTimezone\":\"" + GetBrokerTimezone() + "\",";
    jsonData += "\"holderName\":\"" + JsonEscape(AccountName()) + "\""; // 💰 NOVO
    jsonData += "},";
    
    jsonData += "\"margin\":{\"used\":0.00,\"free\":" + DoubleToString(AccountFreeMargin(), 2) + ",\"level\":0.00},";
    jsonData += "\"positions\":[],";
    
    // 💰 HISTÓRICO IDLE COM CASH E PROFITNET - 30 ITENS
    jsonData += "\"history\":[";
    int histCount = 0;
    
    for(int i = OrdersHistoryTotal()-1; i >= 0 && histCount < 30; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
        {
            string historyItem = BuildHistoryItemJson(OrderTicket());
            if(historyItem == "") continue; // Ignorar tipos não suportados
            
            if(histCount > 0) jsonData += ",";
            jsonData += historyItem;
            histCount++;
        }
    }
    jsonData += "],";
    
    jsonData += "\"userEmail\":\"" + UserEmail + "\",";
    jsonData += "\"status\":\"IDLE\"";

    // ✅ ADICIONAR VPS ID SE DISPONÍVEL
    if(EnableVpsIdentification && g_VpsId != "")
    {
        jsonData += ",\"vpsId\":\"" + g_VpsId + "\"";
    }

    // 💰 VERSÃO v2.21.1
    jsonData += ",\"connectorVersion\":\"v" + EA_VERSION + "\"";
    
    if(EnableVpsIdentification)
    {
        jsonData += ",\"hostname\":\"" + JsonEscape(g_VpsHostname) + "\"";
        jsonData += ",\"publicIp\":\"" + JsonEscape(g_VpsPublicIP) + "\"";
    }

    jsonData += "}";

    SendToSupabase(jsonData);
}

//+------------------------------------------------------------------+
// FUNÇÕES RESTANTES MANTIDAS E ATUALIZADAS v2.21.1
//+------------------------------------------------------------------+

//+--------------+
void SendToSupabase(string jsonData)
{
    bool isIdle = (StringFind(jsonData, "\"status\":\"IDLE\"") >= 0);

    // ✅ LOGS AJUSTADOS: LogSubSeparator movido para LOG_ESSENTIAL
    if(!isIdle || LoggingLevel >= LOG_ALL)
    {
        if(!isIdle && LoggingLevel >= LOG_ESSENTIAL)  // ✅ AJUSTE: Só mostra separador em LOG_ESSENTIAL+
            LogSubSeparator("ENVIO SUPABASE v." + EA_VERSION);
        LogPrint(isIdle ? LOG_ALL : LOG_ALL, "HTTP", "URL: " + ServerURL);
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
    int res = WebRequest("POST", ServerURL, headers, timeout, post, result, resultHeaders);

    // ✅ LOG INTELIGENTE DE CONEXÃO
    LogConnectionSmart(res == 200, res, "Envio para Supabase v" + EA_VERSION);

    if(res == 200)
    {
        if(!isIdle || LoggingLevel >= LOG_ALL)
        {
            LogPrint(isIdle ? LOG_ALL : LOG_ESSENTIAL, "SUCCESS", "✅ Dados v" + EA_VERSION + " enviados para Supabase com sucesso!");
        }
    }
    else if(res == -1)
    {
        LogPrint(LOG_ERRORS_ONLY, "ERROR", "❌ URL não permitida no WebRequest!");
        LogPrint(LOG_ERRORS_ONLY, "SOLUTION", "Adicione esta URL nas configurações:");
        LogPrint(LOG_ERRORS_ONLY, "SOLUTION", "Ferramentas → Opções → Expert Advisors → WebRequest");
        LogPrint(LOG_ERRORS_ONLY, "SOLUTION", ServerURL);
    }
    else
    {
        LogPrint(LOG_ERRORS_ONLY, "ERROR", "❌ Falha no envio v" + EA_VERSION + " - Código: " + IntegerToString(res));
    }
}

//+--------------+
// NOVA FUNÇÃO: Calcular fuso horário da corretora
//+--------------+
string GetBrokerTimezone()
{
    datetime serverTime = TimeCurrent();
    datetime localTime = TimeLocal();
    int offsetSeconds = (int)(serverTime - localTime);
    int offsetHours = offsetSeconds / 3600;
    
    string timezone = "UTC";
    if(offsetHours > 0)
        timezone += "+" + IntegerToString(offsetHours);
    else if(offsetHours < 0)
        timezone += IntegerToString(offsetHours);
    
    return timezone;
}

//+--------------+
// NOVA FUNÇÃO INTELIGENTE: Verificar se há necessidade de processar
//+--------------+
bool HasOpenOrdersOrPendingOrders()
{
    int openPositions = 0;
    int pendingOrders = 0;

    for(int i = 0; i < OrdersTotal(); i++)
    {
        if(OrderSelect(i, SELECT_BY_POS))
        {
            if(OrderType() <= 1) // BUY/SELL
                openPositions++;
            else
                pendingOrders++;
        }
    }

    return (openPositions > 0 || pendingOrders > 0);
}

//+--------------+
// 🔧 NOVA FUNÇÃO: Detectar fechamento imediato de ordens v2.21.1
//+--------------+
void DetectOrderClosureImmediate()
{
    bool hasOrders = HasOpenOrdersOrPendingOrders();
    int currentOrderCount = OrdersTotal();
    
    // 🎯 DETECÇÃO CRÍTICA: Nova ordem foi aberta AGORA
    if(!lastHadOrders && hasOrders)
    {
        LogPrint(LOG_ERRORS_ONLY, "WAKE_UP", "🚀 NOVA ORDEM DETECTADA! Enviando dados imediatamente (OnTick)");
        
        // Reset flag de zero ordens
        enviadoZeroOrdens = false;
        
        // Enviar dados completos imediatamente
        SendTradingDataIntelligent();
        lastSendTime = TimeCurrent();
        
        // Atualizar intervalo para modo com ordens
        UpdateDynamicInterval(true);
        
        // Atualizar variáveis de controle
        lastHadOrders = hasOrders;
        lastOrderCount = currentOrderCount;
        return;
    }
    
    // 🎯 DETECÇÃO CRÍTICA: Ordens foram fechadas AGORA - COM HISTÓRICO COMPLETO
    if(lastHadOrders && !hasOrders)
    {
        LogPrint(LOG_ERRORS_ONLY, "CLOSE_ALL", "🔴 FECHAMENTO DE ORDENS DETECTADO! Enviando dados com histórico completo");
        
        // Enviar dados COMPLETOS com histórico atualizado (não idle)
        SendTradingDataIntelligent();
        lastSendTime = TimeCurrent();
        
        // Atualizar intervalo para modo sem ordens
        UpdateDynamicInterval(false);
        
        // Marcar que será enviado zero ordens na próxima verificação timer
        enviadoZeroOrdens = false;
        
        // Atualizar variáveis de controle
        lastHadOrders = hasOrders;
        lastOrderCount = currentOrderCount;
        return;
    }
    
    // 🎯 DETECÇÃO: Mudança na quantidade de ordens (abertura/fechamento parcial)
    if(lastOrderCount != currentOrderCount && currentOrderCount > 0)
    {
        LogPrint(LOG_ERRORS_ONLY, "ORDER_CHANGE", "📊 MUDANÇA NA QUANTIDADE DE ORDENS DETECTADA! (" + 
                 IntegerToString(lastOrderCount) + " → " + IntegerToString(currentOrderCount) + ")");
        
        SendTradingDataIntelligent();
        lastSendTime = TimeCurrent();
        
        // Atualizar variáveis de controle
        lastHadOrders = hasOrders;
        lastOrderCount = currentOrderCount;
        return;
    }
    
    // Atualizar estado para próxima verificação (SEMPRE)
    lastHadOrders = hasOrders;
    lastOrderCount = currentOrderCount;
}

//+--------------+
// FUNÇÃO INTELIGENTE: Atualizar intervalo dinamicamente
//+--------------+
void UpdateDynamicInterval(bool hasOrders)
{
    int newInterval = hasOrders ? SendIntervalYesOrders : SendIntervalNoOrders;
    
    if(newInterval != SendIntervalSeconds)
    {
        SendIntervalSeconds = newInterval;
        if(UseTimer)
        {
            EventKillTimer();
            EventSetTimer(SendIntervalSeconds);
            LogPrint(LOG_ALL, "TIMER", "Intervalo atualizado para: " + IntegerToString(SendIntervalSeconds) + "s");
        }
        
        LogPrint(LOG_ALL, "INTERVAL", hasOrders ? "Com ordens - intervalo: " + IntegerToString(SendIntervalSeconds) + "s" : "Sem ordens - intervalo: " + IntegerToString(SendIntervalSeconds) + "s");
    }
}

//+--------------+
// 🔧 FUNÇÃO CORRIGIDA: Envio de dados com polling de comandos reativado v2.21.1
//+--------------+
void SendTradingDataIntelligent()
{
    int currentOrderCount = OrdersTotal();
    bool hasOrders = HasOpenOrdersOrPendingOrders();
    
    // NOVA LÓGICA: Atualizar intervalo dinamicamente baseado em ordens abertas
    UpdateDynamicInterval(hasOrders);

    // Detectar mudanças de estado
    bool stateChanged = (lastHadOrders != hasOrders) || (lastOrderCount != currentOrderCount);

    if(!hasOrders)
    {
        // SEM ORDENS - Modo econômico normal
        if(stateChanged || !idleLogAlreadyShown || TimeCurrent() - lastIdleLog >= 300)
        {
            if(stateChanged || !idleLogAlreadyShown)
            {
                if(LoggingLevel >= LOG_ESSENTIAL)
                    LogSubSeparator("MODO IDLE ATIVADO");
                LogPrint(LOG_ESSENTIAL, "IDLE", "Conta " + IntegerToString(AccountNumber()) + " sem ordens abertas");
                LogPrint(LOG_ESSENTIAL, "IDLE", "Balance: $" + DoubleToString(AccountBalance(), 2) + " | Equity: $" + DoubleToString(AccountEquity(), 2));
                LogPrint(LOG_ALL, "IDLE", "Logs reduzidos ativados - dados continuam sendo enviados");
                idleLogAlreadyShown = true;
                activeLogAlreadyShown = false;
            }
            else
            {
                LogPrint(LOG_ESSENTIAL, "IDLE", "Status idle - Balance: $" + DoubleToString(AccountBalance(), 2) + " | Equity: $" + DoubleToString(AccountEquity(), 2));
            }
            lastIdleLog = TimeCurrent();
        }

        SendIdleStatusToSupabase();
    }
    else
    {
        // COM ORDENS - Modo ativo
        if(stateChanged || !activeLogAlreadyShown)
        {
            if(!activeLogAlreadyShown)
            {
                if(LoggingLevel >= LOG_ESSENTIAL)
                    LogSubSeparator("MODO ATIVO");
                LogPrint(LOG_ESSENTIAL, "ACTIVE", "Detectadas " + IntegerToString(currentOrderCount) + " ordens - logs completos reativados");
                activeLogAlreadyShown = true;
                idleLogAlreadyShown = false;
            }
        }

        string jsonData = BuildJsonData();
        SendToSupabase(jsonData);
    }

    // Atualizar estado anterior
    lastHadOrders = hasOrders;
    lastOrderCount = currentOrderCount;
    lastSendTime = TimeCurrent();
    
    // 🔧 CORREÇÃO CRÍTICA: REATIVAR POLLING DE COMANDOS
    if(EnableCommandPolling)
    {
        int commandInterval = hasOrders ? CommandCheckIntervalSeconds : IdleCommandCheckIntervalSeconds;
        if(TimeCurrent() - lastCommandCheck >= commandInterval)
        {
            CheckForRemoteCommands(); // Função corrigida v2.21.1
            lastCommandCheck = TimeCurrent();
        }
    }
}

//+------------------------------------------------------------------+
// 🆕 FUNÇÕES DE COMANDOS REMOTOS CORRIGIDAS v2.21.1
//+------------------------------------------------------------------+

//+--------------+
// 🆕 NOVA FUNÇÃO: Extrair ID do comando (MQL4)
//+--------------+
string ExtractCommandId(string jsonResponse)
{
    LogPrint(LOG_ALL, "PARSE", "Extraindo ID do comando...");
    LogPrint(LOG_ALL, "PARSE", "JSON: " + jsonResponse);
    
    // Buscar por "id":"..." no JSON
    int idPos = StringFind(jsonResponse, "\"id\":\"");
    if(idPos >= 0)
    {
        LogPrint(LOG_ALL, "PARSE", "Padrão 'id' encontrado na posição: " + IntegerToString(idPos));
        idPos += 6; // Pular "id":"
        int endPos = StringFind(jsonResponse, "\"", idPos);
        if(endPos > idPos)
        {
            string commandId = StringSubstr(jsonResponse, idPos, endPos - idPos);
            LogPrint(LOG_ALL, "PARSE", "ID extraído: " + commandId);
            return commandId;
        }
        else
        {
            LogPrint(LOG_CRITICAL, "ERROR", "Não foi possível encontrar o fim do ID");
        }
    }
    else
    {
        LogPrint(LOG_CRITICAL, "ERROR", "Padrão 'id' não encontrado no JSON");
    }
    return "";
}

//+--------------+
// 🆕 NOVA FUNÇÃO: Atualizar status do comando (MQL4)
//+--------------+
void UpdateCommandStatus(string commandId, string status, string errorMessage)
{
    LogSubSeparator("ATUALIZAÇÃO STATUS");
    LogPrint(LOG_ESSENTIAL, "UPDATE", "Command ID: " + commandId + " | Status: " + status);
    
    string url = "https://kgrlcsimdszbrkcwjpke.supabase.co/functions/v1/update-command-status";
    string headers = "Content-Type: application/json\r\n";
    
    string jsonData = "{";
    jsonData += "\"commandId\":\"" + commandId + "\",";
    jsonData += "\"status\":\"" + status + "\"";
    if(errorMessage != "")
    {
        jsonData += ",\"errorMessage\":\"" + JsonEscape(errorMessage) + "\"";
    }
    jsonData += "}";
    
    LogPrint(LOG_ALL, "POST", "Dados: " + jsonData);
    
    char post[];
    char result[];
    string resultHeaders;
    
    StringToCharArray(jsonData, post, 0, WHOLE_ARRAY);
    ArrayResize(post, ArraySize(post) - 1);
    
    int res = WebRequest("POST", url, headers, 5000, post, result, resultHeaders);
    
    LogPrint(LOG_ESSENTIAL, "POST", "Código de resposta: " + IntegerToString(res));
    
    if(res == 200)
    {
        string response = CharArrayToString(result);
        LogPrint(LOG_ESSENTIAL, "SUCCESS", "Status atualizado com sucesso!");
        LogPrint(LOG_ALL, "RESPONSE", "Resposta: " + response);
    }
    else
    {
        LogPrint(LOG_CRITICAL, "ERROR", "Erro ao atualizar status. Código: " + IntegerToString(res));
        if(ArraySize(result) > 0)
        {
            string errorResponse = CharArrayToString(result);
            LogPrint(LOG_ALL, "DEBUG", "Resposta de erro: " + errorResponse);
        }
    }
}

//+--------------+
// 🔧 FUNÇÃO CORRIGIDA: Verificar comandos remotos v2.21.1
//+--------------+
void CheckForRemoteCommands()
{
    LogPrint(LOG_ESSENTIAL, "COMMANDS", "Verificando comandos para conta: " + IntegerToString(AccountNumber()));
    
    // ✅ CORREÇÃO 1: URL com parâmetro correto
    string commandUrl = "https://kgrlcsimdszbrkcwjpke.supabase.co/functions/v1/get-commands?accountNumber=" + IntegerToString(AccountNumber());
    LogPrint(LOG_ALL, "GET", "URL: " + commandUrl);
    
    string headers = "Content-Type: application/json\r\n";
    char post[];
    char result[];
    string resultHeaders;
    
    LogPrint(LOG_ALL, "GET", "Fazendo requisição GET...");
    int res = WebRequest("GET", commandUrl, headers, 5000, post, result, resultHeaders);
    
    // LOG INTELIGENTE DE CONEXÃO
    LogConnectionSmart(res == 200, res, "Verificação de comandos");
    
    if(res == 200)
    {
        string response = CharArrayToString(result);
        LogPrint(LOG_ALL, "RESPONSE", "Resposta completa: " + response);
        
        // ✅ CORREÇÃO 2: Parsing robusto como no MQL5
        if(StringFind(response, "\"commands\"") >= 0)
        {
            LogPrint(LOG_ALL, "PARSE", "Campo 'commands' encontrado");
            
            if(StringFind(response, "\"commands\":[]") >= 0)
            {
                LogPrint(LOG_ALL, "COMMANDS", "Nenhum comando pendente");
            }
            else
            {
                LogPrint(LOG_CRITICAL, "COMMANDS", "Comandos encontrados! Processando...");
                
                // Verificar especificamente por CLOSE_ALL
                if(StringFind(response, "CLOSE_ALL") >= 0)
                {
                    LogPrint(LOG_CRITICAL, "COMMAND", "COMANDO CLOSE_ALL ENCONTRADO!");
                    ProcessCloseAllCommand(response);
                }
                else
                {
                    LogPrint(LOG_ALL, "COMMAND", "Outros comandos encontrados, mas não CLOSE_ALL");
                }
            }
        }
        else
        {
            LogPrint(LOG_CRITICAL, "ERROR", "Campo 'commands' não encontrado na resposta");
        }
    }
    else if(res == -1)
    {
        LogPrint(LOG_CRITICAL, "ERROR", "URL não permitida no WebRequest!");
        LogPrint(LOG_CRITICAL, "SOLUTION", "Adicione estas URLs nas configurações:");
        LogPrint(LOG_CRITICAL, "SOLUTION", "Ferramentas → Opções → Expert Advisors → WebRequest");
        LogPrint(LOG_CRITICAL, "SOLUTION", "URLs: https://kgrlcsimdszbrkcwjpke.supabase.co e *.supabase.co");
    }
    else if(res == 0)
    {
        LogPrint(LOG_CRITICAL, "ERROR", "Timeout ou sem conexão");
    }
    else
    {
        LogPrint(LOG_CRITICAL, "ERROR", "Erro HTTP: " + IntegerToString(res));
        if(ArraySize(result) > 0)
        {
            string errorResponse = CharArrayToString(result);
            LogPrint(LOG_ALL, "DEBUG", "Resposta de erro: " + errorResponse);
        }
    }
}

//+--------------+
// 🔧 FUNÇÃO CORRIGIDA: Processar comando de fechamento v2.21.1
//+--------------+
void ProcessCloseAllCommand(string commandData)
{
    // ✅ CORREÇÃO 3: Extrair ID do comando
    string commandId = ExtractCommandId(commandData);
    
    // ✅ CORREÇÃO 4: Verificar execução única
    if(commandId != "" && commandId == lastProcessedCommandId)
    {
        LogPrint(LOG_CRITICAL, "DUPLICATE", "Comando já processado: " + commandId + " - IGNORANDO");
        return;
    }
    
    int totalOrders = OrdersTotal();
    LogRemoteCloseCommand(commandId, totalOrders);
    
    int closed = 0;
    int failed = 0;
    
    // Fechar todas as ordens abertas (MQL4)
    for(int i = totalOrders - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS) && OrderType() <= 1) // Apenas BUY/SELL
        {
            LogPrint(LOG_ALL, "PROCESS", "Fechando ordem: " + IntegerToString(OrderTicket()) + " | " + OrderSymbol());
            
            double closePrice = (OrderType() == OP_BUY) ? 
                               MarketInfo(OrderSymbol(), MODE_BID) : 
                               MarketInfo(OrderSymbol(), MODE_ASK);
            
            bool result = OrderClose(OrderTicket(), OrderLots(), closePrice, 10); // Slippage 10
            
            if(result)
            {
                closed++;
                LogPrint(LOG_ESSENTIAL, "SUCCESS", "Ordem fechada: " + IntegerToString(OrderTicket()));
            }
            else
            {
                failed++;
                int error = GetLastError();
                LogPrint(LOG_CRITICAL, "ERROR", "Falha ao fechar ordem: " + IntegerToString(OrderTicket()) + " | Erro: " + IntegerToString(error));
            }
        }
    }
    
    LogRemoteCloseResult(closed, failed, totalOrders);
    
    // ✅ CORREÇÃO 5: Atualizar status do comando
    if(commandId != "")
    {
        lastProcessedCommandId = commandId; // Marcar como processado
        
        if(failed == 0)
        {
            UpdateCommandStatus(commandId, "EXECUTED", "Todas as " + IntegerToString(closed) + " posições foram fechadas com sucesso");
        }
        else if(closed > 0)
        {
            UpdateCommandStatus(commandId, "PARTIAL", IntegerToString(closed) + " posições fechadas, " + IntegerToString(failed) + " falharam");
        }
        else
        {
            UpdateCommandStatus(commandId, "FAILED", "Nenhuma posição foi fechada. Total de falhas: " + IntegerToString(failed));
        }
    }
    else
    {
        LogPrint(LOG_CRITICAL, "ERROR", "ID do comando não encontrado - status não será atualizado");
    }
}

//+------------------------------------------------------------------+
// Expert initialization function - MQL4 v2.21.1                          
//+------------------------------------------------------------------+
int OnInit()
{
    LogSeparator("EA CONNECTOR V." + EA_VERSION + " INICIALIZANDO..."); 
    LogPrint(LOG_ERRORS_ONLY, "SYSTEM", "🔧 EA CONNECTOR V." + EA_VERSION + " INICIALIZANDO - COMANDOS REMOTOS CORRIGIDOS...");
    
    LogPrint(LOG_ALL, "CONFIG", "URL do servidor: " + ServerURL);
    LogPrint(LOG_ALL, "CONFIG", "Email do usuário: " + UserEmail);
    LogPrint(LOG_ALL, "CONFIG", "Intervalo com ordens: " + IntegerToString(SendIntervalYesOrders) + "s | Sem ordens: " + IntegerToString(SendIntervalNoOrders) + "s");
    LogPrint(LOG_ALL, "CONFIG", "Modo selecionado: " + (UseTimer ? "TIMER (sem ticks)" : "TICK (com ticks)"));
    LogPrint(LOG_ALL, "CONFIG", "Polling de comandos: " + (EnableCommandPolling ? "HABILITADO" : "DESABILITADO"));
    LogPrint(LOG_ALL, "CONFIG", "Intervalo ativo: " + IntegerToString(CommandCheckIntervalSeconds) + "s | Intervalo idle: " + IntegerToString(IdleCommandCheckIntervalSeconds) + "s");
    LogPrint(LOG_ALL, "CONFIG", "Nível de log: " + EnumToString(LoggingLevel));

    // INICIALIZAR VPS ID - VERSÃO v2.21.1 EXPANDIDA
    if(EnableVpsIdentification)
    {
        LogSubSeparator("IDENTIFICAÇÃO VPS v2.21.1");
        g_VpsId = GetVpsUniqueId(); 
        g_VpsHostname = VPS_GetHostname();  
        g_VpsPublicIP = VPS_GetPublicIP();  
        
        LogPrint(LOG_CRITICAL, "VPS", "VPS ID: " + g_VpsId);
        LogPrint(LOG_CRITICAL, "VPS", "Hostname: " + g_VpsHostname);
        LogPrint(LOG_CRITICAL, "VPS", "IP Público: " + g_VpsPublicIP);
    }

    if(UseTimer)
    {
        SendIntervalSeconds = SendIntervalYesOrders;
        EventSetTimer(SendIntervalSeconds);
        LogPrint(LOG_ERRORS_ONLY, "TIMER", "📌 Timer v" + EA_VERSION + " configurado com intervalos dinâmicos");
        LogPrint(LOG_ALL, "TIMER", "EA funcionará mesmo com mercado FECHADO");
    }
    else
    {
        LogPrint(LOG_ALL, "TIMER", "EA funcionará apenas com mercado ABERTO (ticks)");
    }

    // 🔧 INICIALIZAR ESTADO DAS ORDENS
    lastHadOrders = HasOpenOrdersOrPendingOrders();
    lastOrderCount = OrdersTotal();
    enviadoZeroOrdens = !lastHadOrders;

    // 💰 LOG DE INICIALIZAÇÃO v2.21.1
    LogPrint(LOG_ESSENTIAL, "INIT", "🔧 Recursos v" + EA_VERSION + " - COMANDOS REMOTOS CORRIGIDOS:");
    LogPrint(LOG_ESSENTIAL, "INIT", "  ✅ URL corrigida para accountNumber");
    LogPrint(LOG_ESSENTIAL, "INIT", "  ✅ Parsing JSON robusto implementado");
    LogPrint(LOG_ESSENTIAL, "INIT", "  ✅ Extração de ID de comando");
    LogPrint(LOG_ESSENTIAL, "INIT", "  ✅ Controle de execução única");
    LogPrint(LOG_ESSENTIAL, "INIT", "  ✅ Atualização de status de comando");
    LogPrint(LOG_ESSENTIAL, "INIT", "  ✅ Correção dos 3 warnings MQL4");

    // Primeira execução para estabelecer conexão
    LogPrint(LOG_ALL, "INIT", "Enviando dados iniciais...");
    SendTradingDataIntelligent();
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
// Expert deinitialization function                                 
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    LogSeparator("EA FINALIZAÇÃO");
    if(UseTimer)
    {
        EventKillTimer();
        LogPrint(LOG_ESSENTIAL, "TIMER", "Timer finalizado");
    }
    LogPrint(LOG_ESSENTIAL, "DEINIT", "🔧 EA CONNECTOR V." + EA_VERSION + " FINALIZADO");
}

//+------------------------------------------------------------------+
// 🔧 ONTICK CORRIGIDO: Detecção imediata de mudanças v2.21.1
//+------------------------------------------------------------------+
void OnTick()
{
    // 🎯 DETECÇÃO IMEDIATA: Verificar mudanças de estado das ordens
    DetectOrderClosureImmediate();

    if(UseTimer)
        return; // Se usar timer, não processar envio regular no tick

    // Verificar se é hora de enviar dados (apenas se não usar timer)
    if(TimeCurrent() - lastSendTime >= SendIntervalSeconds)
    {
        SendTradingDataIntelligent();
    }
}

//+------------------------------------------------------------------+
// Timer function v2.21.1                                                   
//+------------------------------------------------------------------+
void OnTimer()
{
    if(!UseTimer)
        return;

    // VERIFICAÇÃO IMEDIATA: Detectar nova ordem aberta
    bool hasOrders = HasOpenOrdersOrPendingOrders();
    if(!lastHadOrders && hasOrders)
    {
        LogPrint(LOG_ERRORS_ONLY, "WAKE_UP", "🚀 NOVA ORDEM DETECTADA! Enviando dados imediatamente (OnTimer)");
        SendTradingDataIntelligent();
        lastSendTime = TimeCurrent();
        return; // Sair para evitar processamento duplo
    }

    SendTradingDataIntelligent();
    
    // 🔧 POLLING DE COMANDOS INTEGRADO v2.21.1
    if(EnableCommandPolling)
    {
        int intervalToUse = hasOrders ? CommandCheckIntervalSeconds : IdleCommandCheckIntervalSeconds;
        
        if(TimeCurrent() - lastCommandCheck >= intervalToUse)
        {
            CheckForRemoteCommands(); // Função corrigida v2.21.1
            lastCommandCheck = TimeCurrent();
        }
    }
}

//+-------------------------------+
//|              EA_Connector.mq5 |
//|                 Versão 2.21.7 |
//|     CORREÇÃO DADOS DE CAIXA   |
//+-------------------------------+

#property copyright  "MrBot © 2025"
#property version    "2.21"         
#define   EA_VERSION "2.21.7" // Versao 2.21.7 - PROFITNET - Lucro líquido com swap e comissão inclusos

#include "Includes/Logger_v2.20.mqh"            
#include "Includes/HttpClient_v2.20.mqh"        
#include "Includes/CommandProcessor_v2.20.mqh"  
#include "Includes/VpsIdentifier_v2.20.mqh"  

input string ServerURL_MT2 = "https://kgrlcsimdszbrkcwjpke.supabase.co";// Adicione esta URL em configurações → WebRequest 
string ServerURL = "https://kgrlcsimdszbrkcwjpke.supabase.co/functions/v1/trading-data"; 

// NOVA VARIÁVEL PARA IDENTIFICAÇÃO DO USUÁRIO     
input string UserEmail = "usuario@exemplo.com"; // Email do usuário para vinculação da conta 

input bool UseTimer = true; // Usar Timer (true) ou Ticks (false)    

// INTERVALOS DINÂMICOS BASEADOS EM ORDENS ABERTAS 
input int SendIntervalYesOrders = 6; // Intervalo quando há ordens abertas (segundos)
input int SendIntervalNoOrders = 240; // Intervalo quando não há ordens (segundos) - 3 minutos

// Variável dinâmica que será atualizada baseada na existência de ordens
int SendIntervalSeconds = 5;

// NOVAS VARIÁVEIS PARA POLLING DE COMANDOS
input bool EnableCommandPolling = true; // Habilitar polling de comandos
input int CommandCheckIntervalSeconds = 7; // Intervalo para verificar comandos (segundos)
input int IdleCommandCheckIntervalSeconds = 400; // Intervalo quando não há ordens (segundos)

// DEFINIÇÃO DO NÍVEL DE LOGGING
input LogLevel LoggingLevel = LOG_ERRORS_ONLY; // Nível de logging

string g_VpsId = "";  // Adicionar no topo do arquivo

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





//+------------------------------------------------------------------+
// 🔧 FUNÇÃO CORRIGIDA: Mapear tipos (StringToLower corrigido)
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
// 🔧 FUNÇÃO FINAL: Mapear tipos de deal para tipos normalizados
//+------------------------------------------------------------------+
string MapDealTypeToNormalized(int dealType, double profit, string comment)
{
    // Converter comment para minúsculas
    string commentLower = "";
    for(int i = 0; i < StringLen(comment); i++)
    {
        ushort ch = StringGetCharacter(comment, i);
        if(ch >= 65 && ch <= 90) ch += 32;
        commentLower += ShortToString(ch);
    }
    
    string result = "";
    
    switch(dealType)
    {
        case DEAL_TYPE_BALANCE:
            if(profit >= 0)
            {
                if(StringFind(commentLower, "deposit") >= 0) result = "DEPOSIT";
                else if(StringFind(commentLower, "bonus") >= 0) result = "BONUS";
                else result = "DEPOSIT";
            }
            else
            {
                if(StringFind(commentLower, "withdraw") >= 0) result = "WITHDRAWAL";
                else if(StringFind(commentLower, "charge") >= 0) result = "CHARGE";
                else result = "WITHDRAWAL";
            }
            break;
        case DEAL_TYPE_CREDIT:
            result = "BONUS";
            break;
        case DEAL_TYPE_CHARGE:
            result = "CHARGE";
            break;
        case DEAL_TYPE_CORRECTION:
            result = profit >= 0 ? "BONUS" : "CHARGE";
            break;
        case DEAL_TYPE_BONUS:
            result = "BONUS";
            break;
        case DEAL_TYPE_BUY:
            result = "BUY";
            break;
        case DEAL_TYPE_SELL:
            result = "SELL";
            break;
        default:
            result = profit >= 0 ? "DEPOSIT" : "WITHDRAWAL";
    }
    
    return result;
}



//+--------------+
// 🔧 FUNÇÃO CORRIGIDA: Verificar se é evento de caixa - INCLUINDO TODOS OS TIPOS
//+--------------+
bool IsCashDeal(int dealType)
{
    return (dealType == DEAL_TYPE_BALANCE || 
            dealType == DEAL_TYPE_CREDIT || 
            dealType == DEAL_TYPE_CHARGE || 
            dealType == DEAL_TYPE_CORRECTION || 
            dealType == DEAL_TYPE_BONUS ||
            dealType == DEAL_TYPE_COMMISSION ||
            dealType == DEAL_TYPE_COMMISSION_DAILY ||
            dealType == DEAL_TYPE_COMMISSION_MONTHLY ||
            dealType == DEAL_TYPE_COMMISSION_AGENT_DAILY ||
            dealType == DEAL_TYPE_COMMISSION_AGENT_MONTHLY ||
            dealType == DEAL_TYPE_INTEREST);
}

//+--------------+
// 🔧 CORREÇÃO: Função para escape JSON robusto
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
// 🔧 FUNÇÃO ATUALIZADA: Construir item de histórico JSON com profitNet
//+--------------+
string BuildHistoryItemJson(ulong ticket)
{
    int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
    double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
    string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
    long expertId = (long)HistoryDealGetInteger(ticket, DEAL_MAGIC);
    datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
    
    // 💰 NOVO: Calcular profit líquido (profit + commission + swap)
    double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
    double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
    double profitNet = profit + commission + swap;
    
    bool isTrade = (dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL);
    bool isCash = IsCashDeal(dealType);
    
    if(!isTrade && !isCash) 
    {
        return ""; // Ignorar outros tipos
    }
    
    string json = "{";
    json += "\"ticket\":" + IntegerToString((long)ticket) + ",";
    
    if(isCash)
    {
        // 🆕 EVENTO DE CAIXA - profitNet = profit (sem swap/comissão)
        string normType = MapDealTypeToNormalized(dealType, profit, comment);
        
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
        string typeStr = (dealType == DEAL_TYPE_BUY ? "BUY" : "SELL");
        double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
        json += "\"symbol\":\"" + HistoryDealGetString(ticket, DEAL_SYMBOL) + "\",";
        json += "\"type\":\"" + typeStr + "\",";
        json += "\"volume\":" + DoubleToString(HistoryDealGetDouble(ticket, DEAL_VOLUME), 2) + ",";
        json += "\"openPrice\":" + DoubleToString(price, 5) + ",";
        json += "\"closePrice\":" + DoubleToString(price, 5) + ",";
        json += "\"profit\":" + DoubleToString(profit, 2) + ",";
        json += "\"profitNet\":" + DoubleToString(profitNet, 2) + ","; // 💰 TRADE: profit + commission + swap
        json += "\"openTime\":\"" + TimeToString(dealTime, TIME_DATE|TIME_MINUTES) + "\",";
        json += "\"closeTime\":\"" + TimeToString(dealTime, TIME_DATE|TIME_MINUTES) + "\",";
    }
    
    // Campos finais
    string escapedComment = JsonEscape(comment);
    json += "\"comment\":\"" + escapedComment + "\",";
    json += "\"expertId\":" + IntegerToString(expertId);
    json += "}";
    
    return json;
}


//+------------------------------------------------------------------+
// FUNÇÕES EXISTENTES (mantidas da v2.20.1)
//+------------------------------------------------------------------+

//+--------------+
// NOVA FUNÇÃO INTELIGENTE: Verificar se há necessidade de processar
//+--------------+
bool HasOpenOrdersOrPendingOrders()
{
    return PositionsTotal() > 0 || OrdersTotal() > 0;
}

//+--------------+
// 🔧 NOVA FUNÇÃO: Detectar fechamento imediato de ordens
//+--------------+
void DetectOrderClosureImmediate()
{
    bool hasOrders = HasOpenOrdersOrPendingOrders();
    int currentOrderCount = PositionsTotal() + OrdersTotal();
    
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
// FUNÇÃO PARA ATUALIZAR INTERVALO DINAMICAMENTE
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
        }
        
        LogPrint(LOG_ALL, "INTERVAL", hasOrders ? "Com ordens - intervalo: " + IntegerToString(SendIntervalSeconds) + "s" : "Sem ordens - intervalo: " + IntegerToString(SendIntervalSeconds) + "s");
    }
}

//+--------------+
// FUNÇÃO AUXILIAR PARA TIMEZONE
//+--------------+
string GetBrokerTimezone()
{
    // Função simples para retornar timezone
    return "UTC+0";
}

//+------------------------------------------------------------------+
// 🔧 FUNÇÃO COMPLETA: Construir JSON completo COM PROFITNET v2.21.7
//+------------------------------------------------------------------+
string BuildJsonDataWithVps()
{
    string json = "{";
    
    // Account Info
    json += "\"account\":{";
    json += "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ",";
    json += "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ",";
    json += "\"profit\":" + DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2) + ",";
    json += "\"accountNumber\":\"" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\",";
    json += "\"server\":\"" + JsonEscape(AccountInfoString(ACCOUNT_SERVER)) + "\",";
    json += "\"leverage\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)) + ",";
    json += "\"brokerTimezone\":\"" + GetBrokerTimezone() + "\",";
    json += "\"holderName\":\"" + JsonEscape(AccountInfoString(ACCOUNT_NAME)) + "\"";
    json += "},";
    
    // Margin Info
    double marginUsed = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN), 2);
    double marginFree = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2);
    double marginLevel = marginUsed == 0 ? 0 : NormalizeDouble(AccountInfoDouble(ACCOUNT_EQUITY)/marginUsed*100, 2);
    
    if(marginUsed > 999999999.99) marginUsed = 999999999.99;
    if(marginFree > 999999999.99) marginFree = 999999999.99;
    if(marginLevel > 999999.99) marginLevel = 999999.99;
    
    json += "\"margin\":{";
    json += "\"used\":" + DoubleToString(marginUsed, 2) + ",";
    json += "\"free\":" + DoubleToString(marginFree, 2) + ",";
    json += "\"level\":" + DoubleToString(marginLevel, 2);
    json += "},";

    // 💰 POSITIONS COM PROFITNET
    json += "\"positions\":[";
    int posCount = 0;
    int totalPositions = PositionsTotal();
    for(int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            // 💰 NOVO: Calcular profit líquido para posições abertas
            double profitGross = PositionGetDouble(POSITION_PROFIT);
            double commission = PositionGetDouble(POSITION_COMMISSION);
            double swap = PositionGetDouble(POSITION_SWAP);
            double profitNet = profitGross + commission + swap;
            
            if(posCount > 0) json += ",";
            json += "{";
            json += "\"ticket\":" + IntegerToString((long)ticket) + ",";
            json += "\"symbol\":\"" + JsonEscape(PositionGetString(POSITION_SYMBOL)) + "\",";
            json += "\"type\":\"" + (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL") + "\",";
            json += "\"volume\":" + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + ",";
            json += "\"openPrice\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 5) + ",";
            json += "\"currentPrice\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_CURRENT), 5) + ",";
            json += "\"profit\":" + DoubleToString(profitGross, 2) + ",";
            json += "\"profitNet\":" + DoubleToString(profitNet, 2) + ","; // 💰 NOVO CAMPO
            json += "\"openTime\":\"" + TimeToString((datetime)PositionGetInteger(POSITION_TIME), TIME_DATE|TIME_MINUTES) + "\"";
            json += "}";
            posCount++;
        }
    }
    json += "],";
    
    // 💰 HISTORY COM PROFITNET
    json += "\"history\":[";
    int histCount = 0;
    HistorySelect(0, TimeCurrent());
    int totalDeals = HistoryDealsTotal();
    
    for(int i = totalDeals-1; i >= 0 && histCount < 50; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket > 0)
        {
            int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
            bool isTrade = (dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL);
            bool isCash = IsCashDeal(dealType);
            
            if(!isTrade && !isCash) continue;
            
            if(histCount > 0) json += ",";
            
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
            datetime time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
            long expertId = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            string normalizedType = MapDealTypeToNormalized(dealType, profit, comment);
            
            // 💰 NOVO: Calcular profit líquido no histórico inline
            double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
            double profitNet = isCash ? profit : (profit + commission + swap); // Cash não tem swap/comissão
            
            json += "{";
            json += "\"ticket\":" + IntegerToString((long)ticket) + ",";
            
            if(isCash)
            {
                json += "\"symbol\":\"CASH\",";
                json += "\"type\":\"" + normalizedType + "\",";
                json += "\"volume\":0,";
                json += "\"openPrice\":0,";
                json += "\"closePrice\":0,";
            }
            else
            {
                string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
                double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
                double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
                
                json += "\"symbol\":\"" + JsonEscape(symbol) + "\",";
                json += "\"type\":\"" + normalizedType + "\",";
                json += "\"volume\":" + DoubleToString(volume, 2) + ",";
                json += "\"openPrice\":" + DoubleToString(price, 5) + ",";
                json += "\"closePrice\":" + DoubleToString(price, 5) + ",";
            }
            
            json += "\"profit\":" + DoubleToString(profit, 2) + ",";
            json += "\"profitNet\":" + DoubleToString(profitNet, 2) + ","; // 💰 NOVO CAMPO
            json += "\"openTime\":\"" + TimeToString(time, TIME_DATE|TIME_MINUTES) + "\",";
            json += "\"closeTime\":\"" + TimeToString(time, TIME_DATE|TIME_MINUTES) + "\",";
            json += "\"comment\":\"" + JsonEscape(comment) + "\",";
            json += "\"expertId\":" + IntegerToString(expertId);
            json += "}";
            histCount++;
        }
    }
    json += "],";
    
    // Resto do JSON (mantido igual)
    json += "\"userEmail\":\"" + UserEmail + "\"";
    
    string vpsId = GetVpsUniqueId();
    if(EnableVpsIdentification && vpsId != "")
        json += ",\"vpsId\":\"" + vpsId + "\"";
    
    json += ",\"connectorVersion\":\"v"+EA_VERSION + "\""; 
    
    if(EnableVpsIdentification)
    {
        string hostname = VPS_GetHostname();
        string publicIp = VPS_GetPublicIP();
        
        if(hostname != "" && hostname != "Unknown")
            json += ",\"hostname\":\"" + JsonEscape(hostname) + "\"";
        if(publicIp != "" && publicIp != "0.0.0.0")
            json += ",\"publicIp\":\"" + JsonEscape(publicIp) + "\"";
    }
    
    json += "}";
    return json;
}




//+------------------------------------------------------------------+
// 🆕 FUNÇÃO IDLE ATUALIZADA v2.21.3 - COM HISTÓRICO CASH CORRIGIDO
//+------------------------------------------------------------------+
void SendIdleStatusToSupabase()
{
    // Log apenas se não foi mostrado ainda ou se está em nível ALL
    if(!idleLogAlreadyShown || LoggingLevel >= LOG_ALL)
    {
        LogPrint(LOG_ALL, "IDLE", "📡 Enviando status idle V"+EA_VERSION + " para servidor (mantendo conexão)...");
    }

    string jsonData = "{";
    
    // 🆕 Account com holderName
    jsonData += "\"account\":{";
    jsonData += "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ",";
    jsonData += "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ",";
    jsonData += "\"profit\":0.00,";
    jsonData += "\"accountNumber\":\"" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\",";
    jsonData += "\"server\":\"" + AccountInfoString(ACCOUNT_SERVER) + "\",";
    jsonData += "\"leverage\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)) + ",";
    jsonData += "\"brokerTimezone\":\"" + GetBrokerTimezone() + "\",";
    jsonData += "\"holderName\":\"" + AccountInfoString(ACCOUNT_NAME) + "\"";
    jsonData += "},";
    
    jsonData += "\"margin\":{\"used\":0.00,\"free\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + ",\"level\":0.00},";
    jsonData += "\"positions\":[],";
    
    // 🆕 HISTÓRICO IDLE COM CASH CORRIGIDO - 30 ITENS
    jsonData += "\"history\":[";
    int histCount = 0;
    HistorySelect(0, TimeCurrent());
    
    for(int i = HistoryDealsTotal()-1; i >= 0 && histCount < 30; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket <= 0) continue;
        
        string historyItem = BuildHistoryItemJson(ticket);
        if(historyItem == "") continue; // Ignorar tipos não suportados
        
        if(histCount > 0) jsonData += ",";
        jsonData += historyItem;
        histCount++;
    }
    jsonData += "],";
    
    jsonData += "\"userEmail\":\"" + UserEmail + "\",";
    jsonData += "\"status\":\"IDLE\"";

    // ✅ ADICIONAR VPS ID SE DISPONÍVEL
    string vpsId = GetVpsUniqueId();
    if(EnableVpsIdentification && vpsId != "")
    {
        jsonData += ",\"vpsId\":\"" + vpsId + "\"";
    }

    // 🆕 VERSÃO CORRIGIDA
    jsonData += ",\"connectorVersion\":\"v" +EA_VERSION + "\"";
    
    if(EnableVpsIdentification)
    {
        string hostname = VPS_GetHostname();
        string publicIp = VPS_GetPublicIP();
        if(hostname != "" && hostname != "Unknown")
            jsonData += ",\"hostname\":\"" + hostname + "\"";
        if(publicIp != "" && publicIp != "0.0.0.0")
            jsonData += ",\"publicIp\":\"" + publicIp + "\"";
    }

    jsonData += "}";

    SendToSupabase(jsonData);
}

//+------------------------------------------------------------------+
// FUNÇÕES RESTANTES (mantidas da v2.20.1)
//+------------------------------------------------------------------+

//+--------------+
void SendToSupabase(string jsonData)
{
    bool isIdle = (StringFind(jsonData, "\"status\":\"IDLE\"") >= 0);

    // ✅ LOGS AJUSTADOS: LogSubSeparator movido para LOG_ESSENTIAL
    if(!isIdle || LoggingLevel >= LOG_ALL)
    {
        if(!isIdle && LoggingLevel >= LOG_ESSENTIAL)  // ✅ AJUSTE: Só mostra separador em LOG_ESSENTIAL+
            LogSubSeparator("ENVIO SUPABASE v."+EA_VERSION);
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
    LogConnectionSmart(res == 200, res, "Envio para Supabase v"+EA_VERSION);

    if(res == 200)
    {
        if(!isIdle || LoggingLevel >= LOG_ALL)
        {
            LogPrint(isIdle ? LOG_ALL : LOG_ESSENTIAL, "SUCCESS", "✅ Dados v"+EA_VERSION + " enviados para Supabase com sucesso!");
        }
    }
    else
    {
        LogPrint(LOG_ERRORS_ONLY, "ERROR", "❌ Falha no envio v"+EA_VERSION + " - Código: " + IntegerToString(res));
    }
}

//+--------------+
// 🔧 FUNÇÃO CORRIGIDA: Envio de dados com polling de comandos reativado
//+--------------+
void SendTradingDataIntelligent()
{
    int currentOrderCount = PositionsTotal() + OrdersTotal();
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
                LogPrint(LOG_ESSENTIAL, "IDLE", "Conta " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " sem ordens abertas");
                LogPrint(LOG_ESSENTIAL, "IDLE", "Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + " | Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
                LogPrint(LOG_ALL, "IDLE", "Logs reduzidos ativados - dados continuam sendo enviados");
                idleLogAlreadyShown = true;
                activeLogAlreadyShown = false;
            }
            else
            {
                LogPrint(LOG_ESSENTIAL, "IDLE", "Status idle - Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + " | Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
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

        string jsonData = BuildJsonDataWithVps();
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
            CheckPendingCommands(); // Função do CommandProcessor_v2.20.mqh
            lastCommandCheck = TimeCurrent();
        }
    }
}

//+------------------------------------------------------------------+
// Expert initialization function - MQL5                          
//+------------------------------------------------------------------+
int OnInit()
{
    // ✅ CONFIGURAR NÍVEL DE LOGGING
    SetLoggingLevel(LoggingLevel);
    
    LogPrint(LOG_ERRORS_ONLY, "SYSTEM", "🔧 EA CONNECTOR V." +EA_VERSION + " INICIALIZANDO - CORREÇÃO CASH...");
    
    // Verificações básicas - MQL5
    if(!TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
    {
        LogPrint(LOG_ERRORS_ONLY, "ERROR", "❌ DLLs não permitidas! Habilite em Ferramentas → Opções → Expert Advisors");
        return INIT_FAILED;
    }
    
    if(!TerminalInfoInteger(TERMINAL_CONNECTED))
    {
        LogPrint(LOG_ERRORS_ONLY, "ERROR", "❌ Terminal não conectado!");
        return INIT_FAILED;
    }

    g_VpsId = GetVpsUniqueId();

    // ✅ INICIALIZAR VPS ID
    if(EnableVpsIdentification)
    {
        LogPrint(LOG_ESSENTIAL, "VPS", "🔍 Iniciando identificação VPS v"+EA_VERSION + "...");
        
        if(VPS_TestFunctionality())
        {
            string hostname = VPS_GetHostname();
            string ip = VPS_GetPublicIP();
            string vpsId = GetVpsUniqueId();
            
            LogPrint(LOG_ESSENTIAL, "VPS", "📌 Hostname: " + hostname);
            LogPrint(LOG_ESSENTIAL, "VPS", "📌 IP Público: " + ip);
            LogPrint(LOG_ESSENTIAL, "VPS", "📌 VPS ID: " + vpsId);
            LogPrint(LOG_ESSENTIAL, "VPS", "✅ Biblioteca VPS funcional - todos os dados capturados");
        }
        else
        {
            LogPrint(LOG_ERRORS_ONLY, "ERROR", "❌ Problema na biblioteca VPS - alguns dados podem não estar disponíveis");
        }
    }

    // Configurar timer se habilitado
    if(UseTimer)
    {
        LogPrint(LOG_ESSENTIAL, "TIMER", "📌 Timer v"+EA_VERSION + " configurado com intervalos dinâmicos");
        LogPrint(LOG_ALL, "TIMER", "Com ordens: " + IntegerToString(SendIntervalYesOrders) + "s | Sem ordens: " + IntegerToString(SendIntervalNoOrders) + "s");
        
        // Iniciar com intervalo padrão
        EventSetTimer(SendIntervalSeconds);
    }

    // 🔧 INICIALIZAR ESTADO DAS ORDENS
    lastHadOrders = HasOpenOrdersOrPendingOrders();
    lastOrderCount = PositionsTotal() + OrdersTotal();
    enviadoZeroOrdens = !lastHadOrders;

    // 🆕 LOG DE INICIALIZAÇÃO v2.21.3
    LogPrint(LOG_ESSENTIAL, "INIT", "🔧 Recursos v"+EA_VERSION + " - CORREÇÃO CASH:");
    LogPrint(LOG_ESSENTIAL, "INIT", "  ✅ Histórico expandido para 50 itens");
    LogPrint(LOG_ESSENTIAL, "INIT", "  ✅ Detecção corrigida de eventos de caixa");
    LogPrint(LOG_ESSENTIAL, "INIT", "  ✅ Logs de debug para CASH adicionados");
    LogPrint(LOG_ESSENTIAL, "INIT", "  ✅ Função IsCashDeal() corrigida");

    // Primeira execução para estabelecer conexão
    SendTradingDataIntelligent();

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
// Expert deinitialization function                                 
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(UseTimer)
        EventKillTimer();
        
    LogPrint(LOG_ERRORS_ONLY, "SYSTEM", "🔧 EA CONNECTOR V." +EA_VERSION + " FINALIZADO");
}

//+------------------------------------------------------------------+
// 🔧 ONTICK CORRIGIDO: Detecção imediata de mudanças v2.21.3
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
// Timer function v2.21.3                                                   
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

    // LOG INTELIGENTE DO TIMER
    string timerMessage = "Timer executado - " + TimeToString(TimeCurrent());
    LogTimerSmart(timerMessage);
    
    SendTradingDataIntelligent();
    lastSendTime = TimeCurrent();
    
    // 🔧 POLLING DE COMANDOS INTEGRADO
    if(EnableCommandPolling)
    {
        int intervalToUse = hasOrders ? CommandCheckIntervalSeconds : IdleCommandCheckIntervalSeconds;
        
        if(TimeCurrent() - lastCommandCheck >= intervalToUse)
        {
            string commandMessage = "Verificando comandos - Modo: " + (hasOrders ? "ATIVO" : "IDLE") + " | Intervalo: " + IntegerToString(intervalToUse) + "s";
            LogCommandSmart(commandMessage, false);
            
            CheckPendingCommands();
            lastCommandCheck = TimeCurrent();
        }
        else
        {
            if(g_LoggingLevel >= LOG_ALL)
            {
                int remaining = intervalToUse - (int)(TimeCurrent() - lastCommandCheck);
                LogPrint(LOG_ALL, "POLLING", "Próxima verificação em: " + IntegerToString(remaining) + "s (" + (hasOrders ? "modo ativo" : "modo idle") + ")");
            }
        }
    }
    
    // Marcar primeira execução como completa após alguns ciclos
    MarkFirstRunCompleted();
}



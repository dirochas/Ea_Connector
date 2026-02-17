//+------------------------------------------------------------------+
//|                                             CommandProcessor.mqh |
//| Processador de comandos recebidos via API    v.2.20              |
//+------------------------------------------------------------------+

#include "Logger_v2.20.mqh"
#include "HttpClient_v2.20.mqh" // update to Version v2.20

//+------------------------------------------------------------------+
// Verificar comandos pendentes
//+------------------------------------------------------------------+
void CheckPendingCommands()
{
   LogPrint(LOG_ESSENTIAL, "COMMANDS", "Verificando comandos para conta: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
   
   string url = "https://kgrlcsimdszbrkcwjpke.supabase.co/functions/v1/get-commands?accountNumber=" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   LogPrint(LOG_ALL, "GET", "URL: " + url);
   
   string headers = "Content-Type: application/json\r\n";
   
   char result[];
   string resultHeaders;
   
   // CORREÇÃO: Usar array vazio para requisição GET
   char emptyPost[];
   
   LogPrint(LOG_ALL, "GET", "Fazendo requisição GET...");
   int res = WebRequest("GET", url, headers, 5000, emptyPost, result, resultHeaders);
   
   // LOG INTELIGENTE DE CONEXÃO
   LogConnectionSmart(res == 200, res, "Verificação de comandos");
   
   if(res == 200)
   {
      string response = CharArrayToString(result);
      LogPrint(LOG_ALL, "RESPONSE", "Resposta completa: " + response);
      
      // Verificar se existe o campo "commands" na resposta
      if(StringFind(response, "\"commands\"") >= 0)
      {
         LogPrint(LOG_ALL, "PARSE", "Campo 'commands' encontrado");
         
         if(StringFind(response, "\"commands\":[]") >= 0)
         {
            LogCommandSmart("Nenhum comando pendente");
         }
         else
         {
            LogPrint(LOG_CRITICAL, "COMMANDS", "Comandos encontrados! Processando...");
            
            // Verificar especificamente por CLOSE_ALL
            if(StringFind(response, "CLOSE_ALL") >= 0)
            {
               LogPrint(LOG_CRITICAL, "COMMAND", "COMANDO CLOSE_ALL ENCONTRADO!");
               ExecuteCloseAllCommand(response);
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

//+------------------------------------------------------------------+
// Executar comando CLOSE_ALL (MQL5) - VERSÃO CORRIGIDA COM LOGS
//+------------------------------------------------------------------+
void ExecuteCloseAllCommand(string jsonResponse)
{
   // Extrair ID do comando (parsing simples)
   string commandId = ExtractCommandId(jsonResponse);
   
   int totalPositions = PositionsTotal();
   
   // ✅ ADICIONADO: LOG REMOTO DETECTADO (sempre visível)
   LogRemoteCloseCommand(commandId, totalPositions);
   
   int closedCount = 0;
   int failedCount = 0;
   
   // Fechar todas as posições abertas (MQL5) - CORRIGIDO
   for(int i = totalPositions - 1; i >= 0; i--)
   {
      LogPrint(LOG_ALL, "PROCESS", "Processando posição índice: " + IntegerToString(i));
      
      ulong positionTicket = PositionGetTicket(i);
      if(positionTicket > 0)
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         double volume = PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         LogPrint(LOG_ALL, "POSITION", "Ticket: " + IntegerToString(positionTicket) + " | Tipo: " + (posType == POSITION_TYPE_BUY ? "BUY" : "SELL") + " | Symbol: " + symbol + " | Volume: " + DoubleToString(volume, 2));
         
         // Preparar requisição de fechamento
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         // Configurar requisição básica
         request.action = TRADE_ACTION_DEAL;
         request.symbol = symbol;
         request.volume = volume;
         request.position = positionTicket; // Usar ticket da posição
         request.deviation = 10; // Aumentar slippage para 10 pontos
         request.magic = 0;
         request.comment = "CLOSE_ALL_COMMAND";
         
         // CORREÇÃO CRÍTICA: Definir modo de preenchimento
         request.type_filling = ORDER_FILLING_FOK; // Fill or Kill - tenta preencher completamente ou cancela
         
         // Verificar se o símbolo suporta FOK, senão usar IOC
         int filling_mode = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
         if((filling_mode & SYMBOL_FILLING_FOK) == 0)
         {
            if((filling_mode & SYMBOL_FILLING_IOC) != 0)
            {
               request.type_filling = ORDER_FILLING_IOC; // Immediate or Cancel
               LogPrint(LOG_ALL, "FILLING", "Usando IOC para " + symbol);
            }
            else
            {
               request.type_filling = ORDER_FILLING_RETURN; // Return - modo padrão
               LogPrint(LOG_ALL, "FILLING", "Usando RETURN para " + symbol);
            }
         }
         else
         {
            LogPrint(LOG_ALL, "FILLING", "Usando FOK para " + symbol);
         }
         
         // Definir tipo de ordem e preço baseado no tipo da posição
         if(posType == POSITION_TYPE_BUY)
         {
            request.type = ORDER_TYPE_SELL;
            request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
            LogPrint(LOG_ALL, "CLOSE", "Fechando BUY com BID: " + DoubleToString(request.price, 5));
         }
         else if(posType == POSITION_TYPE_SELL)
         {
            request.type = ORDER_TYPE_BUY;
            request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
            LogPrint(LOG_ALL, "CLOSE", "Fechando SELL com ASK: " + DoubleToString(request.price, 5));
         }
         
         // Verificar se o preço é válido
         if(request.price <= 0)
         {
            LogPrint(LOG_CRITICAL, "ERROR", "Preço inválido para " + symbol + ": " + DoubleToString(request.price, 5));
            failedCount++;
            continue;
         }
         
         // Executar ordem de fechamento
         bool success = OrderSend(request, result);
         
         LogPrint(LOG_ALL, "RESULT", "OrderSend retornou: " + (success ? "true" : "false"));
         LogPrint(LOG_ALL, "RESULT", "Código de retorno: " + IntegerToString(result.retcode));
         LogPrint(LOG_ALL, "RESULT", "Comentário: " + result.comment);
         
         if(success && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED))
         {
            closedCount++;
            LogPrint(LOG_ESSENTIAL, "SUCCESS", "Posição fechada com sucesso: " + IntegerToString(positionTicket));
            LogPrint(LOG_ALL, "SUCCESS", "Deal: " + IntegerToString(result.deal) + " | Order: " + IntegerToString(result.order));
         }
         else
         {
            failedCount++;
            LogPrint(LOG_CRITICAL, "ERROR", "Falha ao fechar posição: " + IntegerToString(positionTicket));
            LogPrint(LOG_CRITICAL, "ERROR", "Código: " + IntegerToString(result.retcode) + " | " + result.comment);
            LogPrint(LOG_CRITICAL, "ERROR", "Descrição: " + ErrorDescription(result.retcode));
            
            // Log adicional para debugging
            LogPrint(LOG_ALL, "DEBUG", "Request - Action: " + IntegerToString(request.action));
            LogPrint(LOG_ALL, "DEBUG", "Request - Symbol: " + request.symbol);
            LogPrint(LOG_ALL, "DEBUG", "Request - Volume: " + DoubleToString(request.volume, 2));
            LogPrint(LOG_ALL, "DEBUG", "Request - Type: " + IntegerToString(request.type));
            LogPrint(LOG_ALL, "DEBUG", "Request - Price: " + DoubleToString(request.price, 5));
            LogPrint(LOG_ALL, "DEBUG", "Request - Position: " + IntegerToString(request.position));
            LogPrint(LOG_ALL, "DEBUG", "Request - Type_filling: " + IntegerToString(request.type_filling));
            LogPrint(LOG_ALL, "DEBUG", "Request - Deviation: " + IntegerToString(request.deviation));
         }
         
         // Pequena pausa entre fechamentos apenas se necessário (removido para velocidade)
         // Sleep(100); // REMOVIDO - estava causando lentidão
      }
      else
      {
         LogPrint(LOG_CRITICAL, "ERROR", "Erro ao obter ticket da posição no índice: " + IntegerToString(i));
         failedCount++;
      }
   }
   
   // ✅ ADICIONADO: LOG RESULTADO DO FECHAMENTO (sempre visível)
   LogRemoteCloseResult(closedCount, failedCount, totalPositions);
   
   // Atualizar status do comando
   if(commandId != "")
   {
      if(failedCount == 0)
      {
         UpdateCommandStatus(commandId, "EXECUTED", "Todas as " + IntegerToString(closedCount) + " posições foram fechadas com sucesso");
      }
      else if(closedCount > 0)
      {
         UpdateCommandStatus(commandId, "PARTIAL", IntegerToString(closedCount) + " posições fechadas, " + IntegerToString(failedCount) + " falharam");
      }
      else
      {
         UpdateCommandStatus(commandId, "FAILED", "Nenhuma posição foi fechada. Total de falhas: " + IntegerToString(failedCount));
      }
   }
   else
   {
      LogPrint(LOG_CRITICAL, "ERROR", "ID do comando não encontrado - status não será atualizado");
   }
}


//+------------------------------------------------------------------+
// Extrair ID do comando
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
// Atualizar status do comando
//+------------------------------------------------------------------+
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
      jsonData += ",\"errorMessage\":\"" + errorMessage + "\"";
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

//+------------------------------------------------------------------+
// Descrição de erros (MQL5)
//+------------------------------------------------------------------+
string ErrorDescription(int error_code)
{
   switch(error_code)
   {
      case 10004: return "Requote";
      case 10006: return "Requisição rejeitada";
      case 10007: return "Requisição cancelada pelo trader";
      case 10008: return "Ordem colocada";
      case 10009: return "Requisição concluída";
      case 10010: return "Apenas parte da requisição foi executada";
      case 10011: return "Erro de processamento de requisição";
      case 10012: return "Requisição cancelada por timeout";
      case 10013: return "Requisição inválida";
      case 10014: return "Volume inválido na requisição";
      case 10015: return "Preço inválido na requisição";
      case 10016: return "Stops inválidos na requisição";
      case 10017: return "Negociação desabilitada";
      case 10018: return "Mercado fechado";
      case 10019: return "Não há dinheiro suficiente para completar a requisição";
      case 10020: return "Preços mudaram";
      case 10021: return "Não há cotações para processar a requisição";
      case 10022: return "Data de expiração inválida na requisição";
      case 10023: return "Estado da ordem mudou";
      case 10024: return "Muitas requisições";
      case 10025: return "Sem mudanças na requisição de negociação";
      case 10026: return "Autotrading desabilitado pelo servidor";
      case 10027: return "Autotrading desabilitado pelo cliente";
      case 10028: return "Requisição bloqueada para processamento";
      case 10029: return "Ordem ou posição congelada";
      case 10030: return "Tipo de preenchimento de ordem especificado inválido";
      default:   return "Erro desconhecido #" + IntegerToString(error_code);
   }
}


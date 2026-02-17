//+------------------------------------------------------------------+
//|                                      VpsIdentifier_MQL4_v2.20.mqh |
//| Identificação VPS ÚNICA via hostname + IP - MQL4 v2.20           |
//| VERSÃO FINAL - Integrada ao sistema de logs do EA               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Imports das DLLs necessárias                                    |
//+------------------------------------------------------------------+
#import "kernel32.dll"
int GetComputerNameW(short&lpBuffer[],uint&lpnSize);
#import

#import "wininet.dll"
int  InternetOpenW(string sAgent,int lAccessType,string sProxyName="",string sProxyBypass="",int lFlags=0);
int  InternetOpenUrlW(int hInternetSession,string sUrl, string sHeaders="",int lHeadersLength=0,uint lFlags=0,int lContext=0);
int  InternetReadFile(int hFile,uchar & sBuffer[],int lNumBytesToRead,int& lNumberOfBytesRead);
int  InternetCloseHandle(int hInet);
#import

//+------------------------------------------------------------------+
//| Constantes e variáveis globais                                  |
//+------------------------------------------------------------------+
#define VPS_REGISTRY_FILE "vps_registry_v2.json"
#define VPS_ID_PREFIX "VPS_"
#define VPS_AGENT "Mozilla/5.0"

// Variáveis globais para cache
short     VPS_BF[250];
uint      VPS_SZ = 250;
string    VPS_cached_hostname = "";
string    VPS_cached_ip = "";
string    VPS_cached_id = "";

//+------------------------------------------------------------------+
//| DECLARAÇÃO DA FUNÇÃO - Será implementada pelo EA principal      |
//+------------------------------------------------------------------+
// Esta função será implementada no EA principal para integrar aos logs
void VPS_LogPrint(int level, string category, string message);

//+------------------------------------------------------------------+
//| Função para converter array para hex                           |
//+------------------------------------------------------------------+
string VPS_ArrayToHex(uchar &arr[])
{
 string res = "";
 for(int i = 0; i < ArraySize(arr); i++)
    res += StringFormat("%.2X", arr[i]);
 return res;
}

//+------------------------------------------------------------------+
//| Função para fazer requisição HTTP                              |
//+------------------------------------------------------------------+
string VPS_HttpRequest(string url)
{
 int response = InternetOpenUrlW(
    InternetOpenW(VPS_AGENT, 0, "", "", 0),
    url, "", 0, 0x84000100, 0
 );
 
 uchar ch[100];
 string data = "";
 int bytes = -1;
 
 while(InternetReadFile(response, ch, 100, bytes) && bytes > 0)
    data += CharArrayToString(ch, 0, bytes);
 
 InternetCloseHandle(response);
 return data;
}

//+------------------------------------------------+
//| Função para obter hostname do Windows          |
//+------------------------------------------------+
string VPS_GetHostname()
{
 if(VPS_cached_hostname != "")
    return VPS_cached_hostname;
    
 int pc = GetComputerNameW(VPS_BF, VPS_SZ);
 if(pc == 0)
    return "UNKNOWN_HOST";
    
 VPS_cached_hostname = ShortArrayToString(VPS_BF);
 return VPS_cached_hostname;
}

//+---------------------------------------------------+
//| Função para obter IP público com redundância      |
//+---------------------------------------------------+
string VPS_GetPublicIP()
{
 if(VPS_cached_ip != "")
    return VPS_cached_ip;
    
 // Múltiplas fontes para garantir que sempre obtenha o IP
 string services[] = {
    "http://checkip.amazonaws.com/",
    "http://ipv4.icanhazip.com/",
    "http://ipinfo.io/ip",
    "http://api.ipify.org/"
 };
 
 for(int i = 0; i < ArraySize(services); i++)
 {
    string ip = VPS_HttpRequest(services[i]);
    
    // Limpar IP
    StringReplace(ip, "\n", "");
    StringReplace(ip, "\r", "");
    StringTrimLeft(ip);
    StringTrimRight(ip);
    
    // Validação básica de IP (formato xxx.xxx.xxx.xxx)
    if(StringLen(ip) >= 7 && StringLen(ip) <= 15 && StringFind(ip, ".") > 0)
    {
       VPS_cached_ip = ip;
       return ip;
    }
 }
 
 return "UNKNOWN_IP";
}

//+----------------------------------------------------------------+
//| Gerar ID único do VPS baseado em hostname + IP                 |
//+----------------------------------------------------------------+
string GenerateVpsId()
{
 string hostname = VPS_GetHostname();
 string ip = VPS_GetPublicIP();
 
 // Combinar hostname + IP para gerar ID único
 string combined_data = hostname + "|" + ip;
 
 // Gerar hash MD5 único
 uchar src[], dst[], key[];
 StringToCharArray(combined_data, src);
 StringToCharArray(hostname, key);
 CryptEncode(CRYPT_HASH_MD5, src, key, dst);
 
 string unique_hash = VPS_ArrayToHex(dst);
 
 // Retornar com prefixo
 return VPS_ID_PREFIX + unique_hash;
}

//+-----------------------------------------+
//| Ler VPS ID do arquivo                   |
//+-----------------------------------------+
string ReadVpsId()
{
 int fileHandle = FileOpen(VPS_REGISTRY_FILE, FILE_READ|FILE_TXT|FILE_COMMON);
 if(fileHandle != INVALID_HANDLE)
 {
    string content = "";
    while(!FileIsEnding(fileHandle))
    {
       content += FileReadString(fileHandle) + "\n";
    }
    FileClose(fileHandle);
    
    int start = StringFind(content, "\"vps_id\": \"") + 11;
    int end = StringFind(content, "\"", start);
    if(start > 10 && end > start)
    {
       return StringSubstr(content, start, end - start);
    }
 }
 return "";
}

//+----------------------------------------------------------+
//| Escrever VPS ID no arquivo com informações completas     |
//+----------------------------------------------------------+
void WriteVpsId(string vpsId)
{
 string hostname = VPS_GetHostname();
 string ip = VPS_GetPublicIP();
 
 string jsonContent = "{\n";
 jsonContent += "  \"vps_id\": \"" + vpsId + "\",\n";
 jsonContent += "  \"hostname\": \"" + hostname + "\",\n";
 jsonContent += "  \"public_ip\": \"" + ip + "\",\n";
 jsonContent += "  \"last_update\": \"" + TimeToStr(TimeCurrent()) + "\",\n";
 jsonContent += "  \"account\": " + IntegerToString(AccountNumber()) + ",\n";
 jsonContent += "  \"server\": \"" + AccountServer() + "\",\n";
 jsonContent += "  \"terminal_type\": \"MT4\",\n";
 jsonContent += "  \"ea_version\": \"" + EA_VERSION + "\"\n"; // USANDO EA_VERSION
 jsonContent += "}";
 
 int fileHandle = FileOpen(VPS_REGISTRY_FILE, FILE_WRITE|FILE_TXT|FILE_COMMON);
 if(fileHandle != INVALID_HANDLE)
 {
    FileWrite(fileHandle, jsonContent);
    FileClose(fileHandle);
 }
}

//+--------------------------------------------------+
//| Verificar se há múltiplas contas no VPS          |
//+--------------------------------------------------+
bool CheckMultipleAccounts()
{
 int fileHandle = FileOpen(VPS_REGISTRY_FILE, FILE_READ|FILE_TXT|FILE_COMMON);
 if(fileHandle != INVALID_HANDLE)
 {
    string content = "";
    while(!FileIsEnding(fileHandle))
    {
       content += FileReadString(fileHandle) + "\n";
    }
    FileClose(fileHandle);
    
    // Contar quantas vezes aparece "account" no arquivo
    int accountCount = 0;
    int pos = 0;
    while((pos = StringFind(content, "\"account\":", pos)) >= 0)
    {
       accountCount++;
       pos += 10;
    }
    
    return (accountCount > 1);
 }
 return false;
}

//+-------------------------------------------------------------+
//| Validar se VPS ID ainda é válido (hostname/IP não mudaram)  |
//+-------------------------------------------------------------+
bool ValidateVpsId(string existingId)
{
 // Gerar novo ID baseado no estado atual
 string currentId = GenerateVpsId();
 
 // Se IDs são diferentes, significa que hostname ou IP mudaram
 return (existingId == currentId);
}

//+--------------------------------------------+
//| Obter informações detalhadas do VPS        |
//+--------------------------------------------+
string GetVpsInfo()
{
 string hostname = VPS_GetHostname();
 string ip = VPS_GetPublicIP();
 string vpsId = VPS_cached_id != "" ? VPS_cached_id : GenerateVpsId();
 
 string info = "";
 info += "Hostname=" + hostname + ";";
 info += "IP=" + ip + ";";
 info += "VPS_ID=" + vpsId + ";";
 info += "Account=" + IntegerToString(AccountNumber()) + ";";
 info += "EA_Version=" + EA_VERSION; // USANDO EA_VERSION
 
 return info;
}

//+----------------------------------------------------------+
//| Obter ID único do VPS (função principal - CORRIGIDA)     |
//+----------------------------------------------------------+
string GetVpsUniqueId()
{
 // Verificar se já temos ID em cache
 if(VPS_cached_id != "")
    return VPS_cached_id;
    
 string vpsId = ReadVpsId();
 bool isNewId = false;
 
 if(vpsId == "")
 {
    // Primeiro uso - gerar novo ID
    vpsId = GenerateVpsId();
    isNewId = true;
    VPS_LogPrint(4, "VPS_v2", "Novo VPS ID gerado: " + vpsId); // LOG_ALL
 }
 else
 {
    // Validar se ID existente ainda é válido
    if(!ValidateVpsId(vpsId))
    {
       string oldId = vpsId;
       vpsId = GenerateVpsId();
       isNewId = true;
       VPS_LogPrint(3, "VPS_v2", "VPS mudou! ID atualizado:");     // LOG_CRITICAL
       VPS_LogPrint(3, "VPS_v2", "Antigo: " + oldId);             // LOG_CRITICAL
       VPS_LogPrint(3, "VPS_v2", "Novo: " + vpsId);               // LOG_CRITICAL
    }
    else
    {
       VPS_LogPrint(4, "VPS_v2", "VPS ID validado: " + vpsId);    // LOG_ALL
    }
 }
 
 // Salvar/atualizar arquivo
 WriteVpsId(vpsId);
 
 // Exibir informações detalhadas - APENAS EM LOG_ALL
 string hostname = VPS_GetHostname();
 string ip = VPS_GetPublicIP();
 
 VPS_LogPrint(4, "VPS_v2", "Hostname: " + hostname);              // LOG_ALL
 VPS_LogPrint(4, "VPS_v2", "IP Público: " + ip);                 // LOG_ALL
 VPS_LogPrint(4, "VPS_v2", "EA Version: " + EA_VERSION);         // LOG_ALL - USANDO EA_VERSION
 
 // Verificar múltiplas contas - SEMPRE CRÍTICO (aparece mesmo em ERRORS_ONLY)
 if(CheckMultipleAccounts())
 {
    VPS_LogPrint(1, "VPS_MULTI", "🔥 MÚLTIPLAS CONTAS DETECTADAS NESTE VPS!"); // LOG_ERRORS_ONLY
    VPS_LogPrint(1, "VPS_MULTI", "VPS ID: " + vpsId);                          // LOG_ERRORS_ONLY
 }
 
 // Cache para próximas chamadas
 VPS_cached_id = vpsId;
 
 return vpsId;
}

//+------------------------------------------------------------+
//| Função para forçar regeneração do ID (útil para testes)    |
//+------------------------------------------------------------+
string ForceRegenerateVpsId()
{
 // Limpar cache
 VPS_cached_hostname = "";
 VPS_cached_ip = "";
 VPS_cached_id = "";
 
 // Deletar arquivo existente
 FileDelete(VPS_REGISTRY_FILE, FILE_COMMON);
 
 // Gerar novo ID
 return GetVpsUniqueId();
}

//+--------------------------------------------------------------+
//| Função para comparar se dois VPS IDs são do mesmo servidor   |
//+--------------------------------------------------------------+
bool IsSameVps(string vpsId1, string vpsId2)
{
 return (vpsId1 == vpsId2);
}
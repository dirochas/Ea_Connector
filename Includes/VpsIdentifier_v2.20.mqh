//+------------------------------------------------------------------+
//|                                    VpsIdentifier_MQL5_v2.20.mqh |
//|                                      VERSÃO FUNCIONAL CORRIGIDA |
//|                          Baseada no código comprovadamente      |
//|                          funcional - ERROS CORRIGIDOS v1        |
//+------------------------------------------------------------------+
#property copyright "VPS Identifier v2.20 MQL5 - Funcional v1"
#property version   "2.20"

//+--------------------------------------------------------------+
//| Imports das DLLs necessárias - VERSÃO MQL5 FUNCIONAL        |
//+--------------------------------------------------------------+
#import "kernel32.dll"
int GetComputerNameW(ushort &lpBuffer[], uint &lpnSize);
#import

#import "wininet.dll"
int InternetOpenW(string sAgent, int lAccessType, string sProxyName, string sProxyBypass, int lFlags);
int InternetOpenUrlW(int hInternetSession, string sUrl, string sHeaders, int lHeadersLength, uint lFlags, int lContext);
int InternetReadFile(int hFile, uchar &sBuffer[], int lNumBytesToRead, int &lNumberOfBytesRead);
int InternetCloseHandle(int hInet);
#import

//+-------------------------------------------------------------+
//| Variáveis globais - PREFIXADAS PARA EVITAR CONFLITOS       |
//+-------------------------------------------------------------+
ushort    VPS_BF[250];  // MQL5 usa ushort ao invés de short
uint      VPS_SZ = 250;
int       VPS_pc;

// VARIÁVEIS GLOBAIS PARA VPS - v2.20 EXPANDIDO (CACHE) - PREFIXADAS
string VPS_cached_id = "";
string VPS_cached_hostname = "";  // NOVO v2.20
string VPS_cached_publicip = "";  // NOVO v2.20

//+-------------------------------------------------------------+
//| Constantes                                                  |
//+-------------------------------------------------------------+
#define   VPS_AGENT                       "Mozilla/5.0"

//+-------------------------------------------------------------+
//| Função para converter array para hex                        |
//+-------------------------------------------------------------+
string VPS_ArrayToHex(uchar &arr[])
{
 string res = "";
 for(int i = 0; i < ArraySize(arr); i++)
    res += StringFormat("%.2X", arr[i]);
 return res;
}

//+------------------------------------------------------------------+
//| Função para fazer requisição HTTP - BASEADA NO CÓDIGO FUNCIONAL |
//+------------------------------------------------------------------+
string VPS_HttpRequest(string url)
{
 int session = InternetOpenW(VPS_AGENT, 0, "", "", 0);
 if(session == 0) return "";
 
 int response = InternetOpenUrlW(session, url, "", 0, 0x84000100, 0);
 if(response == 0) 
 {
    InternetCloseHandle(session);
    return "";
 }
 
 uchar ch[100];
 string data = "";
 int bytes = 0;
 
 while(InternetReadFile(response, ch, 100, bytes) && bytes > 0)
 {
    data += CharArrayToString(ch, 0, bytes);
 }
 
 InternetCloseHandle(response);
 InternetCloseHandle(session);
 return data;
}

//+------------------------------------------------------------------+
//| Função para obter hostname do Windows (MQL5) - FUNCIONAL       |
//+------------------------------------------------------------------+
string VPS_GetHostname()
{
 if(VPS_cached_hostname != "")
    return VPS_cached_hostname;
    
 VPS_pc = GetComputerNameW(VPS_BF, VPS_SZ);
 if(VPS_pc > 0)
 {
    // Converter ushort array para string - MQL5
    string hostname = "";
    for(int i = 0; i < ArraySize(VPS_BF) && VPS_BF[i] != 0; i++)
    {
       hostname += CharToString((uchar)VPS_BF[i]);
    }
    VPS_cached_hostname = hostname;
 }
 else
 {
    VPS_cached_hostname = "UNKNOWN_HOST";
 }
 
 return VPS_cached_hostname;
}

//+------------------------------------------------------------------+
//| Função para obter IP público - BASEADA NO CÓDIGO FUNCIONAL     |
//+------------------------------------------------------------------+
string VPS_GetPublicIP()
{
 if(VPS_cached_publicip != "")
    return VPS_cached_publicip;
    
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
    
    // Limpar IP - MQL5 tem StringTrimLeft e StringTrimRight
    StringReplace(ip, "\n", "");
    StringReplace(ip, "\r", "");
    StringTrimLeft(ip);
    StringTrimRight(ip);
    
    // Validação básica de IP (formato xxx.xxx.xxx.xxx)
    if(StringLen(ip) >= 7 && StringLen(ip) <= 15 && StringFind(ip, ".") > 0)
    {
       VPS_cached_publicip = ip;
       return ip;
    }
 }
 
 VPS_cached_publicip = "0.0.0.0";
 return VPS_cached_publicip;
}

//+------------------------------------------------------------------+
//| Função para gerar VPS ID único - BASEADA NO CÓDIGO FUNCIONAL   |
//+------------------------------------------------------------------+
string GetVpsUniqueId()
{
 if(VPS_cached_id != "")
    return VPS_cached_id;
    
 string hostname = VPS_GetHostname();
 string ip = VPS_GetPublicIP();
 
 // Concatenar hostname + IP para gerar CID único
 string combined_data = hostname + "|" + ip;
 
 // Gerar hash MD5 - MQL5 usa CryptEncode diferente
 uchar src[], dst[], key[];
 StringToCharArray(combined_data, src, 0, WHOLE_ARRAY, CP_UTF8);
 StringToCharArray(hostname, key, 0, WHOLE_ARRAY, CP_UTF8);
 
 // Em MQL5, CryptEncode tem sintaxe ligeiramente diferente
 if(CryptEncode(CRYPT_HASH_MD5, src, key, dst))
 {
    VPS_cached_id = "VPS_" + VPS_ArrayToHex(dst);
    return VPS_cached_id;
 }
 
 VPS_cached_id = "VPS_ERRO_CID";
 return VPS_cached_id;
}

//+------------------------------------------------------------------+
//| Função adicional para obter informações completas - MQL5      |
//+------------------------------------------------------------------+
string GetVpsInfo()
{
 string hostname = VPS_GetHostname();
 string ip = VPS_GetPublicIP();
 string cid = GetVpsUniqueId();
 
 string info = "";
 info += "Hostname=" + hostname + ";";
 info += "IP=" + ip + ";";
 info += "CID=" + cid + ";";
 info += "Platform=MT5;";
 info += "Version=2.20";
 
 return info;
}

//+------------------------------------------------------------------+
//| Função para resetar cache (útil para testes)                  |
//+------------------------------------------------------------------+
void VPS_ResetCache()
{
 VPS_cached_id = "";
 VPS_cached_hostname = "";
 VPS_cached_publicip = "";
}

//+------------------------------------------------------------------+
//| Função de teste para validar funcionamento                     |
//+------------------------------------------------------------------+
bool VPS_TestFunctionality()
{
 string hostname = VPS_GetHostname();
 string ip = VPS_GetPublicIP();
 string vpsId = GetVpsUniqueId();
 
 // Validações básicas
 if(hostname == "" || hostname == "UNKNOWN_HOST")
    return false;
    
 if(ip == "" || ip == "0.0.0.0")
    return false;
    
 if(vpsId == "" || vpsId == "VPS_ERRO_CID")
    return false;
    
 return true;
}


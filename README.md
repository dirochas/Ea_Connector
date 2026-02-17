# EA Connector - Documentação

## Visão Geral

O **EA Connector** é um Expert Advisor (EA) para MetaTrader 5 que funciona como a ponte entre os terminais de trading e o sistema web **TraderLab**. Sua função principal é capturar em tempo real os dados de cada conta de trading — saldo, margem, posições abertas e histórico de operações — e enviá-los via HTTP POST para o backend Supabase, onde são persistidos e exibidos no **Account Monitor** do painel web.

- **Versão atual:** v2.21.7
- **Plataforma:** MetaTrader 5 (MQL5)
- **Arquivo principal:** `Connector v2.21.3.mq5`
- **Licença:** MrBot © 2025

### Funcionalidades Principais

| Funcionalidade | Descrição |
|---|---|
| **Envio inteligente** | Intervalos dinâmicos: 6s com ordens abertas, 240s sem ordens (modo IDLE) |
| **Detecção imediata** | Via `OnTick`, detecta abertura/fechamento de ordens e envia dados instantaneamente |
| **Comandos remotos** | Polling periódico para executar comandos como `CLOSE_ALL` enviados pelo painel web |
| **Identificação de VPS** | Gera ID único por máquina (hash MD5 de hostname + IP público) para rastrear servidores |
| **Normalização de caixa** | Classifica operações de balanço (depósitos, saques, bônus, correções) em tipos padronizados |
| **Profit líquido** | Calcula `profitNet` = profit + commission + swap para posições e histórico |
| **holderName** | Envia o nome do titular da conta (v2.21+) para preenchimento automático |

### Requisitos

1. **DLLs habilitadas** — Ferramentas → Opções → Expert Advisors → "Permitir importação de DLL"
2. **URL no WebRequest** — Adicionar `https://kgrlcsimdszbrkcwjpke.supabase.co` em Ferramentas → Opções → Expert Advisors → "Permitir WebRequest para as URLs listadas"
3. **Conexão com internet** — O terminal precisa estar conectado ao servidor da corretora e ter acesso HTTP externo

### Parâmetros de Entrada (Inputs)

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `ServerURL_MT2` | URL Supabase | URL base (lembrete para WebRequest) |
| `UserEmail` | `usuario@exemplo.com` | Email do usuário para vinculação da conta |
| `UseTimer` | `true` | Usar Timer (recomendado) ou Ticks para envio |
| `SendIntervalYesOrders` | `6` | Intervalo em segundos quando há ordens abertas |
| `SendIntervalNoOrders` | `240` | Intervalo em segundos sem ordens (modo IDLE) |
| `EnableCommandPolling` | `true` | Habilitar polling de comandos remotos |
| `CommandCheckIntervalSeconds` | `7` | Intervalo de polling com ordens |
| `IdleCommandCheckIntervalSeconds` | `400` | Intervalo de polling sem ordens |
| `LoggingLevel` | `LOG_ERRORS_ONLY` | Nível de logging (NONE, ERRORS_ONLY, ESSENTIAL, CRITICAL, ALL) |

---

## Arquitetura e Fluxo de Dados

```
┌─────────────────────┐
│   MetaTrader 5      │
│   (Terminal 1..N)   │
│                     │
│  EA Connector v2.21 │
│  ┌───────────────┐  │
│  │ OnTick/OnTimer│──┼──► Detecção imediata de mudanças
│  │               │  │
│  │ BuildJson()   │──┼──► Monta JSON com account, margin,
│  │               │  │    positions, history, vpsId, email
│  │ SendToSupabase│──┼──► HTTP POST ─────────────────────────┐
│  │               │  │                                       │
│  │ CheckCommands │──┼──► HTTP GET (polling) ─┐              │
│  └───────────────┘  │                        │              │
└─────────────────────┘                        │              │
                                               ▼              ▼
                              ┌─────────────────────────────────────┐
                              │        Supabase Edge Functions       │
                              │                                     │
                              │  trading-data (POST)                │
                              │  ├─ Detecta formato (legacy/v2.20/  │
                              │  │  v2.21-beta)                     │
                              │  ├─ Upsert conta (accounts)         │
                              │  ├─ Upsert margem (margin)          │
                              │  ├─ Delta update posições (positions)│
                              │  ├─ Upsert histórico (history)      │
                              │  └─ Auto-registro VPS (vps_servers)  │
                              │                                     │
                              │  get-commands (GET)                  │
                              │  └─ Retorna comandos pendentes      │
                              │                                     │
                              │  update-command-status (POST)        │
                              │  └─ Atualiza resultado da execução   │
                              └──────────────┬──────────────────────┘
                                             │
                                             ▼
                              ┌──────────────────────────┐
                              │     Supabase Database     │
                              │                           │
                              │  accounts    margin       │
                              │  positions   history      │
                              │  vps_servers commands     │
                              └──────────────────────────┘
                                             │
                                             ▼
                              ┌──────────────────────────┐
                              │   TraderLab Web App       │
                              │   (Account Monitor)       │
                              └──────────────────────────┘
```

### Modos de Operação

- **Timer (recomendado):** `OnTimer` dispara a cada N segundos. `OnTick` é usado apenas para detecção imediata de mudanças (abertura/fechamento de ordens).
- **Ticks:** `OnTick` faz tudo — detecção + envio periódico baseado em `SendIntervalSeconds`.

### Ciclo de Envio

1. `OnTimer`/`OnTick` dispara
2. `DetectOrderClosureImmediate()` verifica mudanças de estado (nova ordem, ordem fechada, mudança de quantidade)
3. Se mudança detectada → envio imediato via `SendTradingDataIntelligent()`
4. Se sem mudança → envio regular no intervalo configurado
5. `SendTradingDataIntelligent()` decide entre `BuildJsonDataWithVps()` (ativo) ou `SendIdleStatusToSupabase()` (idle)
6. `SendToSupabase()` faz o HTTP POST
7. Polling de comandos executado conforme intervalo

---

## Dados Técnicos — Bibliotecas

### Logger_v2.20.mqh

Sistema de logging inteligente com anti-spam integrado.

**Níveis de Log:**

| Nível | Valor | Comportamento |
|---|---|---|
| `LOG_NONE` | 0 | Sem logs |
| `LOG_ERRORS_ONLY` | 1 | Apenas erros e eventos críticos (comandos remotos, falhas) |
| `LOG_ESSENTIAL` | 2 | Erros + status de conexão + heartbeat a cada 10min |
| `LOG_CRITICAL` | 3 | Essencial + logs críticos detalhados |
| `LOG_ALL` | 4 | Debug completo — todos os envios, respostas, parsing |

**Funções Principais:**

| Função | Descrição |
|---|---|
| `LogPrint(level, category, message)` | Log condicional baseado no nível configurado |
| `LogConnectionSmart(success, code, context)` | Anti-spam: mostra primeira conexão OK, depois silencia. Heartbeat a cada 10min em `ESSENTIAL`. Erros sempre visíveis. |
| `LogTimerSmart(message)` | Timer silencioso em `ERRORS_ONLY`, heartbeat em `ESSENTIAL` |
| `LogCommandSmart(message, isImportant)` | Comandos importantes sempre visíveis, rotina silenciada |
| `LogRemoteCloseCommand(id, total)` | Sempre visível — notifica comando de fechamento remoto |
| `LogRemoteCloseResult(closed, failed, total)` | Sempre visível — resultado do fechamento |
| `MarkFirstRunCompleted()` | Ativa modo otimizado após primeira execução |

### HttpClient_v2.20.mqh

Cliente HTTP minimalista para comunicação com Supabase.

**Função única:** `SendToSupabase(jsonData, serverURL)`

- HTTP POST via `WebRequest` com timeout de 10 segundos
- Detecta modo IDLE (`"status":"IDLE"` no JSON) para reduzir logs
- Tratamento de erros:
  - `res == -1` → URL não permitida no WebRequest (instrui o usuário)
  - `res == 0` → Timeout ou sem internet
  - Outros → Erro HTTP genérico com log de resposta

> **Nota:** O arquivo principal (`Connector v2.21.7.mq5`) possui sua própria versão de `SendToSupabase()` que sobrescreve a da biblioteca, adicionando logs de versão e separadores visuais.

### VpsIdentifier_v2.20.mqh

Identificação única de VPS via fingerprint de máquina.

**Mecanismo:**
1. Obtém hostname via `kernel32.dll` → `GetComputerNameW()`
2. Obtém IP público via `wininet.dll` → HTTP request para serviços externos
3. Concatena `hostname|ip` e gera hash MD5 via `CryptEncode(CRYPT_HASH_MD5)`
4. Resultado: `VPS_` + hash hexadecimal (ex: `VPS_A1B2C3D4E5F6...`)

**Serviços de fallback para IP público (4 fontes):**
1. `checkip.amazonaws.com`
2. `ipv4.icanhazip.com`
3. `ipinfo.io/ip`
4. `api.ipify.org`

**Cache:** Todas as funções usam cache em memória (`VPS_cached_id`, `VPS_cached_hostname`, `VPS_cached_publicip`) — chamadas externas são feitas apenas uma vez por sessão do EA.

**Funções:**

| Função | Descrição |
|---|---|
| `GetVpsUniqueId()` | Retorna ID único (com cache). Formato: `VPS_<MD5_HEX>` |
| `VPS_GetHostname()` | Nome do computador Windows (com cache) |
| `VPS_GetPublicIP()` | IP público com 4 fallbacks (com cache) |
| `GetVpsInfo()` | String formatada com todas as informações |
| `VPS_TestFunctionality()` | Teste de sanidade — verifica se hostname, IP e ID são válidos |
| `VPS_ResetCache()` | Limpa cache (para testes) |

### CommandProcessor_v2.20.mqh

Processador de comandos remotos recebidos via API.

**Fluxo:**
1. `CheckPendingCommands()` → GET para `get-commands?accountNumber=<login>`
2. Parseia resposta JSON procurando por `"commands"` e tipo `CLOSE_ALL`
3. `ExecuteCloseAllCommand()` → Fecha todas as posições via `OrderSend()`
4. `UpdateCommandStatus()` → POST para `update-command-status` com resultado

**Tratamento de Fill Mode (CLOSE_ALL):**
- Tenta `ORDER_FILLING_FOK` primeiro (fill or kill)
- Se não suportado, tenta `ORDER_FILLING_IOC` (immediate or cancel)
- Fallback: `ORDER_FILLING_RETURN`

**Status de resultado:**

| Status | Condição |
|---|---|
| `EXECUTED` | Todas as posições fechadas com sucesso |
| `PARTIAL` | Algumas fecharam, outras falharam |
| `FAILED` | Nenhuma posição foi fechada |

**Funções auxiliares:**

| Função | Descrição |
|---|---|
| `ExtractCommandId(json)` | Parsing simples de `"id":"..."` no JSON |
| `UpdateCommandStatus(id, status, error)` | POST com resultado da execução |
| `ErrorDescription(code)` | Traduz códigos de erro MQL5 para texto legível (pt-BR) |

---

## Dados Técnicos — Arquivo Principal (Connector v2.21.7.mq5)

### Funções Principais

| Função | Descrição |
|---|---|
| `OnInit()` | Inicializa: configura logging, valida DLLs, identifica VPS, configura timer, faz primeiro envio |
| `OnTick()` | Detecção imediata de mudanças via `DetectOrderClosureImmediate()`. Se `UseTimer=false`, também faz envio periódico |
| `OnTimer()` | Envio regular + polling de comandos. Detecta nova ordem para envio imediato |
| `OnDeinit()` | Finaliza timer e loga encerramento |
| `BuildJsonDataWithVps()` | Monta JSON completo: account (com holderName), margin, positions (com profitNet), history (com comment, expertId, profitNet), vpsId, email, connectorVersion, hostname, publicIp |
| `SendIdleStatusToSupabase()` | Versão econômica com 30 itens de histórico, positions vazio, e flag `"status":"IDLE"` |
| `SendTradingDataIntelligent()` | Orquestra: decide idle vs ativo, atualiza intervalo dinâmico, faz polling de comandos |
| `DetectOrderClosureImmediate()` | Compara estado atual vs anterior para detectar: nova ordem, fechamento total, mudança de quantidade |
| `UpdateDynamicInterval(hasOrders)` | Alterna timer entre intervalo com/sem ordens |

### Normalização de Cash

| Função | Descrição |
|---|---|
| `IsCashDeal(dealType)` | Retorna `true` para: BALANCE, CREDIT, CHARGE, CORRECTION, BONUS, COMMISSION (todas variantes), INTEREST |
| `MapDealTypeToNormalized(dealType, profit, comment)` | Mapeia tipo MQL5 para tipo padronizado: DEPOSIT, WITHDRAWAL, BONUS, CHARGE, CORRECTION, INTEREST, BUY, SELL |
| `BuildHistoryItemJson(ticket)` | Monta JSON de um item do histórico com todos os campos normalizados |
| `JsonEscape(s)` | Escapa caracteres especiais (`\`, `"`, `\r`, `\n`, `\t`) para JSON válido |

---

## Dados Técnicos — Edge Function `trading-data`

A Edge Function `trading-data` é o endpoint backend que recebe os dados do EA Connector e persiste no banco de dados Supabase. Usa `SUPABASE_SERVICE_ROLE_KEY` para bypass de RLS.

### Detecção de Formato

A função detecta automaticamente a versão do conector:

| Formato | Critério de Detecção | Campos Extras |
|---|---|---|
| `v2.21-beta` | `account.holderName` presente | holderName, comment, expertId, profitNet |
| `v2.20` | connectorVersion + hostname + publicIp presentes (sem holderName) | connectorVersion, hostname, publicIp |
| `legacy` | Nenhum dos campos acima | Apenas dados básicos |

### Processamento de VPS

1. Se `vpsId` fornecido, verifica se já existe em `vps_servers`
2. **VPS existente:** Atualiza apenas hostname/IP se formato v2.20+ (nunca sobrescreve `display_name` editado manualmente)
3. **VPS novo:** Cria registro com `display_name` encurtado (últimos 4 chars: `VPS_A1B2...WXYZ` → `VPS_WXYZ`)

### Persistência de Dados

| Tabela | Operação | Detalhes |
|---|---|---|
| `accounts` | Upsert (`onConflict: account`) | Atualiza balance, equity, profit, leverage, timezone. Seta `name` com holderName apenas se vazio. |
| `margin` | Upsert (`onConflict: account_id`) | Delta update para evitar flickering na UI |
| `positions` | Delta update | Remove posições fechadas (tickets ausentes), upsert das abertas. Se zero posições, limpa tudo. |
| `history` | Upsert (`onConflict: account_id,ticket`) | Limitado a 50 itens mais recentes. Normalização dupla de cash (EA + backend). |

### Normalização de Cash (Backend)

O backend possui sua própria camada de normalização como fallback para conectores antigos:
- `detectCashOperation()` — Detecta por tipo, symbol ou keywords no comentário
- `normalizeCashType()` — Mapeia para tipos padronizados (DEPOSIT, WITHDRAWAL, CREDIT_IN, CREDIT_OUT, BONUS, CHARGE, CORRECTION, ADJUSTMENT)

---

## Histórico de Versões Relevantes

| Versão | Mudanças Principais |
|---|---|
| v2.20 | Adição de connectorVersion, hostname, publicIp. Bibliotecas refatoradas (Logger, VpsIdentifier, CommandProcessor, HttpClient) |
| v2.21.3 | Correção de dados de caixa (IsCashDeal, MapDealTypeToNormalized). Histórico expandido para 50 itens. holderName no account. |
| v2.21.7 | Adição de `profitNet` (profit + commission + swap) em posições e histórico. Cash profitNet = profit puro. |

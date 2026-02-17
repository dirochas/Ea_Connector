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

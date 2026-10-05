# Rastreamento de versão e upgrade idempotente

**Data:** 2026-10-05
**Status:** rascunho para revisão
**Origem:** solicitação de facilitar o deploy de novas alterações

---

## 1. Problema

Rerodar `deploy/Install.ps1` sobre uma instalação existente não funciona como
upgrade. Três motivos, todos verificados no código:

1. **Colunas novas nunca chegam.** As ~30 tabelas de `install/00-create-schema.sql` e as
   11 de `install/08-extended-schema.sql` estão protegidas por `IF OBJECT_ID(...) IS NULL`.
   A tabela existe, então o `CREATE TABLE` inteiro é ignorado — qualquer coluna adicionada
   depois no repositório nunca é aplicada.

2. **Configuração é destruída.** `install/05-configure.sql:17`, `:68` e `:117` executam
   `DELETE FROM [monitor].[Settings]`, `Thresholds` e `Languages` antes de reinserir os
   defaults. Um upgrade apaga `Email.Recipients`, `General.Language`, `MonitoringEnabled`
   e todo threshold que o operador tenha ajustado.

3. **Jobs são recriados do zero.** `install/04-create-jobs.sql:19-47` apaga os 6 jobs do
   SQL Agent e recria com agendamento padrão, descartando ajustes de horário.

Não há nenhuma versão registrada em lugar nenhum. O instalador é uma lista plana de 40
scripts sem modo, e `install/00-create-schema.sql:13-20` ignora o parâmetro `-Database`.

## 2. Objetivo

Tornar o deploy de uma nova release um caminho de primeira classe: instalar do zero,
atualizar preservando tudo o que pertence ao operador, e saber exatamente qual versão está
em cada servidor.

**Fora de escopo** (ver §9).

## 3. Estado atual aproveitado

O repositório já está mais perto da idempotência do que parece:

- As 37 `CREATE PROCEDURE` e 8 `CREATE VIEW` usam o padrão *placeholder + `ALTER`*
  (ex.: `alerts/alert_engine.sql:8-16`), que atualiza o corpo sem erro em re-run.
- As tabelas já são criadas condicionalmente.
- `install/04-create-jobs.sql` já sabe recriar jobs do zero.

O que falta é a semântica de *preservação*, não a de *criação*.

## 4. Decisões

### 4.1 Modelo: idempotência como base, migrações como válvula de escape

Dois mecanismos convivem:

- **Cadeia idempotente** (`install/00` … `install/09` mais collectors, reports, alerts) —
  roda inteira a cada upgrade. Resolve a esmagadora maioria das mudanças.
- **`migrations/`** — pasta para o que *não pode* ser idempotente: rename de coluna,
  backfill, split de tabela, mudança de tipo. Aplicada apenas quando a versão do arquivo é
  maior que a versão instalada.

Rejeitado: log de migrações estilo Flyway para tudo (exige congelar os 40 scripts atuais e
criar convenção paralela, desproporcional para um projeto de manutenção solo). Rejeitado
também: idempotência pura sem válvula de escape (a primeira mudança que precisar de backfill
vira improviso).

### 4.2 Versão: semver em arquivo único

Um arquivo `VERSION` na raiz, evoluindo junto do `CHANGELOG.md`. Nenhum script SQL escreve
versão hardcoded. Git tag `vX.Y.Z` é o endereço do código-fonte; `VERSION` diz o que esse
código instala; `SchemaVersion` diz o que está no servidor.

**Esta entrega é a `1.1.0`** — funcionalidade nova sobre a `1.0.0` de 2026-06-02, não um
correção. Isso é deliberado: o primeiro upgrade precisa deixar rastro visível. O bootstrap
registra `1.0.0` (§4.3) e o upgrade em seguida registra `1.1.0`, então `Status` mostra uma
transição real e o mecanismo se demonstra no primeiro uso. Se esta entrega saísse como
`1.0.1`, o `VERSION` do repo e o valor assumido no bootstrap seriam idênticos e o primeiro
upgrade pareceria um no-op.

### 4.2.1 Tags

Sem tag, "instalar a versão X" não é instrução possível e um bug report não consegue dizer
que código rodou. Consequências concretas:

- `git clone --branch v1.1.0` entrega exatamente aquele estado, em vez do que estiver em `main`.
- Hotfix sai como `v1.1.1` e só quem quiser pega.
- A detecção de downgrade (§4.4) depende de a versão do repo ser comparável — sem tag,
  "versão antiga" não é um conceito verificável.

A ordem `commit → CHANGELOG → tag → GitHub Release` é procedimento humano e vai para o
README, não para código.

### 4.3 Bootstrap conservador

Instalações anteriores a esta feature não têm `SchemaVersion`. O `Upgrade` registra
`1.0.0` — última entrada do CHANGELOG — imprime aviso dizendo o que assumiu, e segue.
`-AssumeVersion` sobrescreve. Não há fallback para "assumir a versão atual", que seria
otimista e errado.

### 4.4 Downgrade é erro

Se a `VERSION` do repo for **mais antiga** que a versão instalada, o `Upgrade` recusa, salvo
`-Force`. Sem isso, um `git checkout` distraído de branch antiga "atualiza" um banco novo e
o `ALTER PROCEDURE` reverte correções silenciosamente. Detectar isso depende de a versão do
repo ser um valor comparável — ou seja, depende das tags existirem.

---

## 5. Componentes

### 5.1 `VERSION` (novo, raiz)

Arquivo de texto com um único número semver. Fonte da versão alvo para o instalador.

### 5.2 Tabelas de rastreamento (novas, em `install/00-create-schema.sql`)

```sql
CREATE TABLE [monitor].[SchemaVersion] (
    Id               INT IDENTITY(1,1) PRIMARY KEY,
    Version          VARCHAR(20)   NOT NULL,
    PreviousVersion  VARCHAR(20)   NULL,
    InstallMode      VARCHAR(10)   NOT NULL,   -- 'Fresh' | 'Upgrade'
    InstalledAt      DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    InstalledBy      NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
    CommitHash       VARCHAR(40)   NULL,       -- git rev-parse --short HEAD, se disponível
    LastVerifiedAt   DATETIME2     NULL        -- última execução bem-sucedida desta versão
);

CREATE TABLE [monitor].[AppliedMigrations] (
    FileName     NVARCHAR(255) NOT NULL PRIMARY KEY,
    Version      VARCHAR(20)   NOT NULL,
    AppliedAt    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    AppliedBy    NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME()
);
```

Uma linha por versão aplicada — histórico, não uma linha só. `LastVerifiedAt` responde
"meu upgrade de fato aplicou?" mesmo quando a versão não mudou.

Helper, com o mesmo padrão *placeholder + `ALTER FUNCTION`* usado nas procs:

```sql
[monitor].[fn_GetInstalledVersion]() RETURNS VARCHAR(20)
    -- NULL se nunca instalado; senão a última versão aplicada
```

### 5.3 `install/10-record-version.sql` (novo)

Recebe a versão e o modo por variável do sqlcmd (`-v Version="1.1.0" -v Mode="Upgrade" -v
Commit="a1b2c3d"`). Idempotente: se a versão já está registrada, apenas atualiza
`LastVerifiedAt`.

### 5.4 `deploy/Install.ps1` (reescrito)

Novo parâmetro `-Mode`, default `Upgrade`:

| Modo | Comportamento |
|---|---|
| `Status` | Somente leitura. Versão instalada × versão do repo, migrations pendentes, os 6 jobs e seus agendamentos, contagem de linhas. Não escreve nada. |
| `Upgrade` | Cadeia idempotente inteira + migrations pendentes. Preserva dados, config e agendamentos. |
| `Fresh` | Exige `-Force`. Apaga os 6 jobs e o banco, instala do zero. |

Novo parâmetro `-ResetSchedules` (default `$false`), só relevante no `Upgrade`: dá ao repo
o controle dos agendamentos dos jobs novamente.

Novo parâmetro `-AssumeVersion <semver>` para o bootstrap.

Novo parâmetro `-BackupPath <dir>`: se informado, roda `BACKUP DATABASE` antes de alterar
qualquer coisa. Se não informado, imprime recomendação. Independentemente, sempre imprime
contagem de linhas das tabelas de histórico antes e depois, para o operador ver que nada
sumiu.

`Upgrade` em banco inexistente **erra** e aponta para `-Mode Fresh`. Não há fallback
silencioso — instalar do zero destruindo dados sem pedido explícito é o pior modo de falha
possível aqui.

`Install.ps1` inválido quando `-Database` não é `SQLHealthMonitor` no modo `Upgrade`
(ver §9).

### 5.5 `install/04-create-jobs.sql` — passo é do repo, agendamento é do operador

O cursor de deleção das linhas 19-47 sai do caminho de upgrade.

- **Job não existe** → cria job, step e schedule (comportamento atual).
- **Job existe** → atualiza os steps via `sp_update_jobstep`, **sem tocar no schedule**.

Isso é decidido por um erro real do mês passado: os commits `28bd0ae` e `4451c93`
corrigiram o comando do step do Alert Engine e nomes de outras procedures. O passo precisa
acompanhar o repo; o horário que o operador ajustou não.

O caminho de `Fresh` mantém a deleção — feita pelo `Uninstall.sql`, não por este script.

Nome do banco passa a vir de `:setvar DatabaseName`.

### 5.6 `install/05-configure.sql` — `MERGE` com ação diferente por tabela

O que pertence ao operador não se toca; o que pertence ao repo acompanha a release:

| Tabela | `WHEN MATCHED` | `WHEN NOT MATCHED` |
|---|---|---|
| `Settings` | *nada* | `INSERT` |
| `Thresholds` | *nada* | `INSERT` |
| `Languages` | `UPDATE` | `INSERT` |

`Settings` e `Thresholds` usam `MERGE` só para insertar o que falta: threshold novo de
métrica nova entra, threshold ajustado continua ajustado.

**Consequência aceita e precisa ser documentada:** corrigir um default errado no repo deixa
de se propagar sozinho. Se `Email.ProfileName` vier `DBA_Mail` e mudar para
`SQLHealthMonitor_Mail`, uma base existente continua `DBA_Mail`. Isso é o comportamento
correto — config é do operador — mas **mudar um default passa a exigir migration explícita
em `migrations/`**. Registrado no CHANGELOG e no README, ou vira bug report.

### 5.7 Reconciliação de colunas

Toda tabela em `install/00-create-schema.sql` e `install/08-extended-schema.sql` ganha
blocos complementares ao `CREATE TABLE`:

```sql
IF COL_LENGTH('monitor.CpuHistory', 'NovaColuna') IS NULL
    ALTER TABLE [monitor].[CpuHistory] ADD NovaColuna DECIMAL(5,2) NULL;
GO
```

T-SQL não tem `ADD COLUMN IF NOT EXISTS`; `COL_LENGTH` é o idioma disponível. Coluna
calculada usa outro caminho — `HoursSinceLastBackup` em `00-create-schema.sql:233` é
`AS DATEDIFF(...)`, e para esse caso o check é contra `sys.computed_columns`.

## 6. Ordem de execução

**`Upgrade`**

1. Ler `VERSION` do repo e o commit corrente.
2. Checar se o banco existe. Se não → erro, apontar para `-Mode Fresh`.
3. Ler `fn_GetInstalledVersion()`.
   - Ausente → bootstrap para `1.0.0` (ou `-AssumeVersion`), com aviso.
4. Comparar com a `VERSION` do repo.
   - Repo mais antiga → recusa (downgrade), salvo `-Force`.
   - Iguais → seguir mesmo assim, avisando que é re-run idempotente.
5. `BACKUP DATABASE` se `-BackupPath` foi informado; contar linhas de `CpuHistory`,
   `MemoryHistory`, `DiskHistory`, `AlertHistory`, `Incidents`, `BaselineCapture`.
6. Rodar `install/00-create-schema.sql` … `install/09-uptime-tracker.sql` e o restante da
   cadeia, cada script contra o banco correto.
7. Rodar `migrations/` cujas versões forem maiores que a instalada, registrando cada uma em
   `AppliedMigrations`.
8. Rodar `install/10-record-version.sql`.
9. Contar linhas de novo, reportar delta, imprimir versão final.

**`Fresh`**: derrubar os 6 jobs → derrubar o banco → cadeia completa → todas as migrations →
registrar versão.

## 7. Testes

Um script, `tests/Test-Install.ps1`, sem framework novo. O projeto não tem infra de teste e
tSQLt é item separado no `OPEN-SOURCE-PLAN.md`.

Cenários:

| # | Cenário | Asserção | Ambiente |
|---|---|---|---|
| 1 | Instalar fresh, depois rodar `Upgrade` imediato | 0 erros | LocalDB |
| 2 | Adicionar coluna a tabela existente, rodar `Upgrade` | coluna existe | LocalDB |
| 3 | `Settings.Email.Recipients` = sentinela, rodar `Upgrade` | valor inalterado | LocalDB |
| 4 | Alterar `@active_start_time` de um job, rodar `Upgrade` | schedule intacto, step atualizado | **instância real** |
| 5 | Remover `SchemaVersion`, rodar `Upgrade` | aviso + bootstrap `1.0.0` | LocalDB |
| 6 | `VERSION` mais antiga que a instalada | recusado sem `-Force` | LocalDB |
| 7 | Migration fictícia, rodar `Upgrade` duas vezes | roda 1×, registrada, 2ª ignorada | LocalDB |

**Limitação honesta:** LocalDB não tem SQL Agent. `install/04-create-jobs.sql` usa
`msdb.dbo.sp_add_job` e falha lá. O cenário 4 exige instância real e o script o marca como
`SKIP` quando `-ServerInstance` não for informado, com o motivo. Os demais rodam em LocalDB
sem ressalva.

`validate_installation.sql` (raiz) é estendido com as verificações de versão e de objetos
esperados, em vez de criar um validador paralelo.

## 8. Arquivos tocados

**Novos**

- `VERSION`
- `install/10-record-version.sql`
- `install/migrations/` (pasta + `README.md` explicando quando usar)
- `tests/Test-Install.ps1`

**Modificados**

- `install/00-create-schema.sql` — tabelas de rastreamento, `fn_GetInstalledVersion`,
  reconciliação de colunas, `:setvar DatabaseName`
- `install/04-create-jobs.sql` — criação condicional, atualização de steps,
  `:setvar DatabaseName`
- `install/05-configure.sql` — três `MERGE`
- `install/08-extended-schema.sql` — reconciliação de colunas das 11 tabelas
- `deploy/Install.ps1` — `-Mode`, `-Force`, `-ResetSchedules`, `-AssumeVersion`, `-BackupPath`
- `deploy/Uninstall.ps1` — respeitar `-Database`, coerente com os modos
- `validate_installation.sql` — checagens de versão
- `CHANGELOG.md` — entrada `1.1.0`
- `README.md`, `README-PTBR.md`, `docs/INSTALL.md` — modos de instalação, upgrade,
  publicação de release, e o aviso sobre mudança de default exigir migration

## 9. Fora de escopo

Registrados para não virar surpresa depois:

- **33 arquivos com `USE [SQLHealthMonitor]` hardcoded** (40 ocorrências). Só `00` e `04`
  recebem `:setvar` nesta entrega — são os que criam e apagam. Os demais ficam como dívida:
  é refactor mecânico de 33 arquivos que diluiria esta mudança. Consequência: `-Database`
  com nome diferente de `SQLHealthMonitor` não é suportado no `Upgrade`, e o `Install.ps1`
  **avisa** em vez de fingir que funciona.
- GitHub Actions / CI (item separado do `OPEN-SOURCE-PLAN.md`).
- tSQLt e suíte de testes dos collectors.
- Docker / imagem.
- Suporte a multi-instância no instalador.

## 10. Riscos

| Risco | Mitigação |
|---|---|
| `MERGE` em `Settings`/`Thresholds` impede correção de default errado | Documentado como comportamento; mudança de default exige migration em `migrations/` |
| Recipiente de presente fica "meio updated" se um script falhar no meio | `-b` já faz o `Install.ps1` reportar erro e sair com código 1; `LastVerifiedAt` não é atualizado, então `Status` mostra a versão anterior e as migrations aplicadas |
| Bug em script idempotente roda em todo install seguinte | Mitigado pela idempotência; COLUMN guard torna falha visível e repetível, não silenciosa |
| Usuário em `main` recebe código não testado em produção | `Status` mostra `VERSION` do repo + `CommitHash`; a política "instalar a partir de tag, não de `main`" vai no README |
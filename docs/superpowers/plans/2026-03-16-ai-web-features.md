# SimpleORM AI & Web Features Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 7 features that position SimpleORM as the first ORM with deep AI integration and web-ready tooling — Natural Language Query, Auto Swagger, Smart Seeder, AI Auto-Index, AI Query Optimizer, Telegram/Discord Bot skill, and Google Sheets export.

**Architecture:** Each feature is a new unit (`SimpleXxx.pas`) following the existing `TSimpleXxx.New(...)` pattern. AI features use the existing `iSimpleAIClient` interface. Horse features extend `TSimpleHorseRouter`. Skills use `iSimpleSkill`. All features are opt-in — zero impact on existing code unless explicitly enabled.

**Tech Stack:** Delphi 10.2+ Object Pascal, RTTI attributes, System.Net.HttpClient for HTTP calls, System.JSON for serialization, iSimpleAIClient for LLM access, Horse (THorse) for web endpoints.

**Compatibility:** Delphi 10.2 Tokyo+ (NO inline vars, NO managed records). All units must use fully qualified names (`System.SysUtils`, etc.).

---

## File Structure

| Feature | New Files | Modified Files |
|---------|-----------|---------------|
| Natural Language Query | `src/SimpleNLQuery.pas` | `SimpleInterface.pas`, `SimpleDAO.pas` |
| Auto Swagger/OpenAPI | `src/SimpleSwagger.pas` | `SimpleHorseRouter.pas` |
| Smart Seeder | `src/SimpleSeeder.pas` | (none) |
| AI Auto-Index | `src/SimpleAutoIndex.pas` | (none) |
| AI Query Optimizer | `src/SimpleQueryOptimizer.pas` | (none) |
| Telegram/Discord Bot | `src/SimpleSkillMessaging.pas` | (none) |
| Google Sheets Export | `src/SimpleExportSheets.pas` | (none) |

Each feature also requires: test file in `tests/`, sample project in `samples/`, CHANGELOG entry, docs update.

---

## Chunk 1: Natural Language Query

### Task 1: SimpleNLQuery — Natural Language to SQL

O usuario faz uma pergunta em linguagem natural, o ORM usa RTTI para montar o schema das entidades registradas, envia para o LLM junto com a pergunta, recebe SQL de volta, executa e retorna o DataSet.

**Files:**
- Create: `src/SimpleNLQuery.pas`
- Modify: `src/SimpleInterface.pas` (add `iSimpleNLQuery` interface)
- Modify: `src/SimpleDAO.pas` (add `Ask` method)
- Test: `tests/TestSimpleNLQuery.pas`
- Sample: `samples/NLQuery/SimpleORMNLQuery.dpr`

- [ ] **Step 1: Define interface in SimpleInterface.pas**

Add after `iSimpleAgent`:
```pascal
iSimpleNLQuery = interface
  ['{A1B2C3D4-5678-9ABC-DEF0-123456789ABC}']
  function RegisterEntity<T: class, constructor>: iSimpleNLQuery;
  function Ask(const aQuestion: String): TDataSet;
  function LastSQL: String;
end;
```

Note: `RegisterEntity<T>` e um metodo generico em interface — isso causa E2535 em Delphi. Alternativa: usar `RegisterEntity(aTypeInfo: PTypeInfo)` com `TypeInfo(T)` no caller. Ou manter apenas na classe concreta.

**Decisao:** Manter interface simples sem generics:
```pascal
iSimpleNLQuery = interface
  ['{A1B2C3D4-5678-9ABC-DEF0-123456789ABC}']
  function Ask(const aQuestion: String): TDataSet;
  function LastSQL: String;
end;
```

- [ ] **Step 2: Create src/SimpleNLQuery.pas**

```pascal
unit SimpleNLQuery;

interface

uses
  SimpleInterface,
  SimpleRTTIHelper,
  SimpleAttributes,
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  Data.DB;

type
  TSimpleNLQuery = class(TInterfacedObject, iSimpleNLQuery)
  private
    FQuery: iSimpleQuery;
    FAIClient: iSimpleAIClient;
    FEntityTypes: TList<PTypeInfo>;
    FLastSQL: String;
    function BuildSchemaPrompt: String;
  public
    constructor Create(aQuery: iSimpleQuery; aAIClient: iSimpleAIClient);
    destructor Destroy; override;
    class function New(aQuery: iSimpleQuery; aAIClient: iSimpleAIClient): TSimpleNLQuery;
    function RegisterEntity(aTypeInfo: PTypeInfo): TSimpleNLQuery;
    function Ask(const aQuestion: String): TDataSet;
    function LastSQL: String;
  end;

implementation

constructor TSimpleNLQuery.Create(aQuery: iSimpleQuery; aAIClient: iSimpleAIClient);
begin
  FQuery := aQuery;
  FAIClient := aAIClient;
  FEntityTypes := TList<PTypeInfo>.Create;
end;

destructor TSimpleNLQuery.Destroy;
begin
  FreeAndNil(FEntityTypes);
  inherited;
end;

class function TSimpleNLQuery.New(aQuery: iSimpleQuery; aAIClient: iSimpleAIClient): TSimpleNLQuery;
begin
  Result := Self.Create(aQuery, aAIClient);
end;

function TSimpleNLQuery.RegisterEntity(aTypeInfo: PTypeInfo): TSimpleNLQuery;
begin
  Result := Self;
  FEntityTypes.Add(aTypeInfo);
end;

function TSimpleNLQuery.BuildSchemaPrompt: String;
var
  LContext: TRttiContext;
  LTypeInfo: PTypeInfo;
  LType: TRttiType;
  LProp: TRttiProperty;
  LTableName: String;
  LTypeName: String;
begin
  Result := '';
  LContext := TRttiContext.Create;
  try
    for LTypeInfo in FEntityTypes do
    begin
      LType := LContext.GetType(LTypeInfo);
      if LType = nil then
        Continue;

      if LType.Tem<Tabela> then
        LTableName := LType.GetAttribute<Tabela>.Name
      else
        LTableName := UpperCase(Copy(LType.Name, 2, Length(LType.Name)));

      Result := Result + 'TABLE ' + LTableName + ' (';

      for LProp in LType.GetProperties do
      begin
        if LProp.IsIgnore then
          Continue;

        case LProp.PropertyType.TypeKind of
          tkInteger, tkInt64: LTypeName := 'INTEGER';
          tkFloat: LTypeName := 'FLOAT';
          tkUString, tkString, tkLString, tkWString: LTypeName := 'VARCHAR';
        else
          LTypeName := 'VARCHAR';
        end;

        Result := Result + LProp.FieldName + ' ' + LTypeName;
        if LProp.EhChavePrimaria then
          Result := Result + ' PK';
        if LProp.EhChaveEstrangeira then
          Result := Result + ' FK';
        Result := Result + ', ';
      end;

      Result := Result + ')' + sLineBreak;
    end;
  finally
    LContext.Free;
  end;
end;

function TSimpleNLQuery.Ask(const aQuestion: String): TDataSet;
var
  LPrompt: String;
  LResponse: String;
  LSQL: String;
begin
  if FAIClient = nil then
    raise Exception.Create('NLQuery requires an AI client');

  LPrompt :=
    'You are a SQL expert. Given the following database schema:' + sLineBreak +
    sLineBreak +
    BuildSchemaPrompt + sLineBreak +
    'Database type: ' + GetEnumName(TypeInfo(TSQLType), Ord(FQuery.SQLType)) + sLineBreak +
    sLineBreak +
    'Generate a SQL SELECT query to answer this question:' + sLineBreak +
    aQuestion + sLineBreak +
    sLineBreak +
    'Return ONLY the SQL query, nothing else. No markdown, no explanation.';

  LResponse := FAIClient.Complete(LPrompt);

  // Clean response — remove markdown code blocks if present
  LSQL := Trim(LResponse);
  if LSQL.StartsWith('```') then
  begin
    LSQL := Copy(LSQL, Pos(sLineBreak, LSQL) + Length(sLineBreak), MaxInt);
    if LSQL.EndsWith('```') then
      LSQL := Copy(LSQL, 1, Length(LSQL) - 3);
    LSQL := Trim(LSQL);
  end;

  FLastSQL := LSQL;

  FQuery.SQL.Clear;
  FQuery.SQL.Add(LSQL);
  FQuery.Open;
  Result := FQuery.DataSet;
end;

function TSimpleNLQuery.LastSQL: String;
begin
  Result := FLastSQL;
end;

end.
```

- [ ] **Step 3: Add `Ask` convenience method to TSimpleDAO**

Em `SimpleDAO.pas`, adicionar no public de `TSimpleDAO<T>`:
```pascal
function Ask(const aQuestion: String): TDataSet;
```

Implementacao:
```pascal
function TSimpleDAO<T>.Ask(const aQuestion: String): TDataSet;
var
  LNLQuery: TSimpleNLQuery;
begin
  if FAIClient = nil then
    raise Exception.Create('Ask requires an AI client. Call .AIClient(...) first.');

  LNLQuery := TSimpleNLQuery.New(FQuery, FAIClient);
  try
    LNLQuery.RegisterEntity(TypeInfo(T));
    Result := LNLQuery.Ask(aQuestion);
  finally
    FreeAndNil(LNLQuery);
  end;
end;
```

Tambem adicionar `Ask` na interface `iSimpleDAO<T>` em `SimpleInterface.pas`:
```pascal
function Ask(const aQuestion: String): TDataSet;
```

- [ ] **Step 4: Write tests**

Criar `tests/TestSimpleNLQuery.pas` com testes para:
- `BuildSchemaPrompt` gera schema correto a partir de entidade decorada
- `Ask` com mock de AIClient retorna DataSet

- [ ] **Step 5: Create sample project**

Criar `samples/NLQuery/SimpleORMNLQuery.dpr` — console app que demonstra:
```pascal
LNLQuery := TSimpleNLQuery.New(LQuery, LAIClient);
LNLQuery.RegisterEntity(TypeInfo(TProduto));
LNLQuery.RegisterEntity(TypeInfo(TPedido));
LDataSet := LNLQuery.Ask('quais produtos foram vendidos mais de 10 vezes?');
```

- [ ] **Step 6: Register unit and commit**

Adicionar `SimpleNLQuery` em `SimpleORM.dpk` e `SimpleORM.dpr`. Atualizar CHANGELOG.

---

## Chunk 2: Auto Swagger/OpenAPI

### Task 2: SimpleSwagger — OpenAPI spec auto-generation

Gera spec OpenAPI 3.0 JSON automaticamente a partir das entidades registradas via `RegisterEntity<T>`, usando RTTI para extrair schema de propriedades. Integra com Horse para servir em `GET /swagger.json`.

**Files:**
- Create: `src/SimpleSwagger.pas`
- Modify: `src/SimpleHorseRouter.pas` (add auto-register swagger route)
- Test: `tests/TestSimpleSwagger.pas`
- Sample: `samples/Swagger/SimpleORMSwagger.dpr`

- [ ] **Step 1: Create src/SimpleSwagger.pas**

```pascal
unit SimpleSwagger;

interface

uses
  SimpleAttributes,
  SimpleRTTIHelper,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections;

type
  TSimpleSwagger = class
  private
    FTitle: String;
    FVersion: String;
    FDescription: String;
    FBasePath: String;
    FEntities: TList<PTypeInfo>;
    FPaths: TList<String>;
    function BuildSchemaForType(aType: TRttiType): TJSONObject;
    function BuildPathsForEntity(aType: TRttiType; const aPath: String): TJSONObject;
    function DelphiTypeToSwaggerType(aTypeKind: TTypeKind): String;
    function DelphiTypeToSwaggerFormat(aTypeKind: TTypeKind; aTypeInfo: PTypeInfo): String;
  public
    constructor Create;
    destructor Destroy; override;
    class function New: TSimpleSwagger;
    function Title(const aValue: String): TSimpleSwagger;
    function Version(const aValue: String): TSimpleSwagger;
    function Description(const aValue: String): TSimpleSwagger;
    function BasePath(const aValue: String): TSimpleSwagger;
    function RegisterEntity(aTypeInfo: PTypeInfo; const aPath: String): TSimpleSwagger;
    function Generate: TJSONObject;
    function GenerateAsString: String;
  end;

implementation
// Implementacao completa que:
// - Itera entidades registradas via RTTI
// - Para cada entidade gera schema com properties (tipo mapeado de Delphi para JSON Schema)
// - Gera paths GET/POST/PUT/DELETE seguindo o padrao do SimpleHorseRouter
// - Monta objeto OpenAPI 3.0 completo com info, paths, components/schemas
// - GET /{entity} retorna array, GET /{entity}/{id} retorna objeto
// - POST aceita body JSON, PUT aceita body + path param :id
// - DELETE aceita path param :id
// - Respostas: 200, 201, 204, 400, 404, 500
end.
```

- [ ] **Step 2: Integrate with SimpleHorseRouter**

Em `SimpleHorseRouter.pas`, adicionar classe method:
```pascal
class procedure EnableSwagger(aApp: THorse;
  const aTitle: String = 'SimpleORM API';
  const aVersion: String = '1.0.0');
```

Que registra `GET /swagger.json` retornando o spec gerado. Cada `RegisterEntity<T>` tambem registra a entidade no swagger global.

- [ ] **Step 3: Write tests**

Testar: schema gerado contém propriedades corretas, tipos mapeados, paths gerados para entidade.

- [ ] **Step 4: Create sample and commit**

---

## Chunk 3: Smart Seeder

### Task 3: SimpleSeeder — AI-powered test data generation

Gera dados de teste realistas usando LLM baseado no schema RTTI da entidade. O LLM recebe o schema e retorna JSON array com dados que fazem sentido (nomes reais, emails validos, valores coerentes).

**Files:**
- Create: `src/SimpleSeeder.pas`
- Test: `tests/TestSimpleSeeder.pas`
- Sample: `samples/Seeder/SimpleORMSeeder.dpr`

- [ ] **Step 1: Create src/SimpleSeeder.pas**

```pascal
unit SimpleSeeder;

interface

uses
  SimpleInterface,
  SimpleAttributes,
  SimpleRTTIHelper,
  SimpleSerializer,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections;

type
  TSimpleSeeder = class
  private
    FAIClient: iSimpleAIClient;
    function BuildSchemaDescription(aTypeInfo: PTypeInfo): String;
  public
    constructor Create(aAIClient: iSimpleAIClient);
    destructor Destroy; override;
    class function New(aAIClient: iSimpleAIClient): TSimpleSeeder;
    function Generate<T: class, constructor>(aCount: Integer): TObjectList<T>;
    function GenerateAndInsert<T: class, constructor>(aDAO: iSimpleDAO<T>; aCount: Integer): TObjectList<T>;
  end;

implementation
// BuildSchemaDescription usa RTTI para gerar descricao textual:
// "Entity PRODUTO with fields: ID (INTEGER, PK, AutoInc), NOME (VARCHAR, NotNull), PRECO (FLOAT), EMAIL (VARCHAR, Email validation)"
//
// Generate<T> envia prompt para LLM:
// "Generate {aCount} realistic records for entity PRODUTO as a JSON array.
//  Schema: {schema}
//  Rules: skip AutoInc fields, generate valid emails for Email fields,
//  respect NotNull, use realistic Brazilian Portuguese data.
//  Return ONLY the JSON array."
//
// Parseia resposta JSON e usa TSimpleSerializer.JSONToEntity<T> para criar objetos.
//
// GenerateAndInsert<T> chama Generate<T> e depois DAO.InsertBatch ou DAO.BulkInsert.
end.
```

- [ ] **Step 2: Write tests and sample**

- [ ] **Step 3: Register and commit**

---

## Chunk 4: AI Auto-Index

### Task 4: SimpleAutoIndex — AI-powered index suggestions

Analisa o historico de queries logadas pelo `iSimpleQueryLogger` e sugere CREATE INDEX para otimizar as queries mais lentas ou frequentes.

**Files:**
- Create: `src/SimpleAutoIndex.pas`
- Test: `tests/TestSimpleAutoIndex.pas`
- Sample: `samples/AutoIndex/SimpleORMAutoIndex.dpr`

- [ ] **Step 1: Create src/SimpleAutoIndex.pas**

```pascal
unit SimpleAutoIndex;

interface

uses
  SimpleInterface,
  SimpleAttributes,
  SimpleRTTIHelper,
  SimpleLogger,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Data.DB;

type
  TIndexSuggestion = record
    TableName: String;
    FieldNames: String;
    IndexType: String;   // 'SINGLE', 'COMPOSITE', 'UNIQUE'
    Reason: String;
    CreateSQL: String;
    EstimatedImpact: String; // 'HIGH', 'MEDIUM', 'LOW'
  end;

  TSimpleQueryLog = record
    SQL: String;
    DurationMs: Int64;
    ExecutionCount: Integer;
  end;

  TSimpleAutoIndex = class
  private
    FAIClient: iSimpleAIClient;
    FEntityTypes: TList<PTypeInfo>;
    FQueryLogs: TList<TSimpleQueryLog>;
    function BuildAnalysisPrompt: String;
    function ParseSuggestions(const aResponse: String): TArray<TIndexSuggestion>;
  public
    constructor Create(aAIClient: iSimpleAIClient);
    destructor Destroy; override;
    class function New(aAIClient: iSimpleAIClient): TSimpleAutoIndex;
    function RegisterEntity(aTypeInfo: PTypeInfo): TSimpleAutoIndex;
    function AddQueryLog(const aSQL: String; aDurationMs: Int64; aCount: Integer = 1): TSimpleAutoIndex;
    function Analyze: TArray<TIndexSuggestion>;
    function AnalyzeAndExecute(aQuery: iSimpleQuery): Integer;
  end;

implementation
// AddQueryLog acumula queries para analise.
// Analyze envia schema + queries para LLM pedindo sugestoes de indice.
// AnalyzeAndExecute executa os CREATE INDEX sugeridos (com confirmacao).
// Prompt para LLM inclui: schema das entidades, queries com duracao,
// e pede resposta estruturada com CREATE INDEX statements.
end.
```

- [ ] **Step 2: Implement logger collector**

Criar `TSimpleQueryLoggerCollector` que implementa `iSimpleQueryLogger` e acumula logs em memória para posterior análise:
```pascal
TSimpleQueryLoggerCollector = class(TInterfacedObject, iSimpleQueryLogger)
private
  FLogs: TList<TSimpleQueryLog>;
  FInner: iSimpleQueryLogger;  // delegate para logger original
public
  procedure Log(const aSQL: string; aParams: TParams; aDurationMs: Int64);
  function GetLogs: TList<TSimpleQueryLog>;
end;
```

- [ ] **Step 3: Write tests, sample, register and commit**

---

## Chunk 5: AI Query Optimizer

### Task 5: SimpleQueryOptimizer — AI-powered query optimization

Antes de executar um SQL, envia para o LLM analisar e sugerir otimizacoes. Pode ser usado como skill ou standalone.

**Files:**
- Create: `src/SimpleQueryOptimizer.pas`
- Test: `tests/TestSimpleQueryOptimizer.pas`

- [ ] **Step 1: Create src/SimpleQueryOptimizer.pas**

```pascal
unit SimpleQueryOptimizer;

interface

uses
  SimpleInterface,
  SimpleTypes,
  SimpleAttributes,
  SimpleRTTIHelper,
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections;

type
  TQueryOptimization = record
    OriginalSQL: String;
    OptimizedSQL: String;
    Suggestions: String;     // texto livre com sugestoes
    HasOptimization: Boolean;
  end;

  TSimpleQueryOptimizer = class
  private
    FAIClient: iSimpleAIClient;
    FEntityTypes: TList<PTypeInfo>;
    function BuildSchemaContext: String;
  public
    constructor Create(aAIClient: iSimpleAIClient);
    destructor Destroy; override;
    class function New(aAIClient: iSimpleAIClient): TSimpleQueryOptimizer;
    function RegisterEntity(aTypeInfo: PTypeInfo): TSimpleQueryOptimizer;
    function Optimize(const aSQL: String; aSQLType: TSQLType): TQueryOptimization;
  end;

  { Skill wrapper — pode ser adicionado ao DAO como skill }
  TSkillQueryOptimizer = class(TInterfacedObject, iSimpleSkill)
  private
    FOptimizer: TSimpleQueryOptimizer;
  public
    constructor Create(aAIClient: iSimpleAIClient);
    destructor Destroy; override;
    class function New(aAIClient: iSimpleAIClient): iSimpleSkill;
    function Execute(aEntity: TObject; aContext: iSimpleSkillContext): iSimpleSkill;
    function Name: String;
    function RunAt: TSkillRunAt;
    function RunMode: TSkillRunMode;
  end;

implementation
// Optimize envia SQL + schema para LLM pedindo:
// 1. Analise de problemas (N+1, full scan, missing index)
// 2. SQL otimizado (se possivel)
// 3. Sugestoes textuais
//
// TSkillQueryOptimizer roda como srBeforeInsert (ou qualquer RunAt)
// e loga as sugestoes via Logger do contexto.
end.
```

- [ ] **Step 2: Write tests, register and commit**

---

## Chunk 6: Telegram/Discord Bot Skill

### Task 6: SimpleSkillMessaging — Messaging notifications

Skills que enviam mensagens para Telegram ou Discord quando entidades mudam. Usa HTTP API direta (sem SDK).

**Files:**
- Create: `src/SimpleSkillMessaging.pas`
- Test: `tests/TestSimpleSkillMessaging.pas`
- Sample: `samples/Messaging/SimpleORMMessaging.dpr`

- [ ] **Step 1: Create src/SimpleSkillMessaging.pas**

```pascal
unit SimpleSkillMessaging;

interface

uses
  SimpleInterface,
  SimpleSerializer,
  SimpleTypes,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient
  {$IFDEF MSWINDOWS}
  , Winapi.Windows
  {$ENDIF};

type
  { Telegram Bot Skill }
  TSkillTelegram = class(TInterfacedObject, iSimpleSkill)
  private
    FBotToken: String;
    FChatId: String;
    FMessageTemplate: String;
    FRunAt: TSkillRunAt;
    function FormatMessage(aEntity: TObject; aContext: iSimpleSkillContext): String;
  public
    constructor Create(const aBotToken, aChatId: String;
      const aMessageTemplate: String = '';
      aRunAt: TSkillRunAt = srAfterInsert);
    destructor Destroy; override;
    class function New(const aBotToken, aChatId: String;
      const aMessageTemplate: String = '';
      aRunAt: TSkillRunAt = srAfterInsert): iSimpleSkill;
    function Execute(aEntity: TObject; aContext: iSimpleSkillContext): iSimpleSkill;
    function Name: String;
    function RunAt: TSkillRunAt;
    function RunMode: TSkillRunMode;
  end;

  { Discord Webhook Skill }
  TSkillDiscord = class(TInterfacedObject, iSimpleSkill)
  private
    FWebhookURL: String;
    FMessageTemplate: String;
    FRunAt: TSkillRunAt;
    function FormatMessage(aEntity: TObject; aContext: iSimpleSkillContext): String;
  public
    constructor Create(const aWebhookURL: String;
      const aMessageTemplate: String = '';
      aRunAt: TSkillRunAt = srAfterInsert);
    destructor Destroy; override;
    class function New(const aWebhookURL: String;
      const aMessageTemplate: String = '';
      aRunAt: TSkillRunAt = srAfterInsert): iSimpleSkill;
    function Execute(aEntity: TObject; aContext: iSimpleSkillContext): iSimpleSkill;
    function Name: String;
    function RunAt: TSkillRunAt;
    function RunMode: TSkillRunMode;
  end;

implementation

// TSkillTelegram.Execute:
// POST https://api.telegram.org/bot{token}/sendMessage
// Body: {"chat_id": "{chatId}", "text": "{message}", "parse_mode": "HTML"}
//
// TSkillDiscord.Execute:
// POST {webhookURL}
// Body: {"content": "{message}"}
//
// FormatMessage substitui placeholders:
// {entity} = nome da entidade
// {operation} = INSERT/UPDATE/DELETE
// {timestamp} = data/hora
// {data} = JSON da entidade
// Template padrao: "[SimpleORM] {operation} em {entity} em {timestamp}"
//
// Erros sao logados mas NAO interrompem o fluxo (fire-and-forget)
end.
```

- [ ] **Step 2: Write tests, sample, register and commit**

---

## Chunk 7: Google Sheets Export

### Task 7: SimpleExportSheets — Export entity data to Google Sheets

Exporta dados de entidades para Google Sheets via API REST. Suporta criar nova planilha ou atualizar existente.

**Files:**
- Create: `src/SimpleExportSheets.pas`
- Test: `tests/TestSimpleExportSheets.pas`
- Sample: `samples/GoogleSheets/SimpleORMGoogleSheets.dpr`

- [ ] **Step 1: Create src/SimpleExportSheets.pas**

```pascal
unit SimpleExportSheets;

interface

uses
  SimpleAttributes,
  SimpleRTTIHelper,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Rtti,
  System.TypInfo,
  System.Net.HttpClient,
  System.Net.URLClient,
  System.Generics.Collections;

type
  TSimpleExportSheets = class
  private
    FAccessToken: String;
    FSpreadsheetId: String;
    FSheetName: String;
    function EntityListToRows<T: class>(aList: TObjectList<T>): TJSONArray;
    function GetHeaders<T: class>: TJSONArray;
    procedure DoRequest(const aURL, aMethod: String; aBody: TJSONValue);
  public
    constructor Create(const aAccessToken: String);
    destructor Destroy; override;
    class function New(const aAccessToken: String): TSimpleExportSheets;
    function SpreadsheetId(const aValue: String): TSimpleExportSheets;
    function SheetName(const aValue: String): TSimpleExportSheets;
    function Export<T: class>(aList: TObjectList<T>): TSimpleExportSheets;
    function CreateSpreadsheet(const aTitle: String): String; // returns spreadsheet ID
  end;

implementation

// Export<T>:
// 1. Usa RTTI para extrair headers (DisplayName ou FieldName de cada property)
// 2. Itera lista e converte valores para array de arrays
// 3. PUT https://sheets.googleapis.com/v4/spreadsheets/{id}/values/{sheet}!A1
//    Body: {"range": "Sheet1!A1", "majorDimension": "ROWS", "values": [[headers], [row1], [row2]]}
//    Header: Authorization: Bearer {token}
//
// CreateSpreadsheet:
// POST https://sheets.googleapis.com/v4/spreadsheets
// Body: {"properties": {"title": "{aTitle}"}}
// Retorna o spreadsheetId da resposta
//
// EntityListToRows itera propriedades via RTTI, converte para string,
// monta TJSONArray de TJSONArray.
end.
```

- [ ] **Step 2: Write tests, sample, register and commit**

---

## Final Checklist

Apos implementar todas as 7 features:

- [ ] Rodar `/delphi-validate` para verificar compatibilidade 10.2+
- [ ] Registrar todas as novas units em `SimpleORM.dpk` e `SimpleORM.dpr`
- [ ] Atualizar `CHANGELOG.md` com todas as features na secao Added
- [ ] Atualizar `docs/index.html` com novas secoes
- [ ] Atualizar `CLAUDE.md` com descricao das novas features

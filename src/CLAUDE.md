# CLAUDE.md — src/

Regras e padroes obrigatorios para todo codigo em `src/`. Qualquer nova unit ou modificacao DEVE seguir estas convencoes.

## Padrao de Classe

Toda classe principal segue o padrao `TSimpleXxx` com interface e construtor `New`:

```pascal
TSimpleXxx = class(TInterfacedObject, iSimpleXxx)
  constructor Create(...);
  class function New(...): iSimpleXxx;
end;
```

- Herdar de `TInterfacedObject` para reference counting
- `New` e um class function que chama `Self.Create(...)` e retorna a interface
- Todos os metodos publicos retornam `Self` (fluent interface) exceto getters

## Interfaces

- Todas as interfaces ficam em `SimpleInterface.pas` — NUNCA declarar interfaces em outras units
- Toda interface tem um GUID: `['{GUID}']`
- Usar `iSimple` como prefixo (nao `ISimple`)
- Metodos que sao palavras reservadas do Delphi usam `&` escape: `function &End`, `function &EndTransaction`

## Atributos de Entidade

- Todos os atributos ficam em `SimpleAttributes.pas`
- Nao criar atributos em outras units
- Padroes:
  - Atributo simples (flag): `class(TCustomAttribute)` sem campos
  - Atributo com valor: `constructor Create(aValue)` + `property Value read FValue`
- Propriedades da entidade devem ser `published` para que RTTI funcione

## RTTI Helpers

- `SimpleRTTIHelper.pas` contem class helpers para `TRttiProperty`, `TRttiType`, `TRttiField`
- Nomenclatura mista (portugues legado + ingles):
  - Portugues: `EhChavePrimaria`, `EhChaveEstrangeira`, `EhCampo`, `EhSomenteNumeros`, `Tem<T>`
  - Ingles: `IsNotNull`, `IsIgnore`, `IsAutoInc`, `IsHasOne`, `HasFormat`, `GetRelationship`
- Para novos helpers: usar ingles (`Is`, `Has`, `Get` prefixes)
- O metodo `FieldName` retorna o nome do atributo `[Campo]` ou o nome da propriedade como fallback

## Drivers de Query (SimpleQueryXxx.pas)

Todo driver implementa `iSimpleQuery` e DEVE seguir este padrao:

```pascal
TSimpleQueryXxx = class(TInterfacedObject, iSimpleQuery)
  constructor Create(aConnection: TXxxConnection; aSQLType: TSQLType = TSQLType.Firebird);
  class function New(aConnection: TXxxConnection; aSQLType: TSQLType = TSQLType.Firebird): iSimpleQuery;
end;
```

### Metodos obrigatorios:
- `SQL: TStrings` — retorna a lista de SQL (TStringList ou componente interno)
- `Params: TParams` — retorna parametros (criar lazy se necessario como FireDAC faz)
- `ExecSQL: iSimpleQuery` — executa INSERT/UPDATE/DELETE. DEVE re-lancar excecoes apos rollback
- `DataSet: TDataSet` — retorna o dataset interno
- `Open(aSQL): iSimpleQuery` — abre query com SQL
- `Open: iSimpleQuery` — abre query com SQL ja definido
- `StartTransaction/Commit/Rollback/EndTransaction/InTransaction` — controle de transacao
- `SQLType: TSQLType` — retorna o tipo de banco

### Regras de implementacao:
- `ExecSQL` DEVE fazer try/except: em caso de erro, fazer Rollback e `raise` (nunca engolir excecao)
- `EndTransaction` DEVE delegar para `Commit`
- Transacoes: verificar se ja esta ativa antes de iniciar (`if not Active then StartTransaction`)
- Drivers REST (RestDW, Horse): transacoes sao no-ops que retornam Self

## SQL Generation (SimpleSQL.pas)

- `TSimpleSQL<T>` gera SQL a partir de RTTI da entidade
- Metodos de geracao recebem `var aSQL: String` (acumulam no parametro)
- Paginacao e banco-especifica:
  - Firebird: `FIRST n SKIP n` (apos SELECT)
  - MySQL/SQLite: `LIMIT n OFFSET n` (fim da query)
  - Oracle: `OFFSET n ROWS FETCH NEXT n ROWS ONLY` (fim da query)
- Soft Delete: `Delete` gera `UPDATE SET campo=1` em vez de `DELETE` quando `[SoftDelete]` presente
- Soft Delete: `Select` adiciona `WHERE campo = 0` automaticamente

## DAO (SimpleDAO.pas)

- `TSimpleDAO<T>` orquestra: gera SQL via `TSimpleSQL`, preenche params via `TSimpleRTTI`, executa via `iSimpleQuery`
- `FillParameter` usa dicionarios RTTI para mapear campos → valores nos params
- Batch operations (`InsertBatch/UpdateBatch/DeleteBatch`) usam `StartTransaction/Commit/Rollback` automaticamente
- `LoadRelationships` carrega `HasOne`/`BelongsTo` automaticamente (eager loading). `HasMany` e manual via `TSimpleLazyLoader<T>`
- Logger: se `FLogger` esta atribuido, logar SQL + Params + ElapsedMilliseconds via `TStopwatch`

## Serializer (SimpleSerializer.pas)

- Usa RTTI direto (nao SimpleRTTI) para converter Entity ↔ JSON
- Nomes JSON = valor de `[Campo]` (nao nome da propriedade Delphi)
- `[Ignore]` e respeitado — pula propriedades
- TDateTime serializa como ISO8601
- Memory safety: `JSONToEntity` e `JSONArrayToEntityList` tem try/except para liberar objetos em caso de erro

## Validator (SimpleValidator.pas)

- `TSimpleValidator.Validate(object)` itera propriedades via RTTI
- Cada validacao e um metodo `class procedure ValidateXxx` privado
- Mensagens de erro em portugues (constantes `sMSG_*`)
- `SysUtils.Format` deve ser qualificado completamente para evitar conflito com `SimpleAttributes.Format`
- `ESimpleValidator` e a exception lancada com erros acumulados

## Horse Integration

- `SimpleHorseRouter.pas`: auto-gera rotas CRUD. Recebe `iSimpleQuery` (nao iSimpleDAO) para thread safety
- `SimpleQueryHorse.pas`: driver REST que parseia SQL para fazer chamadas HTTP
- `SimpleSerializer.pas`: compartilhado entre servidor e cliente

## Compilacao Condicional

- `{$IFNDEF CONSOLE}` — envolve todo codigo de UI (forms, VCL/FMX components)
- `{$IFDEF FMX}` / `{$IFDEF VCL}` — seleciona framework visual
- `{$IF RTLVERSION > 31.0}` — guarda tipos RTTI mais novos (`tkMRecord`)
- NUNCA colocar logica de negocio dentro de IFDEFs de UI

## Nomenclatura

- Units: `SimpleXxx.pas` (PascalCase)
- Classes: `TSimpleXxx`
- Interfaces: `iSimpleXxx` (i minusculo)
- Excecoes: `ESimpleXxx`
- Variaveis locais: prefixo `L` para locais novas, ou `a` para parametros (padrao legado misto — aceitar ambos, preferir `L` em codigo novo)
- Campos privados: prefixo `F`
- Parametros: prefixo `a`

## Regras de Seguranca

- NUNCA concatenar valores do usuario em SQL — usar parametros (`:fieldname`)
- Excecoes NUNCA devem ser engolidas silenciosamente — sempre `raise` apos cleanup
- Memory management: usar try/finally para objetos, try/except para liberar em caso de erro
agora p
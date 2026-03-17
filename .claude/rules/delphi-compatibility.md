# Regras de Compatibilidade Delphi

Versao minima suportada: **Delphi 10.2 Tokyo** (CompilerVersion 32.0, RTLVersion 32.0).
Todo codigo DEVE compilar sem erros no Delphi 10.2+.

## Variaveis Inline (PROIBIDO)

Variaveis inline foram introduzidas no Delphi 10.3 Rio. NAO usar:

- `var X: Tipo` ou `var X :=` DENTRO de blocos begin/end — NUNCA
- `for var X` em loops — NUNCA
- `const X :=` DENTRO de blocos begin/end — NUNCA

CORRETO:
```pascal
var
  I: Integer;
  LName: String;
begin
  LName := 'valor';
  for I := 0 to 10 do ...
end;
```

ERRADO:
```pascal
begin
  var LName := 'valor';       // PROIBIDO - requer 10.3
  for var I := 0 to 10 do ... // PROIBIDO - requer 10.3
end;
```

## Managed Records (PROIBIDO)

Managed records foram introduzidos no Delphi 10.4 Sydney. NAO usar:

- `class operator Initialize` — NUNCA
- `class operator Finalize` — NUNCA
- `tkMRecord` DEVE estar dentro de `{$IF RTLVERSION > 33.0}`

## Qualificacao de Units (OBRIGATORIO)

- SEMPRE usar nomes fully qualified para units RTL: `System.SysUtils`, `System.Classes`, `System.Variants`
- NUNCA usar `Format(` bare quando `SimpleAttributes` esta no uses — usar `System.SysUtils.Format(`
- NUNCA usar `SysUtils.Format(` — usar `System.SysUtils.Format(` (caminho completo)

## Uses Clause — Visibilidade (OBRIGATORIO)

- Tipos usados na secao `interface` (campos, parametros, tipos) DEVEM ter sua unit no `interface uses`
- Ter a unit apenas no `implementation uses` NAO e suficiente para tipos usados na interface
- NUNCA duplicar units entre interface uses e implementation uses
- NUNCA ter a mesma unit com nomes diferentes nos dois blocos (ex: `TypInfo` + `System.TypInfo`)

## Generics — E2506 (OBRIGATORIO)

- Metodos de classes genericas declaradas na interface (`TSimpleXxx<T>`) NAO podem usar simbolos locais da implementation
- Funcoes/procedures usadas por metodos genericos DEVEM ser declaradas na secao interface ou em units do uses
- Forward declarations de interfaces referenciadas antes de sua definicao completa DEVEM existir no mesmo bloco type

## Compilacao Condicional (OBRIGATORIO)

- `tkMRecord` DEVE estar dentro de `{$IF RTLVERSION > 33.0}` (10.4+)
- Features 10.3+ usadas opcionalmente DEVEM ter guard `{$IF RTLVERSION > 32.0}`
- Toda diretiva `{$IF}` DEVE ter `{$ENDIF}` correspondente
- SEMPRE verificar a tabela de versoes:

| Delphi | CompilerVersion | RTLVersion |
|--------|----------------|------------|
| 10.2 Tokyo | 32.0 | 32.0 |
| 10.3 Rio | 33.0 | 33.0 |
| 10.4 Sydney | 34.0 | 34.0 |
| 11 Alexandria | 35.0 | 35.0 |
| 12 Athens | 36.0 | 36.0 |

## Dependencias de Units por Tipo

Ao usar um tipo, garantir que a unit correspondente esta no uses:

| Tipo | Unit |
|------|------|
| Exception | System.SysUtils |
| TStringList, TStringStream | System.Classes |
| VarToStr | System.Variants |
| OutputDebugString | Winapi.Windows (com {$IFDEF MSWINDOWS}) |
| PTypeInfo, GetEnumName | System.TypInfo |
| TRttiContext, TValue | System.Rtti |
| THTTPClient | System.Net.HttpClient |
| TJSONObject, TJSONArray | System.JSON |
| TStopwatch | System.Diagnostics |
| TObjectList, TList, TDictionary | System.Generics.Collections |
| TDataSet, TParams, TField | Data.DB |

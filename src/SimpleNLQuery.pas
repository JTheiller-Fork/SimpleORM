unit SimpleNLQuery;

interface

uses
  SimpleInterface,
  SimpleAttributes,
  SimpleRTTIHelper,
  SimpleTypes,
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  Data.DB;

type
  ESimpleNLQuery = class(Exception);

  TSimpleNLQuery = class(TInterfacedObject)
  private
    FAIClient: iSimpleAIClient;
    FQuery: iSimpleQuery;
    FEntityTypes: TList<PTypeInfo>;
    FSelectOnly: Boolean;
    FLastSQL: String;
    function BuildSchemaContext: String;
    function BuildSQLTypeHint: String;
    function BuildPrompt(const aQuestion: String): String;
    function ExtractSQL(const aResponse: String): String;
    procedure ValidateSQL(const aSQL: String);
  public
    constructor Create(aQuery: iSimpleQuery; aAIClient: iSimpleAIClient);
    destructor Destroy; override;
    class function New(aQuery: iSimpleQuery; aAIClient: iSimpleAIClient): TSimpleNLQuery;
    function RegisterEntity(aTypeInfo: PTypeInfo): TSimpleNLQuery;
    function SelectOnly(aValue: Boolean): TSimpleNLQuery;
    function Ask(const aQuestion: String): TDataSet;
    function LastSQL: String;
  end;

implementation

{ TSimpleNLQuery }

constructor TSimpleNLQuery.Create(aQuery: iSimpleQuery; aAIClient: iSimpleAIClient);
begin
  FQuery := aQuery;
  FAIClient := aAIClient;
  FEntityTypes := TList<PTypeInfo>.Create;
  FSelectOnly := True;
  FLastSQL := '';
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
  if FEntityTypes.IndexOf(aTypeInfo) < 0 then
    FEntityTypes.Add(aTypeInfo);
end;

function TSimpleNLQuery.SelectOnly(aValue: Boolean): TSimpleNLQuery;
begin
  Result := Self;
  FSelectOnly := aValue;
end;

function TSimpleNLQuery.BuildSchemaContext: String;
var
  LContext: TRttiContext;
  LTypeInfo: PTypeInfo;
  LType: TRttiType;
  LProp: TRttiProperty;
  LTableName: String;
  LFieldInfo: String;
  LPKName: String;
  LPKProp: TRttiProperty;
  LFirstField: Boolean;
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
        LTableName := LType.Name;

      LPKName := '';
      LPKProp := LType.GetPKField;
      if LPKProp <> nil then
        LPKName := LPKProp.FieldName;

      if Result <> '' then
        Result := Result + #13#10;

      Result := Result + 'TABLE ' + LTableName + ' (';

      LFirstField := True;
      for LProp in LType.GetProperties do
      begin
        if LProp.IsIgnore then
          Continue;

        if not LFirstField then
          Result := Result + ', ';
        LFirstField := False;

        LFieldInfo := LProp.FieldName;

        // Add type hint
        case LProp.PropertyType.TypeKind of
          tkInteger, tkInt64:
            LFieldInfo := LFieldInfo + ' INTEGER';
          tkFloat:
            LFieldInfo := LFieldInfo + ' FLOAT';
          tkUString, tkString, tkWString, tkLString:
            LFieldInfo := LFieldInfo + ' VARCHAR';
        else
          LFieldInfo := LFieldInfo + ' VARCHAR';
        end;

        if LProp.FieldName = LPKName then
          LFieldInfo := LFieldInfo + ' PK';
        if LProp.IsAutoInc then
          LFieldInfo := LFieldInfo + ' AUTOINC';
        if LProp.IsNotNull then
          LFieldInfo := LFieldInfo + ' NOT NULL';

        Result := Result + LFieldInfo;
      end;

      Result := Result + ')';

      // Add soft delete info
      if LType.IsSoftDelete then
        Result := Result + ' [SOFT DELETE: ' + LType.GetSoftDeleteField + '=0 means active]';
    end;
  finally
    LContext.Free;
  end;
end;

function TSimpleNLQuery.BuildSQLTypeHint: String;
begin
  case FQuery.SQLType of
    TSQLType.Firebird:
      Result := 'Firebird SQL dialect. Use FIRST/SKIP for pagination (e.g., SELECT FIRST 10 SKIP 0 ...). Use || for string concatenation.';
    TSQLType.MySQL:
      Result := 'MySQL dialect. Use LIMIT/OFFSET for pagination. Use CONCAT() for string concatenation.';
    TSQLType.SQLite:
      Result := 'SQLite dialect. Use LIMIT/OFFSET for pagination. Use || for string concatenation.';
    TSQLType.Oracle:
      Result := 'Oracle SQL dialect. Use OFFSET/FETCH NEXT for pagination. Use || for string concatenation.';
  else
    Result := 'Standard SQL.';
  end;
end;

function TSimpleNLQuery.BuildPrompt(const aQuestion: String): String;
var
  LSelectClause: String;
begin
  if FSelectOnly then
    LSelectClause := 'IMPORTANT: Generate ONLY SELECT statements. Never generate INSERT, UPDATE, DELETE, DROP, ALTER, TRUNCATE, or any data-modifying statement.'
  else
    LSelectClause := 'You may generate SELECT, INSERT, UPDATE, or DELETE statements as needed by the question.';

  Result :=
    'You are a SQL query generator. Given a natural language question and a database schema, ' +
    'generate a single valid SQL query that answers the question.' + #13#10 +
    #13#10 +
    'Database schema:' + #13#10 +
    BuildSchemaContext + #13#10 +
    #13#10 +
    'SQL dialect: ' + BuildSQLTypeHint + #13#10 +
    #13#10 +
    LSelectClause + #13#10 +
    #13#10 +
    'Rules:' + #13#10 +
    '- Generate exactly ONE SQL statement, no semicolons at the end' + #13#10 +
    '- Use only columns and tables from the schema above' + #13#10 +
    '- Do NOT use parameterized queries (no :param syntax) - use literal values' + #13#10 +
    '- Return ONLY the SQL query, no explanation, no markdown, no code blocks' + #13#10 +
    '- If the question cannot be answered with the schema, respond with: ERROR: followed by reason' + #13#10 +
    #13#10 +
    'Question: ' + aQuestion;
end;

function TSimpleNLQuery.ExtractSQL(const aResponse: String): String;
var
  LTrimmed: String;
  LPosStart: Integer;
  LPosEnd: Integer;
begin
  LTrimmed := Trim(aResponse);

  // Check for error response
  if LTrimmed.StartsWith('ERROR:') then
    raise ESimpleNLQuery.Create(LTrimmed);

  // Strip markdown code fences if present
  if LTrimmed.StartsWith('```') then
  begin
    LPosStart := Pos(#10, LTrimmed);
    if LPosStart > 0 then
    begin
      LTrimmed := Copy(LTrimmed, LPosStart + 1, Length(LTrimmed));
      LPosEnd := Pos('```', LTrimmed);
      if LPosEnd > 0 then
        LTrimmed := Copy(LTrimmed, 1, LPosEnd - 1);
    end;
  end;

  Result := Trim(LTrimmed);

  // Remove trailing semicolon
  if (Length(Result) > 0) and (Result[Length(Result)] = ';') then
    Result := Copy(Result, 1, Length(Result) - 1);
end;

procedure TSimpleNLQuery.ValidateSQL(const aSQL: String);
var
  LUpper: String;
begin
  if Trim(aSQL) = '' then
    raise ESimpleNLQuery.Create('AI returned an empty SQL statement');

  LUpper := UpperCase(Trim(aSQL));

  // Always block dangerous statements
  if (Pos('DROP ', LUpper) > 0) or (Pos('TRUNCATE ', LUpper) > 0) or
     (Pos('ALTER ', LUpper) > 0) or (Pos('CREATE ', LUpper) > 0) or
     (Pos('GRANT ', LUpper) > 0) or (Pos('REVOKE ', LUpper) > 0) then
    raise ESimpleNLQuery.Create('SQL statement contains forbidden DDL/DCL commands');

  // Block multiple statements (semicolon injection)
  if Pos(';', aSQL) > 0 then
    raise ESimpleNLQuery.Create('SQL statement contains multiple statements (semicolon detected)');

  // In SelectOnly mode, only allow SELECT
  if FSelectOnly then
  begin
    if not LUpper.StartsWith('SELECT') then
      raise ESimpleNLQuery.Create('SelectOnly mode is enabled - only SELECT statements are allowed');
  end
  else
  begin
    // Even in non-SelectOnly mode, only allow DML
    if not (LUpper.StartsWith('SELECT') or LUpper.StartsWith('INSERT') or
            LUpper.StartsWith('UPDATE') or LUpper.StartsWith('DELETE')) then
      raise ESimpleNLQuery.Create('SQL statement must be a DML statement (SELECT/INSERT/UPDATE/DELETE)');
  end;
end;

function TSimpleNLQuery.Ask(const aQuestion: String): TDataSet;
var
  LPrompt: String;
  LResponse: String;
  LSQL: String;
begin
  if FAIClient = nil then
    raise ESimpleNLQuery.Create('AI client is required for natural language queries. Call AIClient() on the DAO first.');

  if FEntityTypes.Count = 0 then
    raise ESimpleNLQuery.Create('No entity types registered. Register at least one entity type to provide schema context.');

  LPrompt := BuildPrompt(aQuestion);
  LResponse := FAIClient.Complete(LPrompt);
  LSQL := ExtractSQL(LResponse);
  ValidateSQL(LSQL);

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

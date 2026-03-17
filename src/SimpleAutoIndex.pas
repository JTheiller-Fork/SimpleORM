unit SimpleAutoIndex;

interface

uses
  SimpleInterface,
  SimpleAttributes,
  SimpleRTTIHelper,
  SimpleLogger,
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  Data.DB;

type
  TSimpleQueryLog = record
    SQL: String;
    DurationMs: Int64;
    Count: Integer;
  end;

  TIndexSuggestion = record
    TableName: String;
    FieldNames: String;
    IndexType: String;
    Reason: String;
    CreateSQL: String;
    EstimatedImpact: String;
  end;

  TSimpleQueryLoggerCollector = class(TInterfacedObject, iSimpleQueryLogger)
  private
    FInnerLogger: iSimpleQueryLogger;
    FLogs: TList<TSimpleQueryLog>;
    function FindLogIndex(const aSQL: String): Integer;
  public
    constructor Create(aInnerLogger: iSimpleQueryLogger = nil);
    destructor Destroy; override;
    class function New(aInnerLogger: iSimpleQueryLogger = nil): TSimpleQueryLoggerCollector;
    procedure Log(const aSQL: string; aParams: TParams; aDurationMs: Int64);
    function GetLogs: TList<TSimpleQueryLog>;
  end;

  TSimpleAutoIndex = class
  private
    FAIClient: iSimpleAIClient;
    FEntityTypes: TList<PTypeInfo>;
    FQueryLogs: TList<TSimpleQueryLog>;
    function BuildSchemaContext: String;
    function BuildQueryLogContext: String;
    function BuildPrompt: String;
    function ParseSuggestions(const aResponse: String): TArray<TIndexSuggestion>;
  public
    constructor Create(aAIClient: iSimpleAIClient);
    destructor Destroy; override;
    function RegisterEntity(aTypeInfo: PTypeInfo): TSimpleAutoIndex;
    function AddQueryLog(const aSQL: String; aDurationMs: Int64; aCount: Integer = 1): TSimpleAutoIndex;
    function LoadFromCollector(aCollector: TSimpleQueryLoggerCollector): TSimpleAutoIndex;
    function Analyze: TArray<TIndexSuggestion>;
    function AnalyzeAndExecute(aQuery: iSimpleQuery): Integer;
  end;

implementation

{ TSimpleQueryLoggerCollector }

constructor TSimpleQueryLoggerCollector.Create(aInnerLogger: iSimpleQueryLogger);
begin
  inherited Create;
  FInnerLogger := aInnerLogger;
  FLogs := TList<TSimpleQueryLog>.Create;
end;

destructor TSimpleQueryLoggerCollector.Destroy;
begin
  FreeAndNil(FLogs);
  inherited;
end;

class function TSimpleQueryLoggerCollector.New(aInnerLogger: iSimpleQueryLogger): TSimpleQueryLoggerCollector;
begin
  Result := Self.Create(aInnerLogger);
end;

function TSimpleQueryLoggerCollector.FindLogIndex(const aSQL: String): Integer;
var
  I: Integer;
  LLog: TSimpleQueryLog;
begin
  Result := -1;
  for I := 0 to FLogs.Count - 1 do
  begin
    LLog := FLogs[I];
    if LLog.SQL = aSQL then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

procedure TSimpleQueryLoggerCollector.Log(const aSQL: string; aParams: TParams; aDurationMs: Int64);
var
  LIndex: Integer;
  LLog: TSimpleQueryLog;
begin
  LIndex := FindLogIndex(aSQL);
  if LIndex >= 0 then
  begin
    LLog := FLogs[LIndex];
    LLog.Count := LLog.Count + 1;
    if aDurationMs > LLog.DurationMs then
      LLog.DurationMs := aDurationMs;
    FLogs[LIndex] := LLog;
  end
  else
  begin
    LLog.SQL := aSQL;
    LLog.DurationMs := aDurationMs;
    LLog.Count := 1;
    FLogs.Add(LLog);
  end;

  if Assigned(FInnerLogger) then
    FInnerLogger.Log(aSQL, aParams, aDurationMs);
end;

function TSimpleQueryLoggerCollector.GetLogs: TList<TSimpleQueryLog>;
begin
  Result := FLogs;
end;

{ TSimpleAutoIndex }

constructor TSimpleAutoIndex.Create(aAIClient: iSimpleAIClient);
begin
  inherited Create;
  FAIClient := aAIClient;
  FEntityTypes := TList<PTypeInfo>.Create;
  FQueryLogs := TList<TSimpleQueryLog>.Create;
end;

destructor TSimpleAutoIndex.Destroy;
begin
  FreeAndNil(FQueryLogs);
  FreeAndNil(FEntityTypes);
  inherited;
end;

function TSimpleAutoIndex.RegisterEntity(aTypeInfo: PTypeInfo): TSimpleAutoIndex;
begin
  Result := Self;
  if aTypeInfo <> nil then
    FEntityTypes.Add(aTypeInfo);
end;

function TSimpleAutoIndex.AddQueryLog(const aSQL: String; aDurationMs: Int64; aCount: Integer): TSimpleAutoIndex;
var
  LLog: TSimpleQueryLog;
begin
  Result := Self;
  LLog.SQL := aSQL;
  LLog.DurationMs := aDurationMs;
  LLog.Count := aCount;
  FQueryLogs.Add(LLog);
end;

function TSimpleAutoIndex.LoadFromCollector(aCollector: TSimpleQueryLoggerCollector): TSimpleAutoIndex;
var
  LCollectorLogs: TList<TSimpleQueryLog>;
  I: Integer;
begin
  Result := Self;
  if aCollector = nil then
    Exit;

  LCollectorLogs := aCollector.GetLogs;
  for I := 0 to LCollectorLogs.Count - 1 do
    FQueryLogs.Add(LCollectorLogs[I]);
end;

function TSimpleAutoIndex.BuildSchemaContext: String;
var
  LContext: TRttiContext;
  LTypeInfo: PTypeInfo;
  LType: TRttiType;
  LProp: TRttiProperty;
  LTableName: String;
  LFieldInfo: String;
  LFieldName: String;
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

      if Result <> '' then
        Result := Result + #13#10;

      Result := Result + 'TABLE ' + LTableName + ' (';

      LFirstField := True;
      for LProp in LType.GetProperties do
      begin
        if LProp.IsIgnore then
          Continue;

        LFieldName := LProp.FieldName;

        LFieldInfo := '';
        if not LFirstField then
          LFieldInfo := ', ';

        LFieldInfo := LFieldInfo + LFieldName;

        case LProp.PropertyType.TypeKind of
          tkInteger, tkInt64:
            LFieldInfo := LFieldInfo + ' INTEGER';
          tkFloat:
            LFieldInfo := LFieldInfo + ' FLOAT';
          tkString, tkLString, tkWString, tkUString:
            LFieldInfo := LFieldInfo + ' VARCHAR';
        else
          LFieldInfo := LFieldInfo + ' VARCHAR';
        end;

        if LProp.EhChavePrimaria then
          LFieldInfo := LFieldInfo + ' PK';

        if LProp.EhChaveEstrangeira then
          LFieldInfo := LFieldInfo + ' FK';

        if LProp.IsAutoInc then
          LFieldInfo := LFieldInfo + ' AUTOINC';

        if LProp.IsNotNull then
          LFieldInfo := LFieldInfo + ' NOT NULL';

        Result := Result + LFieldInfo;
        LFirstField := False;
      end;

      Result := Result + ')';
    end;
  finally
    LContext.Free;
  end;
end;

function TSimpleAutoIndex.BuildQueryLogContext: String;
var
  LSorted: TList<TSimpleQueryLog>;
  LLog: TSimpleQueryLog;
  LTemp: TSimpleQueryLog;
  I, J: Integer;
  LCount: Integer;
begin
  Result := '';

  if FQueryLogs.Count = 0 then
    Exit;

  LSorted := TList<TSimpleQueryLog>.Create;
  try
    for I := 0 to FQueryLogs.Count - 1 do
      LSorted.Add(FQueryLogs[I]);

    // Sort by score (DurationMs * Count) descending - simple bubble sort
    for I := 0 to LSorted.Count - 2 do
    begin
      for J := 0 to LSorted.Count - 2 - I do
      begin
        if (LSorted[J].DurationMs * LSorted[J].Count) <
           (LSorted[J + 1].DurationMs * LSorted[J + 1].Count) then
        begin
          LTemp := LSorted[J];
          LSorted[J] := LSorted[J + 1];
          LSorted[J + 1] := LTemp;
        end;
      end;
    end;

    LCount := LSorted.Count;
    if LCount > 10 then
      LCount := 10;

    for I := 0 to LCount - 1 do
    begin
      LLog := LSorted[I];
      if Result <> '' then
        Result := Result + #13#10;
      Result := Result + SysUtils.Format('SQL: %s | Duration: %dms | Executions: %d',
        [LLog.SQL, LLog.DurationMs, LLog.Count]);
    end;
  finally
    FreeAndNil(LSorted);
  end;
end;

function TSimpleAutoIndex.BuildPrompt: String;
var
  LSchema: String;
  LQueries: String;
begin
  LSchema := BuildSchemaContext;
  LQueries := BuildQueryLogContext;

  Result :=
    'You are a database index optimization expert.' + #13#10 +
    #13#10 +
    'Database schema:' + #13#10 +
    LSchema + #13#10 +
    #13#10 +
    'Top slow/frequent queries:' + #13#10 +
    LQueries + #13#10 +
    #13#10 +
    'Analyze the queries and schema above. Suggest CREATE INDEX statements ' +
    'that would improve query performance.' + #13#10 +
    #13#10 +
    'Rules:' + #13#10 +
    '- Do NOT suggest indexes on columns that already have PK (primary keys are auto-indexed)' + #13#10 +
    '- Focus on WHERE clause columns, JOIN columns, and ORDER BY columns' + #13#10 +
    '- Consider composite indexes for multi-column WHERE clauses' + #13#10 +
    '- Suggest UNIQUE indexes when the data model implies uniqueness' + #13#10 +
    #13#10 +
    'Respond with one suggestion per line in this exact format:' + #13#10 +
    'TABLE|FIELDS|TYPE|REASON|SQL|IMPACT' + #13#10 +
    #13#10 +
    'Where:' + #13#10 +
    '- TABLE = table name' + #13#10 +
    '- FIELDS = comma-separated field names' + #13#10 +
    '- TYPE = SINGLE, COMPOSITE, or UNIQUE' + #13#10 +
    '- REASON = brief explanation' + #13#10 +
    '- SQL = the CREATE INDEX statement' + #13#10 +
    '- IMPACT = HIGH, MEDIUM, or LOW' + #13#10 +
    #13#10 +
    'Do NOT include any other text, headers, or explanations. Only the pipe-delimited lines.';
end;

function TSimpleAutoIndex.ParseSuggestions(const aResponse: String): TArray<TIndexSuggestion>;
var
  LLines: TStringList;
  LLine: String;
  LParts: TStringList;
  LSuggestion: TIndexSuggestion;
  LResult: TList<TIndexSuggestion>;
  I: Integer;
begin
  LLines := nil;
  LParts := nil;
  LResult := nil;
  try
    LLines := TStringList.Create;
    LLines.Text := aResponse;

    LParts := TStringList.Create;
    LParts.StrictDelimiter := True;
    LParts.Delimiter := '|';

    LResult := TList<TIndexSuggestion>.Create;

    for I := 0 to LLines.Count - 1 do
    begin
      LLine := Trim(LLines[I]);
      if LLine = '' then
        Continue;

      LParts.DelimitedText := LLine;

      if LParts.Count < 6 then
        Continue;

      LSuggestion.TableName := Trim(LParts[0]);
      LSuggestion.FieldNames := Trim(LParts[1]);
      LSuggestion.IndexType := Trim(LParts[2]);
      LSuggestion.Reason := Trim(LParts[3]);
      LSuggestion.CreateSQL := Trim(LParts[4]);
      LSuggestion.EstimatedImpact := Trim(LParts[5]);

      if (LSuggestion.TableName <> '') and (LSuggestion.CreateSQL <> '') then
        LResult.Add(LSuggestion);
    end;

    Result := LResult.ToArray;
  finally
    FreeAndNil(LResult);
    FreeAndNil(LParts);
    FreeAndNil(LLines);
  end;
end;

function TSimpleAutoIndex.Analyze: TArray<TIndexSuggestion>;
var
  LPrompt: String;
  LResponse: String;
begin
  if FAIClient = nil then
    raise Exception.Create('TSimpleAutoIndex requires an AI client');

  if FQueryLogs.Count = 0 then
  begin
    SetLength(Result, 0);
    Exit;
  end;

  LPrompt := BuildPrompt;
  LResponse := FAIClient.Complete(LPrompt);
  Result := ParseSuggestions(LResponse);
end;

function TSimpleAutoIndex.AnalyzeAndExecute(aQuery: iSimpleQuery): Integer;
var
  LSuggestions: TArray<TIndexSuggestion>;
  LSuggestion: TIndexSuggestion;
  LUpperSQL: String;
  I: Integer;
begin
  Result := 0;

  if aQuery = nil then
    raise Exception.Create('TSimpleAutoIndex.AnalyzeAndExecute requires a query instance');

  LSuggestions := Analyze;

  for I := 0 to Length(LSuggestions) - 1 do
  begin
    LSuggestion := LSuggestions[I];

    if LSuggestion.CreateSQL = '' then
      Continue;

    LUpperSQL := UpperCase(Trim(LSuggestion.CreateSQL));
    if not LUpperSQL.StartsWith('CREATE') then
      Continue;

    if (Pos('DROP ', LUpperSQL) > 0) or (Pos('DELETE ', LUpperSQL) > 0) or
       (Pos('INSERT ', LUpperSQL) > 0) or (Pos('UPDATE ', LUpperSQL) > 0) then
      Continue;

    aQuery.SQL.Clear;
    aQuery.SQL.Add(LSuggestion.CreateSQL);
    try
      aQuery.ExecSQL;
      Inc(Result);
    except
      on E: Exception do
      begin
        // Index may already exist or be invalid - skip and continue
        Continue;
      end;
    end;
  end;
end;

end.

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
  System.Generics.Collections
  {$IFDEF MSWINDOWS}
  , Winapi.Windows
  {$ENDIF};

type
  TQueryOptimization = record
    OriginalSQL: String;
    OptimizedSQL: String;
    Suggestions: String;
    HasOptimization: Boolean;
  end;

  TSimpleQueryOptimizer = class
  private
    FAIClient: iSimpleAIClient;
    FEntityTypes: TList<PTypeInfo>;
    function BuildSchemaContext: String;
    function ParseResponse(const aOriginalSQL, aResponse: String): TQueryOptimization;
  public
    constructor Create(aAIClient: iSimpleAIClient);
    destructor Destroy; override;
    class function New(aAIClient: iSimpleAIClient): TSimpleQueryOptimizer;
    function RegisterEntity(aTypeInfo: PTypeInfo): TSimpleQueryOptimizer;
    function Optimize(const aSQL: String; aSQLType: TSQLType): TQueryOptimization;
  end;

  { Skill wrapper - pode ser adicionado ao DAO como skill }
  TSkillQueryOptimizer = class(TInterfacedObject, iSimpleSkill)
  private
    FOptimizer: TSimpleQueryOptimizer;
    FAIClient: iSimpleAIClient;
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

{ TSimpleQueryOptimizer }

constructor TSimpleQueryOptimizer.Create(aAIClient: iSimpleAIClient);
begin
  FAIClient := aAIClient;
  FEntityTypes := TList<PTypeInfo>.Create;
end;

destructor TSimpleQueryOptimizer.Destroy;
begin
  FreeAndNil(FEntityTypes);
  inherited;
end;

class function TSimpleQueryOptimizer.New(aAIClient: iSimpleAIClient): TSimpleQueryOptimizer;
begin
  Result := Self.Create(aAIClient);
end;

function TSimpleQueryOptimizer.RegisterEntity(aTypeInfo: PTypeInfo): TSimpleQueryOptimizer;
begin
  Result := Self;
  if aTypeInfo <> nil then
    FEntityTypes.Add(aTypeInfo);
end;

function TSimpleQueryOptimizer.BuildSchemaContext: String;
var
  LContext: TRttiContext;
  LTypeInfo: PTypeInfo;
  LType: TRttiType;
  LProp: TRttiProperty;
  LTableName: String;
  LTypeName: String;
  LFieldInfo: String;
  I: Integer;
begin
  Result := '';
  LContext := TRttiContext.Create;
  try
    for I := 0 to FEntityTypes.Count - 1 do
    begin
      LTypeInfo := FEntityTypes[I];
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

      for LProp in LType.GetProperties do
      begin
        if LProp.IsIgnore then
          Continue;

        case LProp.PropertyType.TypeKind of
          tkInteger, tkInt64:
            LTypeName := 'INTEGER';
          tkFloat:
            LTypeName := 'FLOAT';
          tkUString, tkString, tkLString, tkWString:
            LTypeName := 'VARCHAR';
        else
          LTypeName := 'VARCHAR';
        end;

        LFieldInfo := LProp.FieldName + ' ' + LTypeName;
        if LProp.EhChavePrimaria then
          LFieldInfo := LFieldInfo + ' PK';
        if LProp.EhChaveEstrangeira then
          LFieldInfo := LFieldInfo + ' FK';
        if LProp.IsAutoInc then
          LFieldInfo := LFieldInfo + ' AUTOINC';
        if LProp.IsNotNull then
          LFieldInfo := LFieldInfo + ' NOT NULL';

        Result := Result + LFieldInfo + ', ';
      end;

      Result := Result + ')';
    end;
  finally
    LContext.Free;
  end;
end;

function TSimpleQueryOptimizer.ParseResponse(const aOriginalSQL, aResponse: String): TQueryOptimization;
var
  LLines: TArray<String>;
  LLine: String;
  LTrimmed: String;
  LOptimizedSQL: String;
  LSuggestions: String;
  LInSuggestions: Boolean;
  I: Integer;
begin
  Result.OriginalSQL := aOriginalSQL;
  Result.OptimizedSQL := '';
  Result.Suggestions := '';
  Result.HasOptimization := False;

  LOptimizedSQL := '';
  LSuggestions := '';
  LInSuggestions := False;

  LLines := aResponse.Split([#13#10, #10]);
  for I := 0 to Length(LLines) - 1 do
  begin
    LLine := LLines[I];
    LTrimmed := Trim(LLine);

    if LTrimmed.StartsWith('OPTIMIZED_SQL:') then
    begin
      LOptimizedSQL := Trim(Copy(LTrimmed, 15, Length(LTrimmed)));
      LInSuggestions := False;
    end
    else if LTrimmed.StartsWith('SUGGESTIONS:') then
    begin
      LSuggestions := Trim(Copy(LTrimmed, 13, Length(LTrimmed)));
      LInSuggestions := True;
    end
    else if LInSuggestions and (LTrimmed <> '') then
    begin
      if LSuggestions <> '' then
        LSuggestions := LSuggestions + #13#10;
      LSuggestions := LSuggestions + LTrimmed;
    end
    else if (not LInSuggestions) and (LOptimizedSQL <> '') and (LTrimmed <> '') then
    begin
      LOptimizedSQL := LOptimizedSQL + ' ' + LTrimmed;
    end;
  end;

  Result.OptimizedSQL := Trim(LOptimizedSQL);
  Result.Suggestions := Trim(LSuggestions);
  Result.HasOptimization := (Result.OptimizedSQL <> '') and
    (Result.OptimizedSQL <> Result.OriginalSQL);
end;

function TSimpleQueryOptimizer.Optimize(const aSQL: String; aSQLType: TSQLType): TQueryOptimization;
var
  LPrompt: String;
  LResponse: String;
  LDBType: String;
begin
  if FAIClient = nil then
    raise Exception.Create('QueryOptimizer requires an AI client');

  case aSQLType of
    TSQLType.Firebird: LDBType := 'Firebird';
    TSQLType.MySQL:    LDBType := 'MySQL';
    TSQLType.SQLite:   LDBType := 'SQLite';
    TSQLType.Oracle:   LDBType := 'Oracle';
  else
    LDBType := 'SQL';
  end;

  LPrompt :=
    'You are a SQL optimization expert for ' + LDBType + ' databases.' + #13#10 +
    #13#10 +
    'Database schema:' + #13#10 +
    BuildSchemaContext + #13#10 +
    #13#10 +
    'Analyze the following SQL query and optimize it:' + #13#10 +
    aSQL + #13#10 +
    #13#10 +
    'Check for:' + #13#10 +
    '- N+1 query problems' + #13#10 +
    '- Missing indexes (suggest CREATE INDEX statements)' + #13#10 +
    '- Full table scans that could be avoided' + #13#10 +
    '- JOIN optimizations' + #13#10 +
    '- Subquery to JOIN conversion opportunities' + #13#10 +
    '- Proper use of WHERE clauses' + #13#10 +
    #13#10 +
    'Respond in EXACTLY this format:' + #13#10 +
    'OPTIMIZED_SQL: (the optimized SQL query, or the original if no optimization is needed)' + #13#10 +
    'SUGGESTIONS: (free text with optimization tips, index suggestions, and explanations)' + #13#10 +
    #13#10 +
    'If the SQL is already optimal, return the original SQL as OPTIMIZED_SQL and explain why it is optimal in SUGGESTIONS.';

  LResponse := FAIClient.Complete(LPrompt);

  Result := ParseResponse(aSQL, LResponse);
end;

{ TSkillQueryOptimizer }

constructor TSkillQueryOptimizer.Create(aAIClient: iSimpleAIClient);
begin
  FAIClient := aAIClient;
  FOptimizer := TSimpleQueryOptimizer.Create(aAIClient);
end;

destructor TSkillQueryOptimizer.Destroy;
begin
  FreeAndNil(FOptimizer);
  inherited;
end;

class function TSkillQueryOptimizer.New(aAIClient: iSimpleAIClient): iSimpleSkill;
begin
  Result := Self.Create(aAIClient);
end;

function TSkillQueryOptimizer.Execute(aEntity: TObject; aContext: iSimpleSkillContext): iSimpleSkill;
var
  LOptimization: TQueryOptimization;
  LSQL: String;
  LSQLType: TSQLType;
  LMsg: String;
begin
  Result := Self;
  if aContext = nil then
    Exit;
  if aContext.Query = nil then
    Exit;

  LSQL := Trim(aContext.Query.SQL.Text);
  if LSQL = '' then
    Exit;

  LSQLType := aContext.Query.SQLType;

  try
    LOptimization := FOptimizer.Optimize(LSQL, LSQLType);

    LMsg := '[Skill:QueryOptimizer] Analyzed: ' + LOptimization.OriginalSQL;
    if LOptimization.HasOptimization then
      LMsg := LMsg + #13#10 + '  Optimized SQL: ' + LOptimization.OptimizedSQL;
    if LOptimization.Suggestions <> '' then
      LMsg := LMsg + #13#10 + '  Suggestions: ' + LOptimization.Suggestions;

    if Assigned(aContext.Logger) then
      aContext.Logger.Log(LMsg, nil, 0)
    else
    begin
      {$IFDEF MSWINDOWS}
      OutputDebugString(PChar(LMsg));
      {$ENDIF}
      {$IFDEF CONSOLE}
      Writeln(LMsg);
      {$ENDIF}
    end;
  except
    on E: Exception do
    begin
      LMsg := '[Skill:QueryOptimizer] Error: ' + E.Message;
      if Assigned(aContext.Logger) then
        aContext.Logger.Log(LMsg, nil, 0)
      else
      begin
        {$IFDEF MSWINDOWS}
        OutputDebugString(PChar(LMsg));
        {$ENDIF}
        {$IFDEF CONSOLE}
        Writeln(LMsg);
        {$ENDIF}
      end;
    end;
  end;
end;

function TSkillQueryOptimizer.Name: String;
begin
  Result := 'query-optimizer';
end;

function TSkillQueryOptimizer.RunAt: TSkillRunAt;
begin
  Result := srBeforeInsert;
end;

function TSkillQueryOptimizer.RunMode: TSkillRunMode;
begin
  Result := srmNormal;
end;

end.

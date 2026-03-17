unit SimpleAgent;

interface

uses
  SimpleInterface,
  SimpleAttributes,
  SimpleRTTIHelper,
  SimpleTypes,
  SimpleSkill,
  System.Classes,
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  System.JSON,
  System.Generics.Collections;

type
  TAgentReaction = class
  private
    FEntityClass: TClass;
    FOperation: TAgentOperation;
    FCondition: TAgentCondition;
    FSkills: TList<iSimpleSkill>;
  public
    constructor Create(aEntityClass: TClass; aOperation: TAgentOperation);
    destructor Destroy; override;
    function Condition(aCondition: TAgentCondition): TAgentReaction;
    function Execute(aSkill: iSimpleSkill): TAgentReaction;
    function Matches(aEntity: TObject; aOperation: TAgentOperation): Boolean;
    procedure Run(aEntity: TObject; aContext: iSimpleSkillContext);
  end;

  TAgentResult = class(TInterfacedObject, iAgentResult)
  private
    FSummary: String;
    FStepsCount: Integer;
    FSuccess: Boolean;
  public
    constructor Create(const aSummary: String; aStepsCount: Integer; aSuccess: Boolean);
    destructor Destroy; override;
    class function New(const aSummary: String; aStepsCount: Integer; aSuccess: Boolean): iAgentResult;
    function Summary: String;
    function StepsCount: Integer;
    function Success: Boolean;
  end;

  TAgentPlan = class(TInterfacedObject, iAgentPlan)
  private
    FDescription: String;
    FSQL: String;
    FRisk: String;
    FStepsCount: Integer;
    FQuery: iSimpleQuery;
    FSteps: TStringList;
  public
    constructor Create(const aDescription, aSQL, aRisk: String; aStepsCount: Integer; aQuery: iSimpleQuery);
    destructor Destroy; override;
    function Description: String;
    function SQL: String;
    function Risk: String;
    function StepsCount: Integer;
    procedure Execute;
  end;

  TSimpleAgent = class(TInterfacedObject, iSimpleAgent)
  private
    FReactions: TObjectList<TAgentReaction>;
    FSkills: TList<iSimpleSkill>;
    FEntityTypes: TList<PTypeInfo>;
    FAIClient: iSimpleAIClient;
    FQuery: iSimpleQuery;
    FSafeMode: Boolean;
    function BuildAgentContext: String;
    function BuildSkillsList: String;
    function DetermineRisk(const aResponse: String): String;
  public
    constructor Create(aQuery: iSimpleQuery = nil; aAIClient: iSimpleAIClient = nil);
    destructor Destroy; override;
    class function New(aQuery: iSimpleQuery = nil; aAIClient: iSimpleAIClient = nil): TSimpleAgent;
    procedure Configure; virtual;
    function When(aEntityClass: TClass; aOperation: TAgentOperation): TAgentReaction;
    function RegisterEntity<T: class, constructor>: TSimpleAgent;
    function RegisterSkill(aSkill: iSimpleSkill): TSimpleAgent;
    function SafeMode(aValue: Boolean): TSimpleAgent;
    function Execute(const aObjective: String): iAgentResult;
    function Plan(const aObjective: String): iAgentPlan;
    procedure React(aEntity: TObject; aOperation: TAgentOperation);
  end;

implementation

{ TAgentReaction }

constructor TAgentReaction.Create(aEntityClass: TClass; aOperation: TAgentOperation);
begin
  FEntityClass := aEntityClass;
  FOperation := aOperation;
  FCondition := nil;
  FSkills := TList<iSimpleSkill>.Create;
end;

destructor TAgentReaction.Destroy;
begin
  FreeAndNil(FSkills);
  inherited;
end;

function TAgentReaction.Condition(aCondition: TAgentCondition): TAgentReaction;
begin
  Result := Self;
  FCondition := aCondition;
end;

function TAgentReaction.Execute(aSkill: iSimpleSkill): TAgentReaction;
begin
  Result := Self;
  FSkills.Add(aSkill);
end;

function TAgentReaction.Matches(aEntity: TObject; aOperation: TAgentOperation): Boolean;
begin
  Result := False;
  if aEntity = nil then
    Exit;
  if FOperation <> aOperation then
    Exit;
  if not aEntity.InheritsFrom(FEntityClass) then
    Exit;
  if Assigned(FCondition) then
    Result := FCondition(aEntity)
  else
    Result := True;
end;

procedure TAgentReaction.Run(aEntity: TObject; aContext: iSimpleSkillContext);
var
  LSkill: iSimpleSkill;
begin
  for LSkill in FSkills do
    LSkill.Execute(aEntity, aContext);
end;

{ TAgentResult }

constructor TAgentResult.Create(const aSummary: String; aStepsCount: Integer; aSuccess: Boolean);
begin
  FSummary := aSummary;
  FStepsCount := aStepsCount;
  FSuccess := aSuccess;
end;

destructor TAgentResult.Destroy;
begin
  inherited;
end;

class function TAgentResult.New(const aSummary: String; aStepsCount: Integer; aSuccess: Boolean): iAgentResult;
begin
  Result := Self.Create(aSummary, aStepsCount, aSuccess);
end;

function TAgentResult.Summary: String;
begin
  Result := FSummary;
end;

function TAgentResult.StepsCount: Integer;
begin
  Result := FStepsCount;
end;

function TAgentResult.Success: Boolean;
begin
  Result := FSuccess;
end;

{ TAgentPlan }

constructor TAgentPlan.Create(const aDescription, aSQL, aRisk: String; aStepsCount: Integer; aQuery: iSimpleQuery);
begin
  FDescription := aDescription;
  FSQL := aSQL;
  FRisk := aRisk;
  FStepsCount := aStepsCount;
  FQuery := aQuery;
  FSteps := TStringList.Create;
end;

destructor TAgentPlan.Destroy;
begin
  FreeAndNil(FSteps);
  inherited;
end;

function TAgentPlan.Description: String;
begin
  Result := FDescription;
end;

function TAgentPlan.SQL: String;
begin
  Result := FSQL;
end;

function TAgentPlan.Risk: String;
begin
  Result := FRisk;
end;

function TAgentPlan.StepsCount: Integer;
begin
  Result := FStepsCount;
end;

procedure TAgentPlan.Execute;
var
  LUpperSQL: String;
begin
  if FSQL = '' then
    Exit;

  LUpperSQL := UpperCase(Trim(FSQL));

  if not LUpperSQL.StartsWith('SELECT') then
  begin
    if Pos(';', FSQL) > 0 then
      raise Exception.Create('Agent plan contains multiple SQL statements - blocked for safety');
  end;

  if FQuery <> nil then
  begin
    FQuery.SQL.Clear;
    FQuery.SQL.Add(FSQL);
    FQuery.ExecSQL;
  end;
end;

{ TSimpleAgent }

constructor TSimpleAgent.Create(aQuery: iSimpleQuery; aAIClient: iSimpleAIClient);
begin
  FReactions := TObjectList<TAgentReaction>.Create(True);
  FSkills := TList<iSimpleSkill>.Create;
  FEntityTypes := TList<PTypeInfo>.Create;
  FQuery := aQuery;
  FAIClient := aAIClient;
  FSafeMode := True;
  Configure;
end;

destructor TSimpleAgent.Destroy;
begin
  FreeAndNil(FReactions);
  FreeAndNil(FSkills);
  FreeAndNil(FEntityTypes);
  inherited;
end;

class function TSimpleAgent.New(aQuery: iSimpleQuery; aAIClient: iSimpleAIClient): TSimpleAgent;
begin
  Result := Self.Create(aQuery, aAIClient);
end;

procedure TSimpleAgent.Configure;
begin
  // Override in subclasses to add reactive rules
end;

function TSimpleAgent.When(aEntityClass: TClass; aOperation: TAgentOperation): TAgentReaction;
var
  LReaction: TAgentReaction;
begin
  LReaction := TAgentReaction.Create(aEntityClass, aOperation);
  FReactions.Add(LReaction);
  Result := LReaction;
end;

function TSimpleAgent.RegisterEntity<T>: TSimpleAgent;
begin
  Result := Self;
  FEntityTypes.Add(TypeInfo(T));
end;

function TSimpleAgent.RegisterSkill(aSkill: iSimpleSkill): TSimpleAgent;
begin
  Result := Self;
  FSkills.Add(aSkill);
end;

function TSimpleAgent.SafeMode(aValue: Boolean): TSimpleAgent;
begin
  Result := Self;
  FSafeMode := aValue;
end;

procedure TSimpleAgent.React(aEntity: TObject; aOperation: TAgentOperation);
var
  LReaction: TAgentReaction;
  LContext: iSimpleSkillContext;
  LEntityName: String;
  LOpStr: String;
begin
  if aEntity = nil then
    Exit;

  LEntityName := aEntity.ClassName;

  case aOperation of
    aoAfterInsert: LOpStr := 'INSERT';
    aoAfterUpdate: LOpStr := 'UPDATE';
    aoAfterDelete: LOpStr := 'DELETE';
  end;

  LContext := TSimpleSkillContext.New(FQuery, FAIClient, nil, LEntityName, LOpStr);

  for LReaction in FReactions do
  begin
    if LReaction.Matches(aEntity, aOperation) then
      LReaction.Run(aEntity, LContext);
  end;
end;

function TSimpleAgent.BuildAgentContext: String;
var
  LContext: TRttiContext;
  LTypeInfo: PTypeInfo;
  LType: TRttiType;
  LProp: TRttiProperty;
  LTableName: String;
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
      Result := Result + 'Tabela: ' + LTableName + ' (Colunas: ';

      for LProp in LType.GetProperties do
      begin
        if LProp.IsIgnore then
          Continue;
        Result := Result + LProp.FieldName + ', ';
      end;

      Result := Result + ')';
    end;
  finally
    LContext.Free;
  end;
end;

function TSimpleAgent.BuildSkillsList: String;
var
  LSkill: iSimpleSkill;
begin
  Result := '';
  for LSkill in FSkills do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + LSkill.Name;
  end;
end;

function TSimpleAgent.DetermineRisk(const aResponse: String): String;
var
  LUpper: String;
begin
  LUpper := UpperCase(aResponse);
  if (Pos('DELETE ', LUpper) > 0) or (Pos('DROP ', LUpper) > 0) or (Pos('TRUNCATE ', LUpper) > 0) then
    Result := 'HIGH'
  else if (Pos('UPDATE ', LUpper) > 0) or (Pos('INSERT ', LUpper) > 0) then
    Result := 'MEDIUM'
  else
    Result := 'LOW';
end;

function TSimpleAgent.Plan(const aObjective: String): iAgentPlan;
var
  LPrompt: String;
  LResponse: String;
  LDescription: String;
  LSQL: String;
  LRisk: String;
  LSteps: Integer;
  LLines: TArray<String>;
  LLine: String;
begin
  if FAIClient = nil then
    raise Exception.Create('Agent proactive mode requires an AI client');

  LPrompt := 'Voce e um assistente de banco de dados.' + #13#10 +
    #13#10 +
    'Esquema do banco:' + #13#10 +
    BuildAgentContext + #13#10 +
    #13#10 +
    'Skills disponiveis: ' + BuildSkillsList + #13#10 +
    #13#10 +
    'Objetivo: ' + aObjective + #13#10 +
    #13#10 +
    'Gere um plano com:' + #13#10 +
    'DESCRICAO: (1 frase descrevendo o que sera feito)' + #13#10 +
    'SQL: (o SQL necessario, apenas SELECT para consulta)' + #13#10 +
    'STEPS: (numero de passos)' + #13#10 +
    'Responda APENAS neste formato, sem explicacoes adicionais.';

  LResponse := FAIClient.Complete(LPrompt);

  LDescription := '';
  LSQL := '';
  LSteps := 1;

  LLines := LResponse.Split([#13#10, #10]);
  for LLine in LLines do
  begin
    if LLine.StartsWith('DESCRICAO:') then
      LDescription := Trim(Copy(LLine, 11, Length(LLine)))
    else if LLine.StartsWith('SQL:') then
      LSQL := Trim(Copy(LLine, 5, Length(LLine)))
    else if LLine.StartsWith('STEPS:') then
      TryStrToInt(Trim(Copy(LLine, 7, Length(LLine))), LSteps);
  end;

  if LDescription = '' then
    LDescription := LResponse;

  LRisk := DetermineRisk(LResponse);

  Result := TAgentPlan.Create(LDescription, LSQL, LRisk, LSteps, FQuery);
end;

function TSimpleAgent.Execute(const aObjective: String): iAgentResult;
var
  LPlan: iAgentPlan;
begin
  if FSafeMode then
    raise Exception.Create('SafeMode is enabled. Use Plan() to inspect before Execute().');

  LPlan := Plan(aObjective);

  try
    LPlan.Execute;
    Result := TAgentResult.New(LPlan.Description, LPlan.StepsCount, True);
  except
    on E: Exception do
      Result := TAgentResult.New('Failed: ' + E.Message, 0, False);
  end;
end;

end.

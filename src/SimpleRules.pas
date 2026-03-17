unit SimpleRules;

interface

uses
  SimpleInterface,
  SimpleAttributes,
  SimpleRTTIHelper,
  SimpleTypes,
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  System.Variants;

type
  ESimpleRuleViolation = class(Exception);

  TSimpleRuleEngine = class
  private
    FAIClient: iSimpleAIClient;
    function EvaluateExpression(aObj: TObject; const aExpression: String; aContext: TRttiContext): Boolean;
    function GetPropertyValue(aObj: TObject; const aPropName: String; aContext: TRttiContext): Variant;
    function ParseSimpleExpression(const aLeft: String; const aOperator: String; const aRight: String; aObj: TObject; aContext: TRttiContext): Boolean;
    function TokenizeExpression(const aExpression: String; var aLeft, aOperator, aRight: String): Boolean;
    procedure ProcessRule(aObj: TObject; aAttr: Rule; aContext: TRttiContext);
    procedure ProcessAIRule(aObj: TObject; aAttr: AIRule; aContext: TRttiContext);
    function BuildEntityContext(aObj: TObject; aContext: TRttiContext): String;
  public
    constructor Create(aAIClient: iSimpleAIClient = nil);
    destructor Destroy; override;
    class function New(aAIClient: iSimpleAIClient = nil): TSimpleRuleEngine;
    procedure Evaluate(aObj: TObject; aAction: TRuleAction);
  end;

implementation

{ TSimpleRuleEngine }

constructor TSimpleRuleEngine.Create(aAIClient: iSimpleAIClient);
begin
  FAIClient := aAIClient;
end;

destructor TSimpleRuleEngine.Destroy;
begin
  inherited;
end;

class function TSimpleRuleEngine.New(aAIClient: iSimpleAIClient): TSimpleRuleEngine;
begin
  Result := Self.Create(aAIClient);
end;

procedure TSimpleRuleEngine.Evaluate(aObj: TObject; aAction: TRuleAction);
var
  LContext: TRttiContext;
  LType: TRttiType;
  LAttr: TCustomAttribute;
begin
  if aObj = nil then
    Exit;

  LContext := TRttiContext.Create;
  try
    LType := LContext.GetType(aObj.ClassType);

    for LAttr in LType.GetAttributes do
    begin
      if (LAttr is Rule) and (Rule(LAttr).Action = aAction) then
        ProcessRule(aObj, Rule(LAttr), LContext)
      else if (LAttr is AIRule) and (AIRule(LAttr).Action = aAction) then
        ProcessAIRule(aObj, AIRule(LAttr), LContext);
    end;
  finally
    LContext.Free;
  end;
end;

procedure TSimpleRuleEngine.ProcessRule(aObj: TObject; aAttr: Rule; aContext: TRttiContext);
begin
  if not EvaluateExpression(aObj, aAttr.Expression, aContext) then
  begin
    if aAttr.Message <> '' then
      raise ESimpleRuleViolation.Create(aAttr.Message)
    else
      raise ESimpleRuleViolation.Create('Rule violation: ' + aAttr.Expression);
  end;
end;

procedure TSimpleRuleEngine.ProcessAIRule(aObj: TObject; aAttr: AIRule; aContext: TRttiContext);
var
  LPrompt: String;
  LEntityContext: String;
  LResponse: String;
begin
  if FAIClient = nil then
    raise ESimpleRuleViolation.Create('AIRule requires an AI client to be configured');

  LEntityContext := BuildEntityContext(aObj, aContext);

  LPrompt := 'Voce e um validador de regras de negocio.' + #13#10 +
    #13#10 +
    'Entidade:' + #13#10 +
    LEntityContext + #13#10 +
    #13#10 +
    'Regra: ' + aAttr.Description + #13#10 +
    #13#10 +
    'Avalie se os dados da entidade atendem a regra.' + #13#10 +
    'Responda APENAS "VALIDO" se atende, ou "INVALIDO: motivo" se nao atende.';

  LResponse := FAIClient.Complete(LPrompt);
  LResponse := Trim(LResponse);

  if not LResponse.StartsWith('VALIDO') then
  begin
    if LResponse.StartsWith('INVALIDO:') then
      raise ESimpleRuleViolation.Create(Copy(LResponse, 11, Length(LResponse)))
    else
      raise ESimpleRuleViolation.Create('AIRule failed: ' + aAttr.Description + ' - ' + LResponse);
  end;
end;

function TSimpleRuleEngine.BuildEntityContext(aObj: TObject; aContext: TRttiContext): String;
var
  LType: TRttiType;
  LProp: TRttiProperty;
  LValue: TValue;
begin
  Result := '';
  LType := aContext.GetType(aObj.ClassType);
  for LProp in LType.GetProperties do
  begin
    if LProp.IsIgnore then
      Continue;
    LValue := LProp.GetValue(aObj);
    if Result <> '' then
      Result := Result + #13#10;
    Result := Result + LProp.Name + ' = ' + LValue.ToString;
  end;
end;

function TSimpleRuleEngine.TokenizeExpression(const aExpression: String; var aLeft, aOperator, aRight: String): Boolean;
var
  LOperators: array[0..5] of String;
  LOp: String;
  LPos: Integer;
  I: Integer;
begin
  Result := False;
  LOperators[0] := '<>';
  LOperators[1] := '>=';
  LOperators[2] := '<=';
  LOperators[3] := '>';
  LOperators[4] := '<';
  LOperators[5] := '=';

  for I := 0 to High(LOperators) do
  begin
    LOp := LOperators[I];
    LPos := Pos(LOp, aExpression);
    if LPos > 0 then
    begin
      aLeft := Trim(Copy(aExpression, 1, LPos - 1));
      aOperator := LOp;
      aRight := Trim(Copy(aExpression, LPos + Length(LOp), Length(aExpression)));
      Result := True;
      Exit;
    end;
  end;
end;

function TSimpleRuleEngine.EvaluateExpression(aObj: TObject; const aExpression: String; aContext: TRttiContext): Boolean;
var
  LLeft, LOperator, LRight: String;
begin
  if not TokenizeExpression(aExpression, LLeft, LOperator, LRight) then
    raise ESimpleRuleViolation.Create('Invalid rule expression: ' + aExpression);

  Result := ParseSimpleExpression(LLeft, LOperator, LRight, aObj, aContext);
end;

function TSimpleRuleEngine.GetPropertyValue(aObj: TObject; const aPropName: String; aContext: TRttiContext): Variant;
var
  LType: TRttiType;
  LProp: TRttiProperty;
  LValue: TValue;
begin
  LType := aContext.GetType(aObj.ClassType);
  LProp := LType.GetProperty(aPropName);
  if LProp = nil then
    raise ESimpleRuleViolation.Create('Property not found: ' + aPropName);

  LValue := LProp.GetValue(aObj);
  case LValue.Kind of
    tkInteger:
      Result := LValue.AsInteger;
    tkInt64:
      Result := LValue.AsInt64;
    tkFloat:
      Result := LValue.AsExtended;
    tkUString, tkString, tkLString, tkWString:
      Result := LValue.AsString;
    tkEnumeration:
    begin
      if LValue.TypeInfo = TypeInfo(Boolean) then
        Result := LValue.AsBoolean
      else
        Result := LValue.AsOrdinal;
    end;
  else
    Result := LValue.ToString;
  end;
end;

function TSimpleRuleEngine.ParseSimpleExpression(const aLeft: String; const aOperator: String; const aRight: String; aObj: TObject; aContext: TRttiContext): Boolean;
var
  LLeftValue: Variant;
  LRightValue: Variant;
  LRightStr: String;
  LFloat: Double;
begin
  LLeftValue := GetPropertyValue(aObj, aLeft, aContext);

  LRightStr := aRight;

  if (Length(LRightStr) >= 2) and (LRightStr[1] = '''') and (LRightStr[Length(LRightStr)] = '''') then
    LRightValue := Copy(LRightStr, 2, Length(LRightStr) - 2)
  else
  begin
    if TryStrToFloat(LRightStr, LFloat) then
      LRightValue := LFloat
    else
      try
        LRightValue := GetPropertyValue(aObj, LRightStr, aContext);
      except
        LRightValue := LRightStr;
      end;
  end;

  if aOperator = '=' then
    Result := LLeftValue = LRightValue
  else if aOperator = '<>' then
    Result := LLeftValue <> LRightValue
  else if aOperator = '>' then
    Result := LLeftValue > LRightValue
  else if aOperator = '<' then
    Result := LLeftValue < LRightValue
  else if aOperator = '>=' then
    Result := LLeftValue >= LRightValue
  else if aOperator = '<=' then
    Result := LLeftValue <= LRightValue
  else
    raise ESimpleRuleViolation.Create('Unknown operator: ' + aOperator);
end;

end.

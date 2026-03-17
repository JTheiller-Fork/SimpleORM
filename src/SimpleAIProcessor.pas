unit SimpleAIProcessor;

interface

uses
  SimpleInterface,
  SimpleAttributes,
  SimpleAIAttributes,
  SimpleRTTIHelper,
  System.SysUtils,
  System.Rtti,
  System.TypInfo;

type
  ESimpleAIValidation = class(Exception);

  TSimpleAIProcessor = class
  private
    FAIClient: iSimpleAIClient;
    function GetPropertyValueAsString(aObj: TObject; aProp: TRttiProperty): String;
    function ResolveTemplate(aObj: TObject; const aTemplate: String; aContext: TRttiContext): String;
    procedure ProcessAIGenerated(aObj: TObject; aProp: TRttiProperty; aAttr: AIGenerated; aContext: TRttiContext);
    procedure ProcessAISummarize(aObj: TObject; aProp: TRttiProperty; aAttr: AISummarize; aContext: TRttiContext);
    procedure ProcessAITranslate(aObj: TObject; aProp: TRttiProperty; aAttr: AITranslate; aContext: TRttiContext);
    procedure ProcessAIClassify(aObj: TObject; aProp: TRttiProperty; aAttr: AIClassify; aContext: TRttiContext);
    procedure ProcessAIValidate(aObj: TObject; aProp: TRttiProperty; aAttr: AIValidate; aContext: TRttiContext);
  public
    constructor Create(aAIClient: iSimpleAIClient);
    destructor Destroy; override;
    class function New(aAIClient: iSimpleAIClient): TSimpleAIProcessor;
    procedure Process(aObj: TObject);
  end;

implementation

{ TSimpleAIProcessor }

constructor TSimpleAIProcessor.Create(aAIClient: iSimpleAIClient);
begin
  FAIClient := aAIClient;
end;

destructor TSimpleAIProcessor.Destroy;
begin
  inherited;
end;

class function TSimpleAIProcessor.New(aAIClient: iSimpleAIClient): TSimpleAIProcessor;
begin
  Result := Self.Create(aAIClient);
end;

function TSimpleAIProcessor.GetPropertyValueAsString(aObj: TObject; aProp: TRttiProperty): String;
var
  LValue: TValue;
begin
  LValue := aProp.GetValue(aObj);
  if LValue.IsEmpty then
    Result := ''
  else
    Result := LValue.ToString;
end;

function TSimpleAIProcessor.ResolveTemplate(aObj: TObject; const aTemplate: String; aContext: TRttiContext): String;
var
  LType: TRttiType;
  LProp: TRttiProperty;
  LPlaceholder: String;
  LValue: String;
begin
  Result := aTemplate;
  LType := aContext.GetType(aObj.ClassType);
  for LProp in LType.GetProperties do
  begin
    LPlaceholder := '{' + LProp.Name + '}';
    if Pos(LPlaceholder, Result) > 0 then
    begin
      LValue := GetPropertyValueAsString(aObj, LProp);
      Result := StringReplace(Result, LPlaceholder, LValue, [rfReplaceAll]);
    end;
  end;
end;

procedure TSimpleAIProcessor.Process(aObj: TObject);
var
  LContext: TRttiContext;
  LType: TRttiType;
  LProp: TRttiProperty;
  LAttr: TCustomAttribute;
begin
  if aObj = nil then
    Exit;

  LContext := TRttiContext.Create;
  try
    LType := LContext.GetType(aObj.ClassType);
    for LProp in LType.GetProperties do
    begin
      if not LProp.HasAIAttribute then
        Continue;

      for LAttr in LProp.GetAttributes do
      begin
        if LAttr is AIGenerated then
          ProcessAIGenerated(aObj, LProp, AIGenerated(LAttr), LContext)
        else if LAttr is AISummarize then
          ProcessAISummarize(aObj, LProp, AISummarize(LAttr), LContext)
        else if LAttr is AITranslate then
          ProcessAITranslate(aObj, LProp, AITranslate(LAttr), LContext)
        else if LAttr is AIClassify then
          ProcessAIClassify(aObj, LProp, AIClassify(LAttr), LContext)
        else if LAttr is AIValidate then
          ProcessAIValidate(aObj, LProp, AIValidate(LAttr), LContext);
      end;
    end;
  finally
    LContext.Free;
  end;
end;

procedure TSimpleAIProcessor.ProcessAIGenerated(aObj: TObject; aProp: TRttiProperty; aAttr: AIGenerated; aContext: TRttiContext);
var
  LPrompt: String;
  LResponse: String;
begin
  LPrompt := ResolveTemplate(aObj, aAttr.PromptTemplate, aContext);
  LResponse := FAIClient.Complete(LPrompt);
  aProp.SetValue(aObj, Trim(LResponse));
end;

procedure TSimpleAIProcessor.ProcessAISummarize(aObj: TObject; aProp: TRttiProperty; aAttr: AISummarize; aContext: TRttiContext);
var
  LType: TRttiType;
  LSourceProp: TRttiProperty;
  LSourceValue: String;
  LPrompt: String;
  LResponse: String;
begin
  LType := aContext.GetType(aObj.ClassType);
  LSourceProp := LType.GetProperty(aAttr.SourceProperty);
  if LSourceProp = nil then
    raise Exception.CreateFmt('Source property "%s" not found for AISummarize', [aAttr.SourceProperty]);

  LSourceValue := GetPropertyValueAsString(aObj, LSourceProp);
  if LSourceValue = '' then
    Exit;

  LPrompt := 'Resuma o seguinte texto de forma concisa';
  if aAttr.MaxLength > 0 then
    LPrompt := LPrompt + ' (maximo ' + IntToStr(aAttr.MaxLength) + ' caracteres)';
  LPrompt := LPrompt + ':' + #13#10 + #13#10 + LSourceValue + #13#10 + #13#10 +
    'Retorne APENAS o resumo, sem explicacoes adicionais.';

  LResponse := FAIClient.Complete(LPrompt);
  LResponse := Trim(LResponse);
  if (aAttr.MaxLength > 0) and (Length(LResponse) > aAttr.MaxLength) then
    LResponse := Copy(LResponse, 1, aAttr.MaxLength);
  aProp.SetValue(aObj, LResponse);
end;

procedure TSimpleAIProcessor.ProcessAITranslate(aObj: TObject; aProp: TRttiProperty; aAttr: AITranslate; aContext: TRttiContext);
var
  LType: TRttiType;
  LSourceProp: TRttiProperty;
  LSourceValue: String;
  LPrompt: String;
  LResponse: String;
begin
  LType := aContext.GetType(aObj.ClassType);
  LSourceProp := LType.GetProperty(aAttr.SourceProperty);
  if LSourceProp = nil then
    raise Exception.CreateFmt('Source property "%s" not found for AITranslate', [aAttr.SourceProperty]);

  LSourceValue := GetPropertyValueAsString(aObj, LSourceProp);
  if LSourceValue = '' then
    Exit;

  LPrompt := 'Traduza o seguinte texto para ' + aAttr.TargetLanguage + ':' + #13#10 + #13#10 +
    LSourceValue + #13#10 + #13#10 +
    'Retorne APENAS a traducao, sem explicacoes adicionais.';

  LResponse := FAIClient.Complete(LPrompt);
  aProp.SetValue(aObj, Trim(LResponse));
end;

procedure TSimpleAIProcessor.ProcessAIClassify(aObj: TObject; aProp: TRttiProperty; aAttr: AIClassify; aContext: TRttiContext);
var
  LType: TRttiType;
  LSourceProp: TRttiProperty;
  LSourceValue: String;
  LPrompt: String;
  LResponse: String;
begin
  LType := aContext.GetType(aObj.ClassType);
  LSourceProp := LType.GetProperty(aAttr.SourceProperty);
  if LSourceProp = nil then
    raise Exception.CreateFmt('Source property "%s" not found for AIClassify', [aAttr.SourceProperty]);

  LSourceValue := GetPropertyValueAsString(aObj, LSourceProp);
  if LSourceValue = '' then
    Exit;

  LPrompt := 'Classifique o seguinte texto em UMA das categorias: ' + aAttr.Categories + #13#10 + #13#10 +
    'Texto: ' + LSourceValue + #13#10 + #13#10 +
    'Retorne APENAS o nome da categoria, sem explicacoes.';

  LResponse := FAIClient.Complete(LPrompt);
  aProp.SetValue(aObj, Trim(LResponse));
end;

procedure TSimpleAIProcessor.ProcessAIValidate(aObj: TObject; aProp: TRttiProperty; aAttr: AIValidate; aContext: TRttiContext);
var
  LValue: String;
  LPrompt: String;
  LResponse: String;
  LErrorMsg: String;
begin
  LValue := GetPropertyValueAsString(aObj, aProp);
  if LValue = '' then
    Exit;

  LPrompt := 'Valide o seguinte valor contra a regra descrita.' + #13#10 +
    'Regra: ' + aAttr.Rule + #13#10 +
    'Valor: ' + LValue + #13#10 + #13#10 +
    'Responda APENAS "VALIDO" se o valor atende a regra, ou "INVALIDO: motivo" se nao atende.';

  LResponse := FAIClient.Complete(LPrompt);
  LResponse := Trim(LResponse);

  if not LResponse.StartsWith('VALIDO') then
  begin
    if aAttr.ErrorMessage <> '' then
      LErrorMsg := aAttr.ErrorMessage
    else
      LErrorMsg := 'AI validation failed for ' + aProp.Name + ': ' + LResponse;
    raise ESimpleAIValidation.Create(LErrorMsg);
  end;
end;

end.

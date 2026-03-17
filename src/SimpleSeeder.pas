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
  ESimpleSeeder = class(Exception);

  TSimpleSeeder = class
  private
    FAIClient: iSimpleAIClient;
    function BuildSchemaDescription(aTypeInfo: PTypeInfo): String;
    function BuildPrompt(const aSchemaDescription: String; aCount: Integer): String;
    function CleanResponse(const aResponse: String): String;
  public
    constructor Create(aAIClient: iSimpleAIClient);
    destructor Destroy; override;
    class function New(aAIClient: iSimpleAIClient): TSimpleSeeder;
    function Seed<T: class, constructor>(aCount: Integer): TObjectList<T>;
    function SeedAndInsert<T: class, constructor>(aDAO: iSimpleDAO<T>; aCount: Integer): Integer;
  end;

implementation

{ TSimpleSeeder }

constructor TSimpleSeeder.Create(aAIClient: iSimpleAIClient);
begin
  if aAIClient = nil then
    raise ESimpleSeeder.Create('TSimpleSeeder requires a valid iSimpleAIClient instance');
  FAIClient := aAIClient;
end;

destructor TSimpleSeeder.Destroy;
begin
  inherited;
end;

class function TSimpleSeeder.New(aAIClient: iSimpleAIClient): TSimpleSeeder;
begin
  Result := Self.Create(aAIClient);
end;

function TSimpleSeeder.BuildSchemaDescription(aTypeInfo: PTypeInfo): String;
var
  LContext: TRttiContext;
  LType: TRttiType;
  LProp: TRttiProperty;
  LTableName: String;
  LFieldName: String;
  LTypeName: String;
  LFlags: String;
  LFormatAttr: SimpleAttributes.Format;
  LMinValueAttr: MinValue;
  LMaxValueAttr: MaxValue;
begin
  Result := '';
  LContext := TRttiContext.Create;
  try
    LType := LContext.GetType(aTypeInfo);
    if LType = nil then
      raise ESimpleSeeder.CreateFmt('Cannot get RTTI type for %s', [String(aTypeInfo.Name)]);

    if LType.Tem<Tabela> then
      LTableName := LType.GetAttribute<Tabela>.Name
    else
      LTableName := UpperCase(Copy(LType.Name, 2, Length(LType.Name)));

    Result := 'Entity: ' + LTableName + sLineBreak;
    Result := Result + 'Fields:' + sLineBreak;

    for LProp in LType.GetProperties do
    begin
      if LProp.IsIgnore then
        Continue;

      if not LProp.EhCampo then
        Continue;

      LFieldName := LProp.FieldName;
      LFlags := '';

      case LProp.PropertyType.TypeKind of
        tkInteger, tkInt64:
          LTypeName := 'INTEGER';
        tkFloat:
        begin
          if LProp.PropertyType.Handle = TypeInfo(TDateTime) then
            LTypeName := 'DATE'
          else
            LTypeName := 'FLOAT';
        end;
        tkUString, tkString, tkLString, tkWString:
          LTypeName := 'VARCHAR';
        tkEnumeration:
        begin
          if LProp.PropertyType.Handle = TypeInfo(Boolean) then
            LTypeName := 'BOOLEAN'
          else
            LTypeName := 'VARCHAR';
        end;
      else
        LTypeName := 'VARCHAR';
      end;

      if LProp.EhChavePrimaria then
        LFlags := LFlags + ', PK';

      if LProp.IsAutoInc then
        LFlags := LFlags + ', AutoInc (SKIP THIS FIELD)';

      if LProp.IsNotNull then
        LFlags := LFlags + ', NotNull';

      if LProp.IsEmail then
        LFlags := LFlags + ', Email (generate valid email addresses)';

      if LProp.IsCPF then
        LFlags := LFlags + ', CPF (generate valid Brazilian CPF numbers, 11 digits)';

      if LProp.IsCNPJ then
        LFlags := LFlags + ', CNPJ (generate valid Brazilian CNPJ numbers, 14 digits)';

      if LProp.HasMinValue then
      begin
        LMinValueAttr := LProp.GetAttribute<MinValue>;
        if LMinValueAttr <> nil then
          LFlags := LFlags + ', MinValue=' + FloatToStr(LMinValueAttr.Value);
      end;

      if LProp.HasMaxValue then
      begin
        LMaxValueAttr := LProp.GetAttribute<MaxValue>;
        if LMaxValueAttr <> nil then
          LFlags := LFlags + ', MaxValue=' + FloatToStr(LMaxValueAttr.Value);
      end;

      if LProp.HasFormat then
      begin
        LFormatAttr := LProp.GetAttribute<SimpleAttributes.Format>;
        if LFormatAttr <> nil then
        begin
          if LFormatAttr.MaxSize > 0 then
            LFlags := LFlags + ', MaxSize=' + IntToStr(LFormatAttr.MaxSize);
          if LFormatAttr.MinSize > 0 then
            LFlags := LFlags + ', MinSize=' + IntToStr(LFormatAttr.MinSize);
        end;
      end;

      Result := Result + '  - ' + LFieldName + ' (' + LTypeName + LFlags + ')' + sLineBreak;
    end;
  finally
    LContext.Free;
  end;
end;

function TSimpleSeeder.BuildPrompt(const aSchemaDescription: String; aCount: Integer): String;
begin
  Result :=
    'Voce e um gerador de dados de teste realistas para um banco de dados brasileiro.' + sLineBreak +
    sLineBreak +
    'Gere ' + IntToStr(aCount) + ' registros realistas para a seguinte entidade:' + sLineBreak +
    sLineBreak +
    aSchemaDescription + sLineBreak +
    'Regras:' + sLineBreak +
    '- NAO inclua campos marcados como AutoInc (SKIP THIS FIELD) no JSON' + sLineBreak +
    '- Use nomes brasileiros realistas para campos de texto (nomes, cidades, etc.)' + sLineBreak +
    '- Gere emails validos para campos marcados como Email' + sLineBreak +
    '- Respeite os limites de MinValue e MaxValue' + sLineBreak +
    '- Respeite MaxSize para comprimento de strings' + sLineBreak +
    '- Campos NotNull DEVEM ter valor (nao vazio, nao zero)' + sLineBreak +
    '- Campos DATE devem estar no formato ISO8601 (ex: 2025-01-15T10:30:00)' + sLineBreak +
    '- Use os nomes dos campos EXATAMENTE como listados no schema como chaves JSON' + sLineBreak +
    sLineBreak +
    'Retorne APENAS um JSON array valido. Sem markdown, sem explicacao, sem texto adicional.' + sLineBreak +
    'Exemplo de formato esperado: [{"CAMPO1": "valor1", "CAMPO2": 123}, ...]';
end;

function TSimpleSeeder.CleanResponse(const aResponse: String): String;
var
  LResult: String;
  LStart: Integer;
  LEnd: Integer;
begin
  LResult := Trim(aResponse);

  if LResult.StartsWith('```') then
  begin
    LStart := Pos(sLineBreak, LResult);
    if LStart > 0 then
      LResult := Copy(LResult, LStart + Length(sLineBreak), Length(LResult))
    else
      LResult := Copy(LResult, 4, Length(LResult));

    if LResult.EndsWith('```') then
      LResult := Copy(LResult, 1, Length(LResult) - 3);

    LResult := Trim(LResult);
  end;

  LStart := Pos('[', LResult);
  LEnd := Length(LResult);
  while (LEnd > 0) and (LResult[LEnd] <> ']') do
    Dec(LEnd);

  if (LStart > 0) and (LEnd > LStart) then
    LResult := Copy(LResult, LStart, LEnd - LStart + 1)
  else
    raise ESimpleSeeder.Create('AI response does not contain a valid JSON array');

  Result := LResult;
end;

function TSimpleSeeder.Seed<T>(aCount: Integer): TObjectList<T>;
var
  LSchemaDesc: String;
  LPrompt: String;
  LResponse: String;
  LCleanJSON: String;
  LJSONValue: TJSONValue;
  LJSONArray: TJSONArray;
begin
  if aCount <= 0 then
    raise ESimpleSeeder.Create('Seed count must be greater than zero');

  LSchemaDesc := BuildSchemaDescription(TypeInfo(T));
  LPrompt := BuildPrompt(LSchemaDesc, aCount);

  LResponse := FAIClient.Complete(LPrompt);

  LCleanJSON := CleanResponse(LResponse);

  LJSONValue := TJSONObject.ParseJSONValue(LCleanJSON);
  if LJSONValue = nil then
    raise ESimpleSeeder.Create('Failed to parse AI response as JSON');

  try
    if not (LJSONValue is TJSONArray) then
      raise ESimpleSeeder.Create('AI response is not a JSON array');

    LJSONArray := LJSONValue as TJSONArray;

    if LJSONArray.Count = 0 then
      raise ESimpleSeeder.Create('AI returned an empty JSON array');

    Result := TSimpleSerializer.JSONArrayToEntityList<T>(LJSONArray);
  finally
    FreeAndNil(LJSONValue);
  end;
end;

function TSimpleSeeder.SeedAndInsert<T>(aDAO: iSimpleDAO<T>; aCount: Integer): Integer;
var
  LList: TObjectList<T>;
begin
  if aDAO = nil then
    raise ESimpleSeeder.Create('SeedAndInsert requires a valid iSimpleDAO instance');

  LList := Seed<T>(aCount);
  try
    aDAO.InsertBatch(LList);
    Result := LList.Count;
  finally
    FreeAndNil(LList);
  end;
end;

end.

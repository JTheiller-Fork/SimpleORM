unit SimpleRTTIHelper;

interface

uses
  SimpleAttributes,
  SimpleAIAttributes,
  System.Rtti;

type
  TCustomAttributeClass = class of TCustomAttribute;

  TRttiPropertyHelper = class helper for TRttiProperty
  public
    function Tem<T: TCustomAttribute>: Boolean;
    function GetAttribute<T: TCustomAttribute>: T;
    function IsNotNull: Boolean;
    function IsNotZero: Boolean;
    function IsIgnore: Boolean;
    function IsEnum: Boolean;
    function IsAutoInc: Boolean;
    function IsHasOne: Boolean;
    function IsBelongsTo: Boolean;
    function IsHasMany: Boolean;
    function IsBelongsToMany: Boolean;
    function GetRelationship: Relationship;
    function EhCampo: Boolean;
    function EhChavePrimaria: Boolean;
    function EhChaveEstrangeira: Boolean;
    function EhSomenteNumeros: Boolean;
    function EhPermitidoNulo: Boolean;
    function DisplayName: string;
    function FieldName: string;
    function EnumName: string;
    function IsEmail: Boolean;
    function IsUuid: Boolean;
    function HasMinValue: Boolean;
    function HasMaxValue: Boolean;
    function HasRegex: Boolean;
    function HasFormat: Boolean;
    function IsIgnoreUpdate: Boolean;
    function IsIgnoreJSON: Boolean;
    function IsJSONBase64: Boolean;
    function IsCreatedAt: Boolean;
    function IsUpdatedAt: Boolean;
    function IsCascadeDelete: Boolean;
    function IsAIGenerated: Boolean;
    function IsAISummarize: Boolean;
    function IsAITranslate: Boolean;
    function IsAIClassify: Boolean;
    function IsAIValidate: Boolean;
    function HasAIAttribute: Boolean;
    function IsCPF: Boolean;
    function IsCNPJ: Boolean;
  end;

  TRttiTypeHelper = class helper for TRttiType
  public
    function Tem<T: TCustomAttribute>: Boolean;
    function GetAttribute<T: TCustomAttribute>: T;
    function GetPropertyFromAttribute<T: TCustomAttribute>
      : TRttiProperty; overload;
    function GetPropertyFromAttribute<T: Campo>(const aFieldName: string)
      : TRttiProperty; overload;
    function GetPKField: TRttiProperty;
    function IsTabela: Boolean;
    function IsSoftDelete: Boolean;
    function GetSoftDeleteField: string;
    function IsAutomapping: Boolean;
  end;

  TRttiFieldHelper = class helper for TRttiField
  public
    function Tem<T: TCustomAttribute>: Boolean;
    function GetAttribute<T: TCustomAttribute>: T;
  end;

  TValueHelper = record helper for TValue
  public
    function AsStringNumberOnly: String;
  end;

implementation

uses
  System.SysUtils;

{ TRttiPropertyMelhorado }

function TRttiPropertyHelper.GetAttribute<T>: T;
var
  oAtributo: TCustomAttribute;
begin
  Result := nil;
  for oAtributo in GetAttributes do
    if oAtributo is T then
      Exit((oAtributo as T));
end;

function TRttiPropertyHelper.DisplayName: string;
begin
  Result := Name;

  if Tem<Display> then
    Result := GetAttribute<Display>.Name
end;

function TRttiPropertyHelper.EhCampo: Boolean;
begin
  Result := Tem<Campo>
end;

function TRttiPropertyHelper.EhChaveEstrangeira: Boolean;
begin
  Result := Tem<FK>
end;

function TRttiPropertyHelper.EhChavePrimaria: Boolean;
begin
  Result := Tem<PK>
end;

function TRttiPropertyHelper.IsNotNull: Boolean;
begin
  Result := Tem<NotNull>
end;

function TRttiPropertyHelper.IsNotZero: Boolean;
begin
  Result := Tem<NotZero>
end;

function TRttiPropertyHelper.IsIgnore: Boolean;
begin
  Result := Tem<Ignore>
end;

function TRttiPropertyHelper.IsEnum: Boolean;
begin
  Result := Tem<Enumerator>
end;

function TRttiPropertyHelper.IsAutoInc: Boolean;
begin
  Result := Tem<AutoInc>
end;

function TRttiPropertyHelper.IsHasOne: Boolean;
begin
  Result := Tem<HasOne>
end;

function TRttiPropertyHelper.IsBelongsTo: Boolean;
begin
  Result := Tem<BelongsTo>
end;

function TRttiPropertyHelper.IsHasMany: Boolean;
begin
  Result := Tem<HasMany>
end;

function TRttiPropertyHelper.IsBelongsToMany: Boolean;
begin
  Result := Tem<BelongsToMany>
end;

function TRttiPropertyHelper.GetRelationship: Relationship;
begin
  Result := GetAttribute<Relationship>;
end;

function TRttiPropertyHelper.EhPermitidoNulo: Boolean;
begin
  Result := not IsNotNull;
end;

function TRttiPropertyHelper.EhSomenteNumeros: Boolean;
begin
  Result := Tem<NumberOnly>
end;

function TRttiPropertyHelper.FieldName: string;
begin
  Result := Name;
  if EhCampo then
    Result := GetAttribute<Campo>.Name;
end;

function TRttiPropertyHelper.EnumName: string;
begin
  Result := Name;
  if IsEnum then
    Result := GetAttribute<Enumerator>.Tipo;
end;

function TRttiPropertyHelper.IsEmail: Boolean;
begin
  Result := Tem<Email>
end;

function TRttiPropertyHelper.IsUuid: Boolean;
begin
  Result := Tem<Uuid>
end;

function TRttiPropertyHelper.HasMinValue: Boolean;
begin
  Result := Tem<MinValue>
end;

function TRttiPropertyHelper.HasMaxValue: Boolean;
begin
  Result := Tem<MaxValue>
end;

function TRttiPropertyHelper.HasRegex: Boolean;
begin
  Result := Tem<Regex>
end;

function TRttiPropertyHelper.HasFormat: Boolean;
begin
  Result := Tem<SimpleAttributes.Format>
end;

function TRttiPropertyHelper.IsIgnoreUpdate: Boolean;
begin
  Result := Tem<IgnoreUpdate>
end;

function TRttiPropertyHelper.IsIgnoreJSON: Boolean;
begin
  Result := Tem<IgnoreJSON>
end;

function TRttiPropertyHelper.IsJSONBase64: Boolean;
begin
  Result := Tem<JSONBase64>
end;

function TRttiPropertyHelper.IsCreatedAt: Boolean;
begin
  Result := Tem<CreatedAt>
end;

function TRttiPropertyHelper.IsUpdatedAt: Boolean;
begin
  Result := Tem<UpdatedAt>
end;

function TRttiPropertyHelper.IsCascadeDelete: Boolean;
begin
  Result := Tem<CascadeDelete>
end;

function TRttiPropertyHelper.IsAIGenerated: Boolean;
begin
  Result := Tem<AIGenerated>
end;

function TRttiPropertyHelper.IsAISummarize: Boolean;
begin
  Result := Tem<AISummarize>
end;

function TRttiPropertyHelper.IsAITranslate: Boolean;
begin
  Result := Tem<AITranslate>
end;

function TRttiPropertyHelper.IsAIClassify: Boolean;
begin
  Result := Tem<AIClassify>
end;

function TRttiPropertyHelper.IsAIValidate: Boolean;
begin
  Result := Tem<AIValidate>
end;

function TRttiPropertyHelper.HasAIAttribute: Boolean;
begin
  Result := IsAIGenerated or IsAISummarize or IsAITranslate or
            IsAIClassify or IsAIValidate;
end;

function TRttiPropertyHelper.IsCPF: Boolean;
begin
  Result := Tem<CPF>
end;

function TRttiPropertyHelper.IsCNPJ: Boolean;
begin
  Result := Tem<CNPJ>
end;

function TRttiPropertyHelper.Tem<T>: Boolean;
begin
  Result := GetAttribute<T> <> nil
end;

{ TRttiTypeMelhorado }

function TRttiTypeHelper.GetAttribute<T>: T;
var
  oAtributo: TCustomAttribute;
begin
  Result := nil;
  for oAtributo in GetAttributes do
    if oAtributo is T then
      Exit((oAtributo as T));
end;

function TRttiTypeHelper.GetPKField: TRttiProperty;
begin
  Result := GetPropertyFromAttribute<PK>;
end;

function TRttiTypeHelper.GetPropertyFromAttribute<T>(
  const aFieldName: string): TRttiProperty;
var
  RttiProp: TRttiProperty;
begin
  Result := nil;
  for RttiProp in GetProperties do
  begin
    if RttiProp.GetAttribute<T> = nil then
      Continue;

    if RttiProp.GetAttribute<Campo>.Name = aFieldName then
      Exit(RttiProp);
  end;
end;

function TRttiTypeHelper.GetPropertyFromAttribute<T>: TRttiProperty;
var
  RttiProp: TRttiProperty;
begin
  Result := nil;
  for RttiProp in GetProperties do
    if RttiProp.GetAttribute<T> <> nil then
      Exit(RttiProp);
end;

function TRttiTypeHelper.isTabela: Boolean;
begin
  Result := Tem<Tabela>
end;

function TRttiTypeHelper.IsSoftDelete: Boolean;
begin
  Result := Tem<SoftDelete>
end;

function TRttiTypeHelper.GetSoftDeleteField: string;
begin
  Result := '';
  if Tem<SoftDelete> then
    Result := GetAttribute<SoftDelete>.FieldName;
end;

function TRttiTypeHelper.IsAutomapping: Boolean;
begin
  Result := Tem<Automapping>;
end;

function TRttiTypeHelper.Tem<T>: Boolean;
begin
  Result := GetAttribute<T> <> nil
end;

{ TRttiFieldHelper }

function TRttiFieldHelper.GetAttribute<T>: T;
var
  oAtributo: TCustomAttribute;
begin
  Result := nil;
  for oAtributo in GetAttributes do
    if oAtributo is T then
      Exit((oAtributo as T));
end;

function TRttiFieldHelper.Tem<T>: Boolean;
begin
  Result := GetAttribute<T> <> nil
end;

{ TValueHelper.NumberOnly }

function TValueHelper.AsStringNumberOnly: String;
var
  sContent: string;
  nIndex: Integer;
begin
  Result := '';
  sContent := Trim(AsString);

  for nIndex := 1 to Length(sContent) do
    if CharInSet(sContent[nIndex], ['0'..'9']) then
      Result := Result + sContent[nIndex];
end;

end.


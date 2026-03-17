unit SimpleValidator;


interface

uses
  System.Classes, System.Rtti, SimpleAttributes, System.SysUtils, SimpleRTTIHelper,
  System.RegularExpressions;

type
  ESimpleValidator = class(Exception);

  TSimpleValidator = class
  private
    class procedure ValidateNotNull(const aErrros: TStrings; const aObject:
      TObject; const aProperty: TRttiProperty); static;
    class procedure ValidateNotZero(const aErrros: TStrings; const aObject:
      TObject; const aProperty: TRttiProperty); static;
    class procedure ValidateFormat(const aErrors: TStrings; const aObject:
      TObject; const aProperty: TRttiProperty); static;
    class procedure ValidateEmail(const aErrors: TStrings; const aObject:
      TObject; const aProperty: TRttiProperty); static;
    class procedure ValidateMinValue(const aErrors: TStrings; const aObject:
      TObject; const aProperty: TRttiProperty); static;
    class procedure ValidateMaxValue(const aErrors: TStrings; const aObject:
      TObject; const aProperty: TRttiProperty); static;
    class procedure ValidateRegex(const aErrors: TStrings; const aObject:
      TObject; const aProperty: TRttiProperty); static;
    class procedure ValidateCPF(const aErrors: TStrings; const aObject:
      TObject; const aProperty: TRttiProperty); static;
    class procedure ValidateCNPJ(const aErrors: TStrings; const aObject:
      TObject; const aProperty: TRttiProperty); static;
  public
    class procedure Validate(const aObject: TObject); overload; static;
    class procedure Validate(const aObject: TObject; const aErrors:
      TStrings); overload; static;
    class function IsClassRtti(const aObject: TObject): Boolean; static;
  end;

implementation

const
  sMSG_NOT_NULL = 'O Campo %s n�o foi informado!';
  sMSG_NUMBER_NOT_NULL = 'O Campo %s n�o pode ser Zero!';
  sMSG_TIME_NOT_NULL = '� obrigat�rio informar uma hora v�lida para %s';
  sMSG_DATE_NOT_NULL = '� obrigat�rio informar uma data v�lida para %s';
  sMSG_FORMAT_MAX = 'O campo %s deve ter no m' + #225 + 'ximo %d caracteres!';
  sMSG_FORMAT_MIN = 'O campo %s deve ter no m' + #237 + 'nimo %d caracteres!';
  sMSG_EMAIL = 'O campo %s deve ser um e-mail v' + #225 + 'lido!';
  sMSG_MIN_VALUE = 'O campo %s deve ser maior ou igual a %s!';
  sMSG_MAX_VALUE = 'O campo %s deve ser menor ou igual a %s!';
  sMSG_REGEX = 'O campo %s n' + #227 + 'o est' + #225 + ' no formato esperado!';
  sMSG_CPF = 'O campo %s n' + #227 + 'o cont' + #233 + 'm um CPF v' + #225 + 'lido!';
  sMSG_CNPJ = 'O campo %s n' + #227 + 'o cont' + #233 + 'm um CNPJ v' + #225 + 'lido!';

class procedure TSimpleValidator.Validate(const aObject: TObject; const
  aErrors: TStrings);
var
  ctxRttiEntity: TRttiContext;
  typRttiEntity: TRttiType;
  prpRtti: TRttiProperty;
  Value: TValue;
begin
  ctxRttiEntity := TRttiContext.Create;
  typRttiEntity := ctxRttiEntity.GetType(aObject.ClassType);

  for prpRtti in typRttiEntity.GetProperties do
  begin
    if prpRtti.IsIgnore then
      Continue;

    Value := prpRtti.GetValue(aObject);
    if Value.IsObject then
      Validate(Value.AsObject, aErrors);

    if prpRtti.IsNotNull then
      ValidateNotNull(aErrors, aObject, prpRtti);

    if prpRtti.IsNotZero then
      ValidateNotZero(aErrors, aObject, prpRtti);

    if prpRtti.HasFormat then
      ValidateFormat(aErrors, aObject, prpRtti);
    if prpRtti.IsEmail then
      ValidateEmail(aErrors, aObject, prpRtti);
    if prpRtti.HasMinValue then
      ValidateMinValue(aErrors, aObject, prpRtti);
    if prpRtti.HasMaxValue then
      ValidateMaxValue(aErrors, aObject, prpRtti);
    if prpRtti.HasRegex then
      ValidateRegex(aErrors, aObject, prpRtti);
    if prpRtti.IsCPF then
      ValidateCPF(aErrors, aObject, prpRtti);
    if prpRtti.IsCNPJ then
      ValidateCNPJ(aErrors, aObject, prpRtti);
  end;
end;

class function TSimpleValidator.IsClassRtti(const aObject: TObject): Boolean;
var
  ctxRttiEntity: TRttiContext;
  typRttiEntity: TRttiType;
begin
  ctxRttiEntity := TRttiContext.Create;
  typRttiEntity := ctxRttiEntity.GetType(aObject.ClassType);
  Exit(typRttiEntity.GetAttributes <> nil);
end;

class procedure TSimpleValidator.Validate(const aObject: TObject);
var
  sErrors: TStringList;
begin
  sErrors := TStringList.Create;
  try
    TSimpleValidator.Validate(aObject, sErrors);
    if sErrors.Count > 0 then
      raise ESimpleValidator.Create('Encontrado erros de preenchimento!'#13 +
        'Detalhes:'#13 + sErrors.Text);
  finally
    FreeAndNil(sErrors);
  end;
end;

class procedure TSimpleValidator.ValidateNotNull(const aErrros: TStrings; const
  aObject: TObject; const aProperty: TRttiProperty);
var
  Value: TValue;
begin
  Value := aProperty.GetValue(aObject);
  case Value.Kind of
    tkUString:
      if string.IsNullOrWhiteSpace(Value.AsString) then
        aErrros.Add(System.SysUtils.Format(sMSG_NOT_NULL, [aProperty.DisplayName]));
    tkInteger:
      ; // Integers always have a value in Delphi, NotNull is inherently satisfied
    tkFloat:
      begin
        if (Value.AsExtended <> 0) then
          Exit;

        if (Value.TypeInfo = TypeInfo(Real)) or (Value.TypeInfo = TypeInfo(Double)) then
          aErrros.Add(System.SysUtils.Format(sMSG_NUMBER_NOT_NULL, [aProperty.DisplayName]));

        if Value.TypeInfo = TypeInfo(TTime) then
          aErrros.Add(System.SysUtils.Format(sMSG_TIME_NOT_NULL, [aProperty.DisplayName]));

        if (Value.TypeInfo = TypeInfo(TDate)) or (Value.TypeInfo = TypeInfo(TDateTime))
          then
          aErrros.Add(System.SysUtils.Format(sMSG_DATE_NOT_NULL, [aProperty.DisplayName]));
      end;
  else
    if Value.IsEmpty then
      aErrros.Add(System.SysUtils.Format(sMSG_NOT_NULL, [aProperty.DisplayName]));
  end;
end;

class procedure TSimpleValidator.ValidateNotZero(const aErrros: TStrings; const
  aObject: TObject; const aProperty: TRttiProperty);
var
  Value: TValue;
begin
  Value := aProperty.GetValue(aObject);
  case Value.Kind of
    tkInteger:
      if Value.AsInteger = 0 then
        aErrros.Add(System.SysUtils.Format(sMSG_NUMBER_NOT_NULL, [aProperty.DisplayName]));
    tkFloat:
      if Value.AsExtended = 0 then
        aErrros.Add(System.SysUtils.Format(sMSG_NUMBER_NOT_NULL, [aProperty.DisplayName]));
  end;
end;

class procedure TSimpleValidator.ValidateFormat(const aErrors: TStrings; const
  aObject: TObject; const aProperty: TRttiProperty);
var
  Value: TValue;
  Fmt: SimpleAttributes.Format;
  Len: Integer;
begin
  Value := aProperty.GetValue(aObject);
  Fmt := aProperty.GetAttribute<SimpleAttributes.Format>;
  if Fmt = nil then Exit;

  if Value.Kind in [tkUString, tkString, tkLString, tkWString] then
  begin
    Len := Length(Value.AsString);
    if (Fmt.MaxSize > 0) and (Len > Fmt.MaxSize) then
      aErrors.Add(System.SysUtils.Format(sMSG_FORMAT_MAX, [aProperty.DisplayName, Fmt.MaxSize]));
    if (Fmt.MinSize > 0) and (Len < Fmt.MinSize) then
      aErrors.Add(System.SysUtils.Format(sMSG_FORMAT_MIN, [aProperty.DisplayName, Fmt.MinSize]));
  end;
end;

class procedure TSimpleValidator.ValidateEmail(const aErrors: TStrings; const
  aObject: TObject; const aProperty: TRttiProperty);
var
  Value: TValue;
  EmailStr: string;
begin
  Value := aProperty.GetValue(aObject);
  if Value.Kind in [tkUString, tkString, tkLString, tkWString] then
  begin
    EmailStr := Value.AsString;
    if EmailStr <> '' then
    begin
      if not TRegEx.IsMatch(EmailStr, '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
        aErrors.Add(System.SysUtils.Format(sMSG_EMAIL, [aProperty.DisplayName]));
    end;
  end;
end;

class procedure TSimpleValidator.ValidateMinValue(const aErrors: TStrings; const
  aObject: TObject; const aProperty: TRttiProperty);
var
  Value: TValue;
  Attr: MinValue;
begin
  Value := aProperty.GetValue(aObject);
  Attr := aProperty.GetAttribute<MinValue>;
  if Attr = nil then Exit;

  case Value.Kind of
    tkInteger:
      if Value.AsInteger < Attr.Value then
        aErrors.Add(System.SysUtils.Format(sMSG_MIN_VALUE, [aProperty.DisplayName, FloatToStr(Attr.Value)]));
    tkFloat:
      if Value.AsExtended < Attr.Value then
        aErrors.Add(System.SysUtils.Format(sMSG_MIN_VALUE, [aProperty.DisplayName, FloatToStr(Attr.Value)]));
  end;
end;

class procedure TSimpleValidator.ValidateMaxValue(const aErrors: TStrings; const
  aObject: TObject; const aProperty: TRttiProperty);
var
  Value: TValue;
  Attr: MaxValue;
begin
  Value := aProperty.GetValue(aObject);
  Attr := aProperty.GetAttribute<MaxValue>;
  if Attr = nil then Exit;

  case Value.Kind of
    tkInteger:
      if Value.AsInteger > Attr.Value then
        aErrors.Add(System.SysUtils.Format(sMSG_MAX_VALUE, [aProperty.DisplayName, FloatToStr(Attr.Value)]));
    tkFloat:
      if Value.AsExtended > Attr.Value then
        aErrors.Add(System.SysUtils.Format(sMSG_MAX_VALUE, [aProperty.DisplayName, FloatToStr(Attr.Value)]));
  end;
end;

class procedure TSimpleValidator.ValidateRegex(const aErrors: TStrings; const
  aObject: TObject; const aProperty: TRttiProperty);
var
  Value: TValue;
  Attr: Regex;
  Str: string;
begin
  Value := aProperty.GetValue(aObject);
  Attr := aProperty.GetAttribute<Regex>;
  if Attr = nil then Exit;

  if Value.Kind in [tkUString, tkString, tkLString, tkWString] then
  begin
    Str := Value.AsString;
    if Str <> '' then
    begin
      if not TRegEx.IsMatch(Str, Attr.Pattern) then
      begin
        if Attr.Message <> '' then
          aErrors.Add(Attr.Message)
        else
          aErrors.Add(System.SysUtils.Format(sMSG_REGEX, [aProperty.DisplayName]));
      end;
    end;
  end;
end;

function StripMask(const aValue: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(aValue) do
    if CharInSet(aValue[I], ['0'..'9']) then
      Result := Result + aValue[I];
end;

function AllSameDigits(const aValue: String): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 2 to Length(aValue) do
    if aValue[I] <> aValue[1] then
      Exit(False);
end;

class procedure TSimpleValidator.ValidateCPF(const aErrors: TStrings; const aObject:
  TObject; const aProperty: TRttiProperty);
var
  Value: TValue;
  LCPF: String;
  LSum, LRest, I: Integer;
begin
  Value := aProperty.GetValue(aObject);
  if not (Value.Kind in [tkUString, tkString, tkLString, tkWString]) then
    Exit;

  LCPF := Value.AsString;
  if LCPF = '' then
    Exit;

  LCPF := StripMask(LCPF);

  if (Length(LCPF) <> 11) or AllSameDigits(LCPF) then
  begin
    aErrors.Add(System.SysUtils.Format(sMSG_CPF, [aProperty.DisplayName]));
    Exit;
  end;

  // First check digit
  LSum := 0;
  for I := 1 to 9 do
    LSum := LSum + StrToInt(LCPF[I]) * (11 - I);
  LRest := (LSum * 10) mod 11;
  if LRest = 10 then
    LRest := 0;
  if LRest <> StrToInt(LCPF[10]) then
  begin
    aErrors.Add(System.SysUtils.Format(sMSG_CPF, [aProperty.DisplayName]));
    Exit;
  end;

  // Second check digit
  LSum := 0;
  for I := 1 to 10 do
    LSum := LSum + StrToInt(LCPF[I]) * (12 - I);
  LRest := (LSum * 10) mod 11;
  if LRest = 10 then
    LRest := 0;
  if LRest <> StrToInt(LCPF[11]) then
    aErrors.Add(System.SysUtils.Format(sMSG_CPF, [aProperty.DisplayName]));
end;

class procedure TSimpleValidator.ValidateCNPJ(const aErrors: TStrings; const aObject:
  TObject; const aProperty: TRttiProperty);
var
  Value: TValue;
  LCNPJ: String;
  LSum, LRest, I: Integer;
const
  WEIGHTS1: array[1..12] of Integer = (5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2);
  WEIGHTS2: array[1..13] of Integer = (6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2);
begin
  Value := aProperty.GetValue(aObject);
  if not (Value.Kind in [tkUString, tkString, tkLString, tkWString]) then
    Exit;

  LCNPJ := Value.AsString;
  if LCNPJ = '' then
    Exit;

  LCNPJ := StripMask(LCNPJ);

  if (Length(LCNPJ) <> 14) or AllSameDigits(LCNPJ) then
  begin
    aErrors.Add(System.SysUtils.Format(sMSG_CNPJ, [aProperty.DisplayName]));
    Exit;
  end;

  // First check digit
  LSum := 0;
  for I := 1 to 12 do
    LSum := LSum + StrToInt(LCNPJ[I]) * WEIGHTS1[I];
  LRest := LSum mod 11;
  if LRest < 2 then
    LRest := 0
  else
    LRest := 11 - LRest;
  if LRest <> StrToInt(LCNPJ[13]) then
  begin
    aErrors.Add(System.SysUtils.Format(sMSG_CNPJ, [aProperty.DisplayName]));
    Exit;
  end;

  // Second check digit
  LSum := 0;
  for I := 1 to 13 do
    LSum := LSum + StrToInt(LCNPJ[I]) * WEIGHTS2[I];
  LRest := LSum mod 11;
  if LRest < 2 then
    LRest := 0
  else
    LRest := 11 - LRest;
  if LRest <> StrToInt(LCNPJ[14]) then
    aErrors.Add(System.SysUtils.Format(sMSG_CNPJ, [aProperty.DisplayName]));
end;

end.


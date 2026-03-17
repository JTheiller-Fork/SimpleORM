unit SimpleExportSheets;

interface

uses
  SimpleAttributes,
  SimpleRTTIHelper,
  System.SysUtils, System.Classes, System.Rtti, System.JSON,
  System.TypInfo, System.Generics.Collections,
  System.Net.HttpClient, System.Net.URLClient;

type
  ESimpleExportSheets = class(Exception);

  TSimpleExportSheets = class
  private
    FAccessToken: string;
    FSpreadsheetId: string;
    FSheetName: string;

    function DoHTTPRequest(const aMethod, aURL, aBody: string): string;
  public
    constructor Create(const aAccessToken: string);
    destructor Destroy; override;
    class function New(const aAccessToken: string): TSimpleExportSheets;

    function SpreadsheetId(const aValue: string): TSimpleExportSheets;
    function SheetName(const aValue: string): TSimpleExportSheets;

    function Export<T: class>(aList: TObjectList<T>): TSimpleExportSheets;
    function CreateSpreadsheet(const aTitle: string): string;
  end;

implementation

{ TSimpleExportSheets }

constructor TSimpleExportSheets.Create(const aAccessToken: string);
begin
  inherited Create;
  FAccessToken := aAccessToken;
  FSpreadsheetId := '';
  FSheetName := 'Sheet1';
end;

destructor TSimpleExportSheets.Destroy;
begin
  inherited;
end;

class function TSimpleExportSheets.New(const aAccessToken: string): TSimpleExportSheets;
begin
  Result := Self.Create(aAccessToken);
end;

function TSimpleExportSheets.SpreadsheetId(const aValue: string): TSimpleExportSheets;
begin
  Result := Self;
  FSpreadsheetId := aValue;
end;

function TSimpleExportSheets.SheetName(const aValue: string): TSimpleExportSheets;
begin
  Result := Self;
  FSheetName := aValue;
end;

function TSimpleExportSheets.Export<T>(aList: TObjectList<T>): TSimpleExportSheets;
var
  LContext: TRttiContext;
  LType: TRttiType;
  LProp: TRttiProperty;
  LProps: TArray<TRttiProperty>;
  LValidProps: TList<TRttiProperty>;
  LHeaders: TJSONArray;
  LRows: TJSONArray;
  LRow: TJSONArray;
  LValues: TJSONObject;
  LURL: string;
  LBody: string;
  LValue: TValue;
  LStrValue: string;
  I, J: Integer;
begin
  Result := Self;

  if FSpreadsheetId = '' then
    raise ESimpleExportSheets.Create('SpreadsheetId is required. Call SpreadsheetId() or CreateSpreadsheet() first.');

  LContext := TRttiContext.Create;
  LValidProps := TList<TRttiProperty>.Create;
  try
    LType := LContext.GetType(T);
    LProps := LType.GetProperties;

    for I := 0 to Length(LProps) - 1 do
    begin
      LProp := LProps[I];

      if LProp.IsIgnore then
        Continue;

      if not LProp.EhCampo then
        Continue;

      if LProp.IsHasOne or LProp.IsBelongsTo or LProp.IsHasMany or LProp.IsBelongsToMany then
        Continue;

      LValidProps.Add(LProp);
    end;

    LHeaders := TJSONArray.Create;
    try
      for I := 0 to LValidProps.Count - 1 do
        LHeaders.Add(LValidProps[I].DisplayName);

      LRows := TJSONArray.Create;
      try
        LRows.AddElement(LHeaders.Clone as TJSONArray);

        for I := 0 to aList.Count - 1 do
        begin
          LRow := TJSONArray.Create;
          for J := 0 to LValidProps.Count - 1 do
          begin
            LProp := LValidProps[J];
            LValue := LProp.GetValue(TObject(aList[I]));
            LStrValue := '';

            case LProp.PropertyType.TypeKind of
              tkInteger:
                LStrValue := IntToStr(LValue.AsInteger);
              tkInt64:
                LStrValue := IntToStr(LValue.AsInt64);
              tkFloat:
              begin
                if (LProp.PropertyType.Handle = System.TypeInfo(TDateTime)) or
                   (LProp.PropertyType.Handle = System.TypeInfo(TDate)) or
                   (LProp.PropertyType.Handle = System.TypeInfo(TTime)) then
                  LStrValue := FormatDateTime('yyyy-mm-dd hh:nn:ss', LValue.AsExtended)
                else
                  LStrValue := FloatToStr(LValue.AsExtended);
              end;
              tkUString, tkString, tkLString, tkWString:
                LStrValue := LValue.AsString;
              tkEnumeration:
              begin
                if LProp.PropertyType.Handle = System.TypeInfo(Boolean) then
                begin
                  if LValue.AsBoolean then
                    LStrValue := 'True'
                  else
                    LStrValue := 'False';
                end
                else
                  LStrValue := GetEnumName(LProp.PropertyType.Handle, LValue.AsOrdinal);
              end;
            else
              LStrValue := LValue.ToString;
            end;

            LRow.Add(LStrValue);
          end;
          LRows.AddElement(LRow);
        end;

        LValues := TJSONObject.Create;
        try
          LValues.AddPair('range', FSheetName + '!A1');
          LValues.AddPair('majorDimension', 'ROWS');
          LValues.AddPair('values', LRows.Clone as TJSONArray);

          LBody := LValues.ToString;
        finally
          FreeAndNil(LValues);
        end;

        LURL := 'https://sheets.googleapis.com/v4/spreadsheets/' +
                FSpreadsheetId + '/values/' +
                FSheetName + '!A1?valueInputOption=RAW';

        DoHTTPRequest('PUT', LURL, LBody);
      finally
        FreeAndNil(LRows);
      end;
    finally
      FreeAndNil(LHeaders);
    end;
  finally
    FreeAndNil(LValidProps);
    LContext.Free;
  end;
end;

function TSimpleExportSheets.CreateSpreadsheet(const aTitle: string): string;
var
  LBody: TJSONObject;
  LProps: TJSONObject;
  LBodyStr: string;
  LResponseStr: string;
  LResponseJSON: TJSONValue;
  LResponseObj: TJSONObject;
  LURL: string;
begin
  Result := '';
  LURL := 'https://sheets.googleapis.com/v4/spreadsheets';

  LBody := TJSONObject.Create;
  try
    LProps := TJSONObject.Create;
    LProps.AddPair('title', aTitle);
    LBody.AddPair('properties', LProps);
    LBodyStr := LBody.ToString;
  finally
    FreeAndNil(LBody);
  end;

  LResponseStr := DoHTTPRequest('POST', LURL, LBodyStr);

  LResponseJSON := TJSONObject.ParseJSONValue(LResponseStr);
  if not Assigned(LResponseJSON) then
    raise ESimpleExportSheets.Create('Google Sheets API: invalid JSON response');

  try
    if not (LResponseJSON is TJSONObject) then
      raise ESimpleExportSheets.Create('Google Sheets API: expected JSON object in response');

    LResponseObj := TJSONObject(LResponseJSON);

    if not Assigned(LResponseObj.Values['spreadsheetId']) then
      raise ESimpleExportSheets.Create('Google Sheets API: spreadsheetId not found in response');

    Result := LResponseObj.Values['spreadsheetId'].Value;
    FSpreadsheetId := Result;
  finally
    FreeAndNil(LResponseJSON);
  end;
end;

function TSimpleExportSheets.DoHTTPRequest(const aMethod, aURL, aBody: string): string;
var
  LClient: THTTPClient;
  LContent: TStringStream;
  LResponse: IHTTPResponse;
begin
  Result := '';
  LClient := THTTPClient.Create;
  try
    LClient.ContentType := 'application/json';
    LClient.CustomHeaders['Authorization'] := 'Bearer ' + FAccessToken;

    if SameText(aMethod, 'PUT') then
    begin
      LContent := TStringStream.Create(aBody, TEncoding.UTF8);
      try
        LResponse := LClient.Put(aURL, LContent);
      finally
        FreeAndNil(LContent);
      end;
    end
    else if SameText(aMethod, 'POST') then
    begin
      LContent := TStringStream.Create(aBody, TEncoding.UTF8);
      try
        LResponse := LClient.Post(aURL, LContent);
      finally
        FreeAndNil(LContent);
      end;
    end;

    if Assigned(LResponse) then
    begin
      if LResponse.StatusCode >= 400 then
        raise ESimpleExportSheets.CreateFmt('Google Sheets API HTTP %d: %s',
          [LResponse.StatusCode, LResponse.ContentAsString(TEncoding.UTF8)]);
      Result := LResponse.ContentAsString(TEncoding.UTF8);
    end;
  finally
    FreeAndNil(LClient);
  end;
end;

end.

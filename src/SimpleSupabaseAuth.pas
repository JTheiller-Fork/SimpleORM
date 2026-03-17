unit SimpleSupabaseAuth;

interface

uses
  SimpleInterface,
  System.SysUtils, System.JSON, System.DateUtils,
  System.Net.HttpClient, System.Net.URLClient, System.Classes;

type
  TSimpleSupabaseAuth = class(TInterfacedObject, iSimpleSupabaseAuth)
  private
    FBaseURL: string;
    FAPIKey: string;
    FAccessToken: string;
    FRefreshTokenValue: string;
    FUserJSON: string;
    FExpiresAt: TDateTime;

    function DoAuthRequest(aEndpoint, aBody: string): TJSONObject;
    procedure ParseAuthResponse(aResponse: TJSONObject);
  public
    constructor Create(aBaseURL, aAPIKey: string);
    destructor Destroy; override;
    class function New(aBaseURL, aAPIKey: string): iSimpleSupabaseAuth;

    { iSimpleSupabaseAuth }
    function SignIn(aEmail, aPassword: String): iSimpleSupabaseAuth;
    function SignUp(aEmail, aPassword: String): iSimpleSupabaseAuth;
    function SignOut: iSimpleSupabaseAuth;
    function RefreshToken: iSimpleSupabaseAuth;
    function Token: String;
    function User: String;
    function IsAuthenticated: Boolean;
    function ExpiresAt: TDateTime;
  end;

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;
{$ENDIF}

{ TSimpleSupabaseAuth }

constructor TSimpleSupabaseAuth.Create(aBaseURL, aAPIKey: string);
begin
  inherited Create;
  FBaseURL := aBaseURL.TrimRight(['/']);
  FAPIKey := aAPIKey;
  FAccessToken := '';
  FRefreshTokenValue := '';
  FUserJSON := '';
  FExpiresAt := 0;
end;

destructor TSimpleSupabaseAuth.Destroy;
begin
  inherited;
end;

class function TSimpleSupabaseAuth.New(aBaseURL, aAPIKey: string): iSimpleSupabaseAuth;
begin
  Result := Self.Create(aBaseURL, aAPIKey);
end;

function TSimpleSupabaseAuth.DoAuthRequest(aEndpoint, aBody: string): TJSONObject;
var
  LClient: THTTPClient;
  LContent: TStringStream;
  LResponse: IHTTPResponse;
  LURL: string;
  LResponseStr: string;
  LValue: TJSONValue;
begin
  Result := nil;
  LURL := FBaseURL + aEndpoint;
  LClient := THTTPClient.Create;
  try
    LContent := TStringStream.Create(aBody, TEncoding.UTF8);
    try
      LClient.ContentType := 'application/json';
      LClient.CustomHeaders['apikey'] := FAPIKey;

      if FAccessToken <> '' then
        LClient.CustomHeaders['Authorization'] := 'Bearer ' + FAccessToken;

      LResponse := LClient.Post(LURL, LContent);
    finally
      FreeAndNil(LContent);
    end;

    if LResponse.StatusCode >= 400 then
      raise Exception.CreateFmt('Supabase Auth HTTP %d: %s',
        [LResponse.StatusCode, LResponse.ContentAsString(TEncoding.UTF8)]);

    LResponseStr := LResponse.ContentAsString(TEncoding.UTF8);
    if LResponseStr.Trim = '' then
      Exit;

    LValue := TJSONObject.ParseJSONValue(LResponseStr);
    if not Assigned(LValue) then
      raise Exception.Create('Supabase Auth: invalid JSON response');

    if not (LValue is TJSONObject) then
    begin
      LValue.Free;
      raise Exception.Create('Supabase Auth: expected JSON object in response');
    end;

    Result := TJSONObject(LValue);
  finally
    FreeAndNil(LClient);
  end;
end;

procedure TSimpleSupabaseAuth.ParseAuthResponse(aResponse: TJSONObject);
var
  LExpiresIn: Integer;
  LUserValue: TJSONValue;
begin
  if not Assigned(aResponse) then
    Exit;

  if Assigned(aResponse.Values['access_token']) then
    FAccessToken := aResponse.Values['access_token'].Value;

  if Assigned(aResponse.Values['refresh_token']) then
    FRefreshTokenValue := aResponse.Values['refresh_token'].Value;

  if Assigned(aResponse.Values['expires_in']) then
  begin
    LExpiresIn := TJSONNumber(aResponse.Values['expires_in']).AsInt;
    FExpiresAt := IncSecond(Now, LExpiresIn);
  end;

  LUserValue := aResponse.Values['user'];
  if Assigned(LUserValue) then
    FUserJSON := LUserValue.ToString;
end;

function TSimpleSupabaseAuth.SignIn(aEmail, aPassword: String): iSimpleSupabaseAuth;
var
  LBody: TJSONObject;
  LBodyStr: string;
  LResponse: TJSONObject;
begin
  Result := Self;
  LBody := TJSONObject.Create;
  try
    LBody.AddPair('email', aEmail);
    LBody.AddPair('password', aPassword);
    LBodyStr := LBody.ToString;
  finally
    FreeAndNil(LBody);
  end;

  LResponse := DoAuthRequest('/auth/v1/token?grant_type=password', LBodyStr);
  try
    ParseAuthResponse(LResponse);
  finally
    FreeAndNil(LResponse);
  end;
end;

function TSimpleSupabaseAuth.SignUp(aEmail, aPassword: String): iSimpleSupabaseAuth;
var
  LBody: TJSONObject;
  LBodyStr: string;
  LResponse: TJSONObject;
begin
  Result := Self;
  LBody := TJSONObject.Create;
  try
    LBody.AddPair('email', aEmail);
    LBody.AddPair('password', aPassword);
    LBodyStr := LBody.ToString;
  finally
    FreeAndNil(LBody);
  end;

  LResponse := DoAuthRequest('/auth/v1/signup', LBodyStr);
  try
    ParseAuthResponse(LResponse);
  finally
    FreeAndNil(LResponse);
  end;
end;

function TSimpleSupabaseAuth.SignOut: iSimpleSupabaseAuth;
var
  LClient: THTTPClient;
  LContent: TStringStream;
  LResponse: IHTTPResponse;
  LURL: string;
begin
  Result := Self;

  if FAccessToken <> '' then
  begin
    LURL := FBaseURL + '/auth/v1/logout';
    LClient := THTTPClient.Create;
    try
      LContent := TStringStream.Create('', TEncoding.UTF8);
      try
        LClient.ContentType := 'application/json';
        LClient.CustomHeaders['apikey'] := FAPIKey;
        LClient.CustomHeaders['Authorization'] := 'Bearer ' + FAccessToken;

        LResponse := LClient.Post(LURL, LContent);

        if LResponse.StatusCode >= 400 then
          raise Exception.CreateFmt('Supabase Auth SignOut HTTP %d: %s',
            [LResponse.StatusCode, LResponse.ContentAsString(TEncoding.UTF8)]);
      finally
        FreeAndNil(LContent);
      end;
    finally
      FreeAndNil(LClient);
    end;
  end;

  FAccessToken := '';
  FRefreshTokenValue := '';
  FUserJSON := '';
  FExpiresAt := 0;
end;

function TSimpleSupabaseAuth.RefreshToken: iSimpleSupabaseAuth;
var
  LBody: TJSONObject;
  LBodyStr: string;
  LResponse: TJSONObject;
begin
  Result := Self;

  if FRefreshTokenValue = '' then
    raise Exception.Create('Supabase Auth: no refresh token available. Call SignIn first.');

  LBody := TJSONObject.Create;
  try
    LBody.AddPair('refresh_token', FRefreshTokenValue);
    LBodyStr := LBody.ToString;
  finally
    FreeAndNil(LBody);
  end;

  LResponse := DoAuthRequest('/auth/v1/token?grant_type=refresh_token', LBodyStr);
  try
    ParseAuthResponse(LResponse);
  finally
    FreeAndNil(LResponse);
  end;
end;

function TSimpleSupabaseAuth.Token: String;
begin
  if (FAccessToken <> '') and (FExpiresAt > 0) and
     (Now >= IncSecond(FExpiresAt, -30)) then
  begin
    try
      RefreshToken;
    except
      on E: Exception do
      begin
        {$IFDEF MSWINDOWS}
        OutputDebugString(PChar('[SimpleORM] Token refresh failed: ' + E.Message));
        {$ENDIF}
        {$IFDEF CONSOLE}
        Writeln('[SimpleORM] Token refresh failed: ', E.Message);
        {$ENDIF}
      end;
    end;
  end;

  Result := FAccessToken;
end;

function TSimpleSupabaseAuth.User: String;
begin
  Result := FUserJSON;
end;

function TSimpleSupabaseAuth.IsAuthenticated: Boolean;
begin
  Result := (FAccessToken <> '') and (FExpiresAt > Now);
end;

function TSimpleSupabaseAuth.ExpiresAt: TDateTime;
begin
  Result := FExpiresAt;
end;

end.

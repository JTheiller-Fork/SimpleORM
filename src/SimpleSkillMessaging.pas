unit SimpleSkillMessaging;

interface

uses
  SimpleInterface,
  SimpleTypes,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Net.HttpClient
  {$IFDEF MSWINDOWS}
  , Winapi.Windows
  {$ENDIF};

type
  { TSkillTelegram - Sends notifications to Telegram via Bot API }
  TSkillTelegram = class(TInterfacedObject, iSimpleSkill)
  private
    FBotToken: String;
    FChatId: String;
    FMessageTemplate: String;
    FRunAt: TSkillRunAt;
    function FormatMessage(aEntity: TObject; aContext: iSimpleSkillContext): String;
  public
    constructor Create(const aBotToken, aChatId: String;
      const aMessageTemplate: String = ''; aRunAt: TSkillRunAt = srAfterInsert);
    destructor Destroy; override;
    class function New(const aBotToken, aChatId: String;
      const aMessageTemplate: String = ''; aRunAt: TSkillRunAt = srAfterInsert): iSimpleSkill;
    function Execute(aEntity: TObject; aContext: iSimpleSkillContext): iSimpleSkill;
    function Name: String;
    function RunAt: TSkillRunAt;
    function RunMode: TSkillRunMode;
  end;

  { TSkillDiscord - Sends notifications to Discord via Webhook }
  TSkillDiscord = class(TInterfacedObject, iSimpleSkill)
  private
    FWebhookURL: String;
    FMessageTemplate: String;
    FRunAt: TSkillRunAt;
    function FormatMessage(aEntity: TObject; aContext: iSimpleSkillContext): String;
  public
    constructor Create(const aWebhookURL: String;
      const aMessageTemplate: String = ''; aRunAt: TSkillRunAt = srAfterInsert);
    destructor Destroy; override;
    class function New(const aWebhookURL: String;
      const aMessageTemplate: String = ''; aRunAt: TSkillRunAt = srAfterInsert): iSimpleSkill;
    function Execute(aEntity: TObject; aContext: iSimpleSkillContext): iSimpleSkill;
    function Name: String;
    function RunAt: TSkillRunAt;
    function RunMode: TSkillRunMode;
  end;

implementation

uses
  SimpleSerializer;

const
  DEFAULT_TEMPLATE = '[SimpleORM] {operation} em {entity} em {timestamp}';

{ TSkillTelegram }

constructor TSkillTelegram.Create(const aBotToken, aChatId: String;
  const aMessageTemplate: String; aRunAt: TSkillRunAt);
begin
  FBotToken := aBotToken;
  FChatId := aChatId;
  FMessageTemplate := aMessageTemplate;
  FRunAt := aRunAt;
end;

destructor TSkillTelegram.Destroy;
begin
  inherited;
end;

class function TSkillTelegram.New(const aBotToken, aChatId: String;
  const aMessageTemplate: String; aRunAt: TSkillRunAt): iSimpleSkill;
begin
  Result := Self.Create(aBotToken, aChatId, aMessageTemplate, aRunAt);
end;

function TSkillTelegram.FormatMessage(aEntity: TObject;
  aContext: iSimpleSkillContext): String;
var
  LTemplate: String;
  LEntityJSON: TJSONObject;
  LDataStr: String;
begin
  if FMessageTemplate <> '' then
    LTemplate := FMessageTemplate
  else
    LTemplate := DEFAULT_TEMPLATE;

  Result := StringReplace(LTemplate, '{entity}', aContext.EntityName, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{operation}', aContext.Operation, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{timestamp}', FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), [rfReplaceAll, rfIgnoreCase]);

  if Pos('{data}', LowerCase(Result)) > 0 then
  begin
    LDataStr := '(no entity data)';
    if aEntity <> nil then
    begin
      try
        LEntityJSON := TSimpleSerializer.EntityToJSON<TObject>(aEntity);
        try
          LDataStr := LEntityJSON.ToJSON;
        finally
          LEntityJSON.Free;
        end;
      except
        LDataStr := '(serialization error)';
      end;
    end;
    Result := StringReplace(Result, '{data}', LDataStr, [rfReplaceAll, rfIgnoreCase]);
  end;
end;

function TSkillTelegram.Execute(aEntity: TObject;
  aContext: iSimpleSkillContext): iSimpleSkill;
var
  LClient: THTTPClient;
  LPayload: TJSONObject;
  LBody: TStringStream;
  LURL: String;
  LMessage: String;
begin
  Result := Self;

  LMessage := FormatMessage(aEntity, aContext);
  LURL := 'https://api.telegram.org/bot' + FBotToken + '/sendMessage';

  LClient := THTTPClient.Create;
  try
    try
      LPayload := TJSONObject.Create;
      try
        LPayload.AddPair('chat_id', FChatId);
        LPayload.AddPair('text', LMessage);
        LPayload.AddPair('parse_mode', 'HTML');

        LBody := TStringStream.Create(LPayload.ToJSON, TEncoding.UTF8);
        try
          LClient.ContentType := 'application/json';
          LClient.ConnectionTimeout := 5000;
          LClient.ResponseTimeout := 10000;
          LClient.Post(LURL, LBody);
        finally
          LBody.Free;
        end;
      finally
        LPayload.Free;
      end;
    except
      on E: Exception do
      begin
        {$IFDEF MSWINDOWS}
        OutputDebugString(PChar('[Skill:Telegram] Error: ' + E.Message));
        {$ENDIF}
        {$IFDEF CONSOLE}
        Writeln('[Skill:Telegram] Error: ', E.Message);
        {$ENDIF}
      end;
    end;
  finally
    LClient.Free;
  end;
end;

function TSkillTelegram.Name: String;
begin
  Result := 'telegram';
end;

function TSkillTelegram.RunAt: TSkillRunAt;
begin
  Result := FRunAt;
end;

function TSkillTelegram.RunMode: TSkillRunMode;
begin
  Result := srmNormal;
end;

{ TSkillDiscord }

constructor TSkillDiscord.Create(const aWebhookURL: String;
  const aMessageTemplate: String; aRunAt: TSkillRunAt);
begin
  FWebhookURL := aWebhookURL;
  FMessageTemplate := aMessageTemplate;
  FRunAt := aRunAt;
end;

destructor TSkillDiscord.Destroy;
begin
  inherited;
end;

class function TSkillDiscord.New(const aWebhookURL: String;
  const aMessageTemplate: String; aRunAt: TSkillRunAt): iSimpleSkill;
begin
  Result := Self.Create(aWebhookURL, aMessageTemplate, aRunAt);
end;

function TSkillDiscord.FormatMessage(aEntity: TObject;
  aContext: iSimpleSkillContext): String;
var
  LTemplate: String;
  LEntityJSON: TJSONObject;
  LDataStr: String;
begin
  if FMessageTemplate <> '' then
    LTemplate := FMessageTemplate
  else
    LTemplate := DEFAULT_TEMPLATE;

  Result := StringReplace(LTemplate, '{entity}', aContext.EntityName, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{operation}', aContext.Operation, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '{timestamp}', FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), [rfReplaceAll, rfIgnoreCase]);

  if Pos('{data}', LowerCase(Result)) > 0 then
  begin
    LDataStr := '(no entity data)';
    if aEntity <> nil then
    begin
      try
        LEntityJSON := TSimpleSerializer.EntityToJSON<TObject>(aEntity);
        try
          LDataStr := LEntityJSON.ToJSON;
        finally
          LEntityJSON.Free;
        end;
      except
        LDataStr := '(serialization error)';
      end;
    end;
    Result := StringReplace(Result, '{data}', LDataStr, [rfReplaceAll, rfIgnoreCase]);
  end;
end;

function TSkillDiscord.Execute(aEntity: TObject;
  aContext: iSimpleSkillContext): iSimpleSkill;
var
  LClient: THTTPClient;
  LPayload: TJSONObject;
  LBody: TStringStream;
  LMessage: String;
begin
  Result := Self;

  LMessage := FormatMessage(aEntity, aContext);

  LClient := THTTPClient.Create;
  try
    try
      LPayload := TJSONObject.Create;
      try
        LPayload.AddPair('content', LMessage);

        LBody := TStringStream.Create(LPayload.ToJSON, TEncoding.UTF8);
        try
          LClient.ContentType := 'application/json';
          LClient.ConnectionTimeout := 5000;
          LClient.ResponseTimeout := 10000;
          LClient.Post(FWebhookURL, LBody);
        finally
          LBody.Free;
        end;
      finally
        LPayload.Free;
      end;
    except
      on E: Exception do
      begin
        {$IFDEF MSWINDOWS}
        OutputDebugString(PChar('[Skill:Discord] Error: ' + E.Message));
        {$ENDIF}
        {$IFDEF CONSOLE}
        Writeln('[Skill:Discord] Error: ', E.Message);
        {$ENDIF}
      end;
    end;
  finally
    LClient.Free;
  end;
end;

function TSkillDiscord.Name: String;
begin
  Result := 'discord';
end;

function TSkillDiscord.RunAt: TSkillRunAt;
begin
  Result := FRunAt;
end;

function TSkillDiscord.RunMode: TSkillRunMode;
begin
  Result := srmNormal;
end;

end.

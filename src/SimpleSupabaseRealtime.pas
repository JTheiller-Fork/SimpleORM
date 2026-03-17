unit SimpleSupabaseRealtime;

interface

uses
  SimpleInterface,
  SimpleTypes,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.SyncObjs,
  System.JSON,
  System.Net.HttpClient,
  System.Net.URLClient;

type
  TTableSubscription = class
  private
    FTable: String;
    FCallback: TSupabaseRealtimeCallback;
    FLastKnownId: String;
  public
    property Table: String read FTable write FTable;
    property Callback: TSupabaseRealtimeCallback read FCallback write FCallback;
    property LastKnownId: String read FLastKnownId write FLastKnownId;
  end;

  TRealtimeListenerThread = class(TThread)
  private
    FBaseURL: String;
    FAPIKey: String;
    FToken: String;
    FSubscriptions: TObjectList<TTableSubscription>;
    FOnInsertCallback: TSupabaseRealtimeCallback;
    FOnUpdateCallback: TSupabaseRealtimeCallback;
    FOnDeleteCallback: TSupabaseRealtimeCallback;
    FTableCallbacks: TDictionary<String, TSupabaseRealtimeCallback>;
    FLock: TCriticalSection;
    FPollIntervalMs: Integer;
    procedure PollTable(aSub: TTableSubscription);
    procedure FireEvent(aEvent: TSupabaseRealtimeEvent);
    procedure FireTableCallback(aTable: String; aEvent: TSupabaseRealtimeEvent);
  protected
    procedure Execute; override;
  public
    constructor Create(aBaseURL, aAPIKey, aToken: String;
      aSubscriptions: TObjectList<TTableSubscription>;
      aTableCallbacks: TDictionary<String, TSupabaseRealtimeCallback>;
      aLock: TCriticalSection;
      aPollIntervalMs: Integer);
    property OnInsertCallback: TSupabaseRealtimeCallback read FOnInsertCallback write FOnInsertCallback;
    property OnUpdateCallback: TSupabaseRealtimeCallback read FOnUpdateCallback write FOnUpdateCallback;
    property OnDeleteCallback: TSupabaseRealtimeCallback read FOnDeleteCallback write FOnDeleteCallback;
  end;

  TSimpleSupabaseRealtime = class(TInterfacedObject, iSimpleSupabaseRealtime)
  private
    FBaseURL: String;
    FAPIKey: String;
    FToken: String;
    FSubscriptions: TObjectList<TTableSubscription>;
    FTableCallbacks: TDictionary<String, TSupabaseRealtimeCallback>;
    FOnInsertCallback: TSupabaseRealtimeCallback;
    FOnUpdateCallback: TSupabaseRealtimeCallback;
    FOnDeleteCallback: TSupabaseRealtimeCallback;
    FListenerThread: TRealtimeListenerThread;
    FLock: TCriticalSection;
    FConnected: Boolean;
    FPollIntervalMs: Integer;
  public
    constructor Create(aBaseURL, aAPIKey: String; aPollIntervalMs: Integer = 2000);
    destructor Destroy; override;
    class function New(aBaseURL, aAPIKey: String; aPollIntervalMs: Integer = 2000): iSimpleSupabaseRealtime;
    function Subscribe(aTable: String): iSimpleSupabaseRealtime;
    function Unsubscribe(aTable: String): iSimpleSupabaseRealtime;
    function OnInsert(aCallback: TSupabaseRealtimeCallback): iSimpleSupabaseRealtime;
    function OnUpdate(aCallback: TSupabaseRealtimeCallback): iSimpleSupabaseRealtime;
    function OnDelete(aCallback: TSupabaseRealtimeCallback): iSimpleSupabaseRealtime;
    function OnChange(aTable: String; aCallback: TSupabaseRealtimeCallback): iSimpleSupabaseRealtime;
    function Connect: iSimpleSupabaseRealtime;
    function Disconnect: iSimpleSupabaseRealtime;
    function IsConnected: Boolean;
    function Token(aValue: String): iSimpleSupabaseRealtime;
    function PollInterval(aMs: Integer): iSimpleSupabaseRealtime;
  end;

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows;
{$ENDIF}

{ TRealtimeListenerThread }

constructor TRealtimeListenerThread.Create(aBaseURL, aAPIKey, aToken: String;
  aSubscriptions: TObjectList<TTableSubscription>;
  aTableCallbacks: TDictionary<String, TSupabaseRealtimeCallback>;
  aLock: TCriticalSection;
  aPollIntervalMs: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FBaseURL := aBaseURL;
  FAPIKey := aAPIKey;
  FToken := aToken;
  FSubscriptions := aSubscriptions;
  FTableCallbacks := aTableCallbacks;
  FLock := aLock;
  FPollIntervalMs := aPollIntervalMs;
end;

procedure TRealtimeListenerThread.Execute;
var
  LSnapshots: TList<TTableSubscription>;
  I: Integer;
  LSleepRemaining: Integer;
begin
  LSnapshots := TList<TTableSubscription>.Create;
  try
    while not Terminated do
    begin
      LSnapshots.Clear;
      FLock.Acquire;
      try
        for I := 0 to FSubscriptions.Count - 1 do
          LSnapshots.Add(FSubscriptions[I]);
      finally
        FLock.Release;
      end;

      for I := 0 to LSnapshots.Count - 1 do
      begin
        if Terminated then
          Break;
        try
          PollTable(LSnapshots[I]);
        except
          on E: Exception do
          begin
            {$IFDEF MSWINDOWS}
            OutputDebugString(PChar('[SimpleORM] Realtime polling error: ' + E.Message));
            {$ENDIF}
            {$IFDEF CONSOLE}
            Writeln('[SimpleORM] Realtime polling error: ', E.Message);
            {$ENDIF}
          end;
        end;
      end;

      LSleepRemaining := FPollIntervalMs;
      while (LSleepRemaining > 0) and (not Terminated) do
      begin
        Sleep(100);
        Dec(LSleepRemaining, 100);
      end;
    end;
  finally
    FreeAndNil(LSnapshots);
  end;
end;

procedure TRealtimeListenerThread.PollTable(aSub: TTableSubscription);
var
  LClient: THTTPClient;
  LResponse: IHTTPResponse;
  LURL: String;
  LJSONArray: TJSONArray;
  LJSONValue: TJSONValue;
  LParsed: TJSONValue;
  LEvent: TSupabaseRealtimeEvent;
  LId: String;
  LNewLastId: String;
  I: Integer;
begin
  LClient := THTTPClient.Create;
  try
    LClient.CustomHeaders['apikey'] := FAPIKey;
    if FToken <> '' then
      LClient.CustomHeaders['Authorization'] := 'Bearer ' + FToken
    else
      LClient.CustomHeaders['Authorization'] := 'Bearer ' + FAPIKey;

    LURL := FBaseURL + '/rest/v1/' + aSub.Table + '?order=id.desc&limit=10';
    if aSub.LastKnownId <> '' then
      LURL := LURL + '&id=gt.' + aSub.LastKnownId;

    LResponse := LClient.Get(LURL);
    if LResponse.StatusCode >= 400 then
      Exit;

    LParsed := TJSONObject.ParseJSONValue(LResponse.ContentAsString);
    if LParsed = nil then
      Exit;
    try
      if not (LParsed is TJSONArray) then
        Exit;

      LJSONArray := TJSONArray(LParsed);
      if LJSONArray.Count = 0 then
        Exit;

      LNewLastId := '';
      LJSONValue := LJSONArray.Items[0];
      if LJSONValue is TJSONObject then
      begin
        LNewLastId := TJSONObject(LJSONValue).GetValue<String>('id', '');
      end;

      // Iterate in reverse for chronological order (oldest first)
      for I := LJSONArray.Count - 1 downto 0 do
      begin
        LJSONValue := LJSONArray.Items[I];

        LEvent.Table := aSub.Table;
        LEvent.EventType := TSupabaseEventType.setInsert;
        LEvent.OldRecord := '';
        LEvent.NewRecord := LJSONValue.ToJSON;

        FireEvent(LEvent);
        FireTableCallback(aSub.Table, LEvent);
      end;

      if LNewLastId <> '' then
      begin
        FLock.Acquire;
        try
          aSub.LastKnownId := LNewLastId;
        finally
          FLock.Release;
        end;
      end;
    finally
      FreeAndNil(LParsed);
    end;
  finally
    FreeAndNil(LClient);
  end;
end;

procedure TRealtimeListenerThread.FireEvent(aEvent: TSupabaseRealtimeEvent);
var
  LCallback: TSupabaseRealtimeCallback;
begin
  case aEvent.EventType of
    TSupabaseEventType.setInsert:
    begin
      LCallback := FOnInsertCallback;
      if Assigned(LCallback) then
        TThread.Queue(nil,
          procedure
          begin
            LCallback(aEvent);
          end);
    end;
    TSupabaseEventType.setUpdate:
    begin
      LCallback := FOnUpdateCallback;
      if Assigned(LCallback) then
        TThread.Queue(nil,
          procedure
          begin
            LCallback(aEvent);
          end);
    end;
    TSupabaseEventType.setDelete:
    begin
      LCallback := FOnDeleteCallback;
      if Assigned(LCallback) then
        TThread.Queue(nil,
          procedure
          begin
            LCallback(aEvent);
          end);
    end;
  end;
end;

procedure TRealtimeListenerThread.FireTableCallback(aTable: String; aEvent: TSupabaseRealtimeEvent);
var
  LCallback: TSupabaseRealtimeCallback;
begin
  FLock.Acquire;
  try
    if not FTableCallbacks.TryGetValue(aTable, LCallback) then
      Exit;
  finally
    FLock.Release;
  end;

  if Assigned(LCallback) then
    TThread.Queue(nil,
      procedure
      begin
        LCallback(aEvent);
      end);
end;

{ TSimpleSupabaseRealtime }

constructor TSimpleSupabaseRealtime.Create(aBaseURL, aAPIKey: String; aPollIntervalMs: Integer);
begin
  inherited Create;
  FBaseURL := aBaseURL;
  FAPIKey := aAPIKey;
  FPollIntervalMs := aPollIntervalMs;
  FConnected := False;
  FLock := TCriticalSection.Create;
  FSubscriptions := TObjectList<TTableSubscription>.Create(True);
  FTableCallbacks := TDictionary<String, TSupabaseRealtimeCallback>.Create;
end;

destructor TSimpleSupabaseRealtime.Destroy;
begin
  Disconnect;
  FreeAndNil(FTableCallbacks);
  FreeAndNil(FSubscriptions);
  FreeAndNil(FLock);
  inherited;
end;

class function TSimpleSupabaseRealtime.New(aBaseURL, aAPIKey: String; aPollIntervalMs: Integer): iSimpleSupabaseRealtime;
begin
  Result := Self.Create(aBaseURL, aAPIKey, aPollIntervalMs);
end;

function TSimpleSupabaseRealtime.Subscribe(aTable: String): iSimpleSupabaseRealtime;
var
  LSub: TTableSubscription;
  I: Integer;
begin
  Result := Self;
  FLock.Acquire;
  try
    for I := 0 to FSubscriptions.Count - 1 do
    begin
      if SameText(FSubscriptions[I].Table, aTable) then
        Exit;
    end;

    LSub := TTableSubscription.Create;
    LSub.Table := aTable;
    LSub.LastKnownId := '';
    LSub.Callback := nil;

    if FTableCallbacks.ContainsKey(aTable) then
      LSub.Callback := FTableCallbacks[aTable];

    FSubscriptions.Add(LSub);
  finally
    FLock.Release;
  end;
end;

function TSimpleSupabaseRealtime.Unsubscribe(aTable: String): iSimpleSupabaseRealtime;
var
  I: Integer;
begin
  Result := Self;
  FLock.Acquire;
  try
    for I := FSubscriptions.Count - 1 downto 0 do
    begin
      if SameText(FSubscriptions[I].Table, aTable) then
      begin
        FSubscriptions.Delete(I);
        Break;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

function TSimpleSupabaseRealtime.OnInsert(aCallback: TSupabaseRealtimeCallback): iSimpleSupabaseRealtime;
begin
  Result := Self;
  FOnInsertCallback := aCallback;
  if Assigned(FListenerThread) then
    FListenerThread.OnInsertCallback := aCallback;
end;

function TSimpleSupabaseRealtime.OnUpdate(aCallback: TSupabaseRealtimeCallback): iSimpleSupabaseRealtime;
begin
  Result := Self;
  FOnUpdateCallback := aCallback;
  if Assigned(FListenerThread) then
    FListenerThread.OnUpdateCallback := aCallback;
end;

function TSimpleSupabaseRealtime.OnDelete(aCallback: TSupabaseRealtimeCallback): iSimpleSupabaseRealtime;
begin
  Result := Self;
  FOnDeleteCallback := aCallback;
  if Assigned(FListenerThread) then
    FListenerThread.OnDeleteCallback := aCallback;
end;

function TSimpleSupabaseRealtime.OnChange(aTable: String; aCallback: TSupabaseRealtimeCallback): iSimpleSupabaseRealtime;
var
  I: Integer;
begin
  Result := Self;
  FLock.Acquire;
  try
    FTableCallbacks.AddOrSetValue(aTable, aCallback);

    for I := 0 to FSubscriptions.Count - 1 do
    begin
      if SameText(FSubscriptions[I].Table, aTable) then
      begin
        FSubscriptions[I].Callback := aCallback;
        Break;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

function TSimpleSupabaseRealtime.Connect: iSimpleSupabaseRealtime;
begin
  Result := Self;
  if FConnected then
    Exit;

  FListenerThread := TRealtimeListenerThread.Create(
    FBaseURL, FAPIKey, FToken, FSubscriptions, FTableCallbacks, FLock, FPollIntervalMs);
  FListenerThread.OnInsertCallback := FOnInsertCallback;
  FListenerThread.OnUpdateCallback := FOnUpdateCallback;
  FListenerThread.OnDeleteCallback := FOnDeleteCallback;
  FListenerThread.Start;
  FConnected := True;
end;

function TSimpleSupabaseRealtime.Disconnect: iSimpleSupabaseRealtime;
begin
  Result := Self;
  if not FConnected then
    Exit;

  if Assigned(FListenerThread) then
  begin
    FListenerThread.Terminate;
    FListenerThread.WaitFor;
    FreeAndNil(FListenerThread);
  end;
  FConnected := False;
end;

function TSimpleSupabaseRealtime.IsConnected: Boolean;
begin
  Result := FConnected;
end;

function TSimpleSupabaseRealtime.Token(aValue: String): iSimpleSupabaseRealtime;
begin
  Result := Self;
  FToken := aValue;
end;

function TSimpleSupabaseRealtime.PollInterval(aMs: Integer): iSimpleSupabaseRealtime;
begin
  Result := Self;
  FPollIntervalMs := aMs;
end;

end.

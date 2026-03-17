unit SimpleEvents;

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TSimpleEventType = (seBeforeInsert, seAfterInsert, seBeforeUpdate, seAfterUpdate, seBeforeDelete, seAfterDelete);

  TSimpleEventCallback = reference to procedure(aEntity: TObject; aEventType: TSimpleEventType);

  TSimpleEventBus = class
  private
    class var FListeners: TList<TSimpleEventCallback>;
    class var FClassListeners: TObjectDictionary<TClass, TList<TSimpleEventCallback>>;
  public
    class procedure Subscribe(aCallback: TSimpleEventCallback); overload;
    class procedure Subscribe(aClass: TClass; aCallback: TSimpleEventCallback); overload;
    class procedure Notify(aEntity: TObject; aEventType: TSimpleEventType);
    class procedure Clear;
  end;

implementation

class procedure TSimpleEventBus.Subscribe(aCallback: TSimpleEventCallback);
begin
  if FListeners = nil then
    FListeners := TList<TSimpleEventCallback>.Create;
  FListeners.Add(aCallback);
end;

class procedure TSimpleEventBus.Subscribe(aClass: TClass; aCallback: TSimpleEventCallback);
var
  LList: TList<TSimpleEventCallback>;
begin
  if FClassListeners = nil then
    FClassListeners := TObjectDictionary<TClass, TList<TSimpleEventCallback>>.Create([doOwnsValues]);
  if not FClassListeners.TryGetValue(aClass, LList) then
  begin
    LList := TList<TSimpleEventCallback>.Create;
    FClassListeners.Add(aClass, LList);
  end;
  LList.Add(aCallback);
end;

class procedure TSimpleEventBus.Notify(aEntity: TObject; aEventType: TSimpleEventType);
var
  LCallback: TSimpleEventCallback;
  LList: TList<TSimpleEventCallback>;
begin
  // Global listeners
  if FListeners <> nil then
    for LCallback in FListeners do
      LCallback(aEntity, aEventType);

  // Class-specific listeners
  if (FClassListeners <> nil) and (aEntity <> nil) then
  begin
    if FClassListeners.TryGetValue(aEntity.ClassType, LList) then
      for LCallback in LList do
        LCallback(aEntity, aEventType);
  end;
end;

class procedure TSimpleEventBus.Clear;
begin
  FreeAndNil(FListeners);
  FreeAndNil(FClassListeners);
end;

initialization

finalization
  TSimpleEventBus.Clear;

end.

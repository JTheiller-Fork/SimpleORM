unit TestSimpleEvents;

interface

uses
  TestFramework,
  System.SysUtils,
  SimpleEvents;

type
  TDummyEntity = class
  private
    FName: String;
  public
    constructor Create;
    destructor Destroy; override;
    property Name: String read FName write FName;
  end;

  TAnotherEntity = class
  private
    FValue: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    property Value: Integer read FValue write FValue;
  end;

  TTestSimpleEventBus = class(TTestCase)
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSubscribe_GlobalListener_ReceivesNotify;
    procedure TestSubscribe_ClassSpecific_ReceivesNotify;
    procedure TestSubscribe_ClassSpecific_IgnoresOtherClass;
    procedure TestNotify_NoListeners_NoError;
    procedure TestNotify_NilEntity_GlobalOnly;
    procedure TestNotify_MultipleGlobalListeners_AllCalled;
    procedure TestNotify_EventTypePreserved;
    procedure TestClear_RemovesAllListeners;
    procedure TestSubscribe_GlobalAndClassSpecific_BothCalled;
    procedure TestNotify_BeforeInsert_CorrectType;
    procedure TestNotify_AfterInsert_CorrectType;
    procedure TestNotify_BeforeUpdate_CorrectType;
    procedure TestNotify_AfterUpdate_CorrectType;
    procedure TestNotify_BeforeDelete_CorrectType;
    procedure TestNotify_AfterDelete_CorrectType;
  end;

implementation

{ TDummyEntity }

constructor TDummyEntity.Create;
begin
  FName := '';
end;

destructor TDummyEntity.Destroy;
begin
  inherited;
end;

{ TAnotherEntity }

constructor TAnotherEntity.Create;
begin
  FValue := 0;
end;

destructor TAnotherEntity.Destroy;
begin
  inherited;
end;

{ TTestSimpleEventBus }

procedure TTestSimpleEventBus.SetUp;
begin
  inherited;
  TSimpleEventBus.Clear;
end;

procedure TTestSimpleEventBus.TearDown;
begin
  TSimpleEventBus.Clear;
  inherited;
end;

procedure TTestSimpleEventBus.TestSubscribe_GlobalListener_ReceivesNotify;
var
  LCalled: Boolean;
  LEntity: TDummyEntity;
begin
  LCalled := False;
  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LCalled := True;
    end
  );

  LEntity := TDummyEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seBeforeInsert);
    CheckTrue(LCalled, 'Global listener should be called on Notify');
  finally
    FreeAndNil(LEntity);
  end;
end;

procedure TTestSimpleEventBus.TestSubscribe_ClassSpecific_ReceivesNotify;
var
  LCalled: Boolean;
  LEntity: TDummyEntity;
begin
  LCalled := False;
  TSimpleEventBus.Subscribe(TDummyEntity,
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LCalled := True;
    end
  );

  LEntity := TDummyEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seAfterInsert);
    CheckTrue(LCalled, 'Class-specific listener should be called for matching class');
  finally
    FreeAndNil(LEntity);
  end;
end;

procedure TTestSimpleEventBus.TestSubscribe_ClassSpecific_IgnoresOtherClass;
var
  LCalled: Boolean;
  LEntity: TAnotherEntity;
begin
  LCalled := False;
  TSimpleEventBus.Subscribe(TDummyEntity,
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LCalled := True;
    end
  );

  LEntity := TAnotherEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seBeforeInsert);
    CheckFalse(LCalled, 'Class-specific listener should NOT be called for different class');
  finally
    FreeAndNil(LEntity);
  end;
end;

procedure TTestSimpleEventBus.TestNotify_NoListeners_NoError;
var
  LEntity: TDummyEntity;
begin
  LEntity := TDummyEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seBeforeInsert);
    CheckTrue(True, 'Notify with no listeners should not raise exception');
  finally
    FreeAndNil(LEntity);
  end;
end;

procedure TTestSimpleEventBus.TestNotify_NilEntity_GlobalOnly;
var
  LCalled: Boolean;
begin
  LCalled := False;
  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LCalled := True;
    end
  );

  TSimpleEventBus.Notify(nil, seBeforeInsert);
  CheckTrue(LCalled, 'Global listener should be called even with nil entity');
end;

procedure TTestSimpleEventBus.TestNotify_MultipleGlobalListeners_AllCalled;
var
  LCount: Integer;
  LEntity: TDummyEntity;
begin
  LCount := 0;
  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      Inc(LCount);
    end
  );
  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      Inc(LCount);
    end
  );
  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      Inc(LCount);
    end
  );

  LEntity := TDummyEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seBeforeUpdate);
    CheckEquals(3, LCount, 'All three global listeners should be called');
  finally
    FreeAndNil(LEntity);
  end;
end;

procedure TTestSimpleEventBus.TestNotify_EventTypePreserved;
var
  LReceivedType: TSimpleEventType;
  LEntity: TDummyEntity;
begin
  LReceivedType := seBeforeInsert;
  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LReceivedType := aEventType;
    end
  );

  LEntity := TDummyEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seAfterDelete);
    CheckTrue(LReceivedType = seAfterDelete, 'Event type should be preserved in notification');
  finally
    FreeAndNil(LEntity);
  end;
end;

procedure TTestSimpleEventBus.TestClear_RemovesAllListeners;
var
  LCalled: Boolean;
  LEntity: TDummyEntity;
begin
  LCalled := False;
  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LCalled := True;
    end
  );
  TSimpleEventBus.Subscribe(TDummyEntity,
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LCalled := True;
    end
  );

  TSimpleEventBus.Clear;

  LEntity := TDummyEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seBeforeInsert);
    CheckFalse(LCalled, 'After Clear, no listeners should be called');
  finally
    FreeAndNil(LEntity);
  end;
end;

procedure TTestSimpleEventBus.TestSubscribe_GlobalAndClassSpecific_BothCalled;
var
  LGlobalCalled: Boolean;
  LClassCalled: Boolean;
  LEntity: TDummyEntity;
begin
  LGlobalCalled := False;
  LClassCalled := False;

  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LGlobalCalled := True;
    end
  );
  TSimpleEventBus.Subscribe(TDummyEntity,
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LClassCalled := True;
    end
  );

  LEntity := TDummyEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seBeforeInsert);
    CheckTrue(LGlobalCalled, 'Global listener should be called');
    CheckTrue(LClassCalled, 'Class-specific listener should be called');
  finally
    FreeAndNil(LEntity);
  end;
end;

procedure TTestSimpleEventBus.TestNotify_BeforeInsert_CorrectType;
var
  LReceivedType: TSimpleEventType;
  LEntity: TDummyEntity;
begin
  LReceivedType := seAfterDelete;
  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LReceivedType := aEventType;
    end
  );
  LEntity := TDummyEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seBeforeInsert);
    CheckTrue(LReceivedType = seBeforeInsert, 'Should receive seBeforeInsert');
  finally
    FreeAndNil(LEntity);
  end;
end;

procedure TTestSimpleEventBus.TestNotify_AfterInsert_CorrectType;
var
  LReceivedType: TSimpleEventType;
  LEntity: TDummyEntity;
begin
  LReceivedType := seBeforeInsert;
  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LReceivedType := aEventType;
    end
  );
  LEntity := TDummyEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seAfterInsert);
    CheckTrue(LReceivedType = seAfterInsert, 'Should receive seAfterInsert');
  finally
    FreeAndNil(LEntity);
  end;
end;

procedure TTestSimpleEventBus.TestNotify_BeforeUpdate_CorrectType;
var
  LReceivedType: TSimpleEventType;
  LEntity: TDummyEntity;
begin
  LReceivedType := seBeforeInsert;
  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LReceivedType := aEventType;
    end
  );
  LEntity := TDummyEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seBeforeUpdate);
    CheckTrue(LReceivedType = seBeforeUpdate, 'Should receive seBeforeUpdate');
  finally
    FreeAndNil(LEntity);
  end;
end;

procedure TTestSimpleEventBus.TestNotify_AfterUpdate_CorrectType;
var
  LReceivedType: TSimpleEventType;
  LEntity: TDummyEntity;
begin
  LReceivedType := seBeforeInsert;
  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LReceivedType := aEventType;
    end
  );
  LEntity := TDummyEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seAfterUpdate);
    CheckTrue(LReceivedType = seAfterUpdate, 'Should receive seAfterUpdate');
  finally
    FreeAndNil(LEntity);
  end;
end;

procedure TTestSimpleEventBus.TestNotify_BeforeDelete_CorrectType;
var
  LReceivedType: TSimpleEventType;
  LEntity: TDummyEntity;
begin
  LReceivedType := seBeforeInsert;
  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LReceivedType := aEventType;
    end
  );
  LEntity := TDummyEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seBeforeDelete);
    CheckTrue(LReceivedType = seBeforeDelete, 'Should receive seBeforeDelete');
  finally
    FreeAndNil(LEntity);
  end;
end;

procedure TTestSimpleEventBus.TestNotify_AfterDelete_CorrectType;
var
  LReceivedType: TSimpleEventType;
  LEntity: TDummyEntity;
begin
  LReceivedType := seBeforeInsert;
  TSimpleEventBus.Subscribe(
    procedure(aEntity: TObject; aEventType: TSimpleEventType)
    begin
      LReceivedType := aEventType;
    end
  );
  LEntity := TDummyEntity.Create;
  try
    TSimpleEventBus.Notify(LEntity, seAfterDelete);
    CheckTrue(LReceivedType = seAfterDelete, 'Should receive seAfterDelete');
  finally
    FreeAndNil(LEntity);
  end;
end;

initialization
  RegisterTest('Events', TTestSimpleEventBus.Suite);

end.

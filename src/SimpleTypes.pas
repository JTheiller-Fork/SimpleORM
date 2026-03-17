unit SimpleTypes;

interface

uses
  System.SysUtils;

type
  TSQLType = (Firebird, MySQL, SQLite, Oracle);
  TRuleAction = (raBeforeInsert, raAfterInsert, raBeforeUpdate, raAfterUpdate, raBeforeDelete, raAfterDelete);
  TSkillRunAt = (srBeforeInsert, srAfterInsert, srBeforeUpdate, srAfterUpdate, srBeforeDelete, srAfterDelete);
  TSkillRunMode = (srmNormal, srmOnError);
  TAgentOperation = (aoAfterInsert, aoAfterUpdate, aoAfterDelete);
  TAgentCondition = reference to function(aEntity: TObject): Boolean;

  TSupabaseEventType = (setInsert, setUpdate, setDelete);

  TSupabaseRealtimeEvent = record
    Table: String;
    EventType: TSupabaseEventType;
    OldRecord: String;
    NewRecord: String;
  end;

  TSupabaseRealtimeCallback = reference to procedure(aEvent: TSupabaseRealtimeEvent);

  TSimpleErrorCallback = reference to procedure(aEntity: TObject; aException: Exception);

  TMigrationFormat = (mfCSV, mfJSON);

  TMigrationStatus = (msInProgress, msCompleted, msFailed);

  TMigrationError = record
    SourceTable: String;
    RecordIndex: Integer;
    FieldName: String;
    ErrorMessage: String;
    OriginalValue: Variant;
  end;

  TFieldTransformFunc = reference to function(aValue: Variant): Variant;
  TSimpleMigrationProgress = reference to procedure(aTable: String; aCurrent, aTotal: Integer);
  TSimpleMigrationErrorCallback = reference to procedure(aError: TMigrationError; var aSkip: Boolean);

implementation

end.

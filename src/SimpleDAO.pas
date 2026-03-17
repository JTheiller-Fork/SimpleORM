unit SimpleDAO;

interface

uses
    SimpleInterface,
    SimpleLogger,
    SimpleTypes,
    SimpleSkill,
    System.RTTI,
    System.Generics.Collections,
    System.Classes,
    Data.DB,
{$IFNDEF CONSOLE}
{$IFDEF FMX}
    FMX.Forms,
{$ELSE}
    Vcl.Forms,
{$ENDIF}
{$ENDIF}
    SimpleDAOSQLAttribute,
    System.Threading;

Type
    TSimpleDAO<T: class, constructor> = class(TInterfacedObject, iSimpleDAO<T>)
    private
        FQuery: iSimpleQuery;
        FDataSource: TDataSource;
        FSQLAttribute: iSimpleDAOSQLAttribute<T>;
{$IFNDEF CONSOLE}
        FForm: TForm;
{$ENDIF}
        FList: TObjectList<T>;
        FLogger: iSimpleQueryLogger;
        FOnBeforeInsert: TSimpleCallback;
        FOnAfterInsert: TSimpleCallback;
        FOnBeforeUpdate: TSimpleCallback;
        FOnAfterUpdate: TSimpleCallback;
        FOnBeforeDelete: TSimpleCallback;
        FOnAfterDelete: TSimpleCallback;
        FOnError: TSimpleErrorCallback;
        FScopes: TDictionary<String, String>;
        FActiveScopes: TList<String>;
        FRawSQL: String;
        FRawParams: TDictionary<String, Variant>;
        FCacheEnabled: Boolean;
        FCache: TDictionary<String, T>;
        FAIClient: iSimpleAIClient;
        FSkillRunner: TSimpleSkillRunner;
        FAgent: iSimpleAgent;
        function FillParameter(aInstance: T): iSimpleDAO<T>; overload;
        function FillParameter(aInstance: T; aId: Variant)
          : iSimpleDAO<T>; overload;
        procedure OnDataChange(Sender: TObject; Field: TField);
        procedure LoadRelationships(aEntity: T);
        procedure ApplyScopes;
        procedure ExecuteCascadeDelete(aValue: T);
    public
        constructor Create(aQuery: iSimpleQuery);
        destructor Destroy; override;
        class function New(aQuery: iSimpleQuery): iSimpleDAO<T>; overload;
        function DataSource(aDataSource: TDataSource): iSimpleDAO<T>;
        function Insert(aValue: T): iSimpleDAO<T>; overload;
        function Update(aValue: T): iSimpleDAO<T>; overload;
        function Delete(aValue: T): iSimpleDAO<T>; overload;
        function ForceDelete(aValue: T): iSimpleDAO<T>;
        function Delete(aField: String; aValue: String): iSimpleDAO<T>;
          overload;
        function LastID: iSimpleDAO<T>;
        function LastRecord: iSimpleDAO<T>;
{$IFNDEF CONSOLE}
        function Insert: iSimpleDAO<T>; overload;
        function Update: iSimpleDAO<T>; overload;
        function Delete: iSimpleDAO<T>; overload;
{$ENDIF}
        function Find(aBindList: Boolean = True): iSimpleDAO<T>; overload;
        function Find(var aList: TObjectList<T>): iSimpleDAO<T>; overload;
        function Find(aId: Integer): T; overload;
        function Find(aKey: String; aValue: Variant): iSimpleDAO<T>; overload;
        function InsertBatch(aList: TObjectList<T>): iSimpleDAO<T>;
        function UpdateBatch(aList: TObjectList<T>): iSimpleDAO<T>;
        function DeleteBatch(aList: TObjectList<T>): iSimpleDAO<T>;
        function BulkInsert(aList: TObjectList<T>): iSimpleDAO<T>;
        function Count: Integer;
        function Sum(const aField: String): Double;
        function Min(const aField: String): Double;
        function Max(const aField: String): Double;
        function Avg(const aField: String): Double;
        function Exists(const aField: String; aValue: Variant): Boolean;
        function SQL: iSimpleDAOSQLAttribute<T>;
        function RegisterScope(const aName, aWhere: String): iSimpleDAO<T>;
        function Scope(const aName: String): iSimpleDAO<T>;
        function ClearScopes: iSimpleDAO<T>;
        function FindOrCreate(const aField: String; aValue: Variant; aEntity: T): T;
        function UpdateOrCreate(const aField: String; aValue: Variant; aEntity: T): T;
        function Logger(aLogger: iSimpleQueryLogger): iSimpleDAO<T>;
        function AIClient(aValue: iSimpleAIClient): iSimpleDAO<T>;
        function Skill(aSkill: iSimpleSkill): iSimpleDAO<T>;
        function Agent(aAgent: iSimpleAgent): iSimpleDAO<T>;
        function OnBeforeInsert(aCallback: TSimpleCallback): iSimpleDAO<T>;
        function OnAfterInsert(aCallback: TSimpleCallback): iSimpleDAO<T>;
        function OnBeforeUpdate(aCallback: TSimpleCallback): iSimpleDAO<T>;
        function OnAfterUpdate(aCallback: TSimpleCallback): iSimpleDAO<T>;
        function OnBeforeDelete(aCallback: TSimpleCallback): iSimpleDAO<T>;
        function OnAfterDelete(aCallback: TSimpleCallback): iSimpleDAO<T>;
        function OnError(aCallback: TSimpleErrorCallback): iSimpleDAO<T>;
        function RawSQL(const aSQL: String): iSimpleDAO<T>;
        function RawSQLWithParams(const aSQL: String; const aParamNames: array of String; const aParamValues: array of Variant): iSimpleDAO<T>;
        function FindRaw: TObjectList<T>;
        function FindAs<R: class, constructor>(var aList: TObjectList<R>): iSimpleDAO<T>;
        function ExecRawSQL(const aSQL: String): iSimpleDAO<T>;
        function Ask(const aQuestion: String): TDataSet;
        function EnableCache: iSimpleDAO<T>;
        function DisableCache: iSimpleDAO<T>;
        function ClearCache: iSimpleDAO<T>;
{$IFNDEF CONSOLE}
        function BindForm(aForm: TForm): iSimpleDAO<T>;
{$ENDIF}
    end;

implementation

uses
    System.SysUtils,
    System.Diagnostics,
    SimpleAttributes,
    System.TypInfo,
    SimpleRTTI,
    SimpleRTTIHelper,
    SimpleSQL,
    SimpleProxy,
    SimpleAIProcessor,
    SimpleAIAttributes,
    SimpleRules,
    SimpleAgent,
    SimpleEvents,
    SimpleNLQuery,
    System.Variants;
{ TGenericDAO }
{$IFNDEF CONSOLE}

function TSimpleDAO<T>.BindForm(aForm: TForm): iSimpleDAO<T>;
begin
    Result := Self;
    FForm := aForm;
end;

{$ENDIF}

constructor TSimpleDAO<T>.Create(aQuery: iSimpleQuery);
begin
    FQuery := aQuery;
    FSQLAttribute := TSimpleDAOSQLAttribute<T>.New(Self);
    FList := TObjectList<T>.Create;
    FScopes := TDictionary<String, String>.Create;
    FActiveScopes := TList<String>.Create;
    FRawParams := TDictionary<String, Variant>.Create;
    FCacheEnabled := False;
    FCache := TDictionary<String, T>.Create;
    FSkillRunner := TSimpleSkillRunner.New;
end;

function TSimpleDAO<T>.DataSource(aDataSource: TDataSource): iSimpleDAO<T>;
begin
    Result := Self;
    FDataSource := aDataSource;
    FDataSource.DataSet := FQuery.DataSet;
    FDataSource.OnDataChange := OnDataChange;
end;

function TSimpleDAO<T>.Delete(aValue: T): iSimpleDAO<T>;
var
    aSQL: String;
    SW: TStopwatch;
    LRuleEngine: TSimpleRuleEngine;
    LSkillContext: iSimpleSkillContext;
    LTableName: String;
begin
    Result := Self;
    if Assigned(FOnBeforeDelete) then
      FOnBeforeDelete(aValue);
    TSimpleEventBus.Notify(aValue, seBeforeDelete);

    // 1. Rules (Before)
    LRuleEngine := TSimpleRuleEngine.New(FAIClient);
    try
      LRuleEngine.Evaluate(aValue, raBeforeDelete);
    finally
      FreeAndNil(LRuleEngine);
    end;

    // 2. Skills (Before)
    TSimpleRTTI<T>.New(aValue).TableName(LTableName);
    LSkillContext := TSimpleSkillContext.New(FQuery, FAIClient, FLogger, LTableName, 'DELETE');
    FSkillRunner.RunBefore(aValue, LSkillContext, srBeforeDelete);

    try
      // 3. SQL Execution
      ExecuteCascadeDelete(aValue);
      TSimpleSQL<T>.New(aValue).Delete(aSQL);
      FQuery.SQL.Clear;
      FQuery.SQL.Add(aSQL);
      Self.FillParameter(aValue);
      SW := TStopwatch.StartNew;
      FQuery.ExecSQL;
      SW.Stop;
      if Assigned(FLogger) then
        FLogger.Log(aSQL, FQuery.Params, SW.ElapsedMilliseconds);
      if FCacheEnabled then
        FCache.Clear;

      // 4. Skills (After)
      FSkillRunner.RunAfter(aValue, LSkillContext, srAfterDelete);

      // 5. Agent (React)
      if FAgent <> nil then
        FAgent.React(aValue, aoAfterDelete);

      if Assigned(FOnAfterDelete) then
        FOnAfterDelete(aValue);
      TSimpleEventBus.Notify(aValue, seAfterDelete);
    except
      on E: Exception do
      begin
        LSkillContext := TSimpleSkillContext.New(FQuery, FAIClient, FLogger, LTableName, 'DELETE', E.Message);
        FSkillRunner.RunOnError(aValue, LSkillContext);
        if Assigned(FOnError) then
          FOnError(aValue, E);
        raise;
      end;
    end;
end;
{$IFNDEF CONSOLE}

function TSimpleDAO<T>.Delete: iSimpleDAO<T>;
var
    aSQL: String;
    Entity: T;
begin
    Result := Self;
    Entity := T.Create;
    try
        TSimpleSQL<T>.New(Entity).Delete(aSQL);
        FQuery.SQL.Clear;
        FQuery.SQL.Add(aSQL);
        TSimpleRTTI<T>.New(nil).BindFormToClass(FForm, Entity);
        Self.FillParameter(Entity);
        FQuery.ExecSQL;
    finally
        FreeAndNil(Entity);
    end;
end;
{$ENDIF}

function TSimpleDAO<T>.ForceDelete(aValue: T): iSimpleDAO<T>;
var
    aSQL, aClassName, aWhere: String;
    SW: TStopwatch;
begin
    Result := Self;
    if Assigned(FOnBeforeDelete) then
      FOnBeforeDelete(aValue);
    ExecuteCascadeDelete(aValue);
    TSimpleRTTI<T>.New(aValue)
      .TableName(aClassName)
      .Where(aWhere);
    aSQL := 'DELETE FROM ' + aClassName + ' WHERE ' + aWhere;
    FQuery.SQL.Clear;
    FQuery.SQL.Add(aSQL);
    Self.FillParameter(aValue);
    SW := TStopwatch.StartNew;
    FQuery.ExecSQL;
    SW.Stop;
    if Assigned(FLogger) then
      FLogger.Log(aSQL, FQuery.Params, SW.ElapsedMilliseconds);
    if FCacheEnabled then
      FCache.Clear;
    if Assigned(FOnAfterDelete) then
      FOnAfterDelete(aValue);
end;

function TSimpleDAO<T>.Delete(aField, aValue: String): iSimpleDAO<T>;
var
    aTableName: string;
    Entity: T;
begin
    Result := Self;
    Entity := T.Create;
    try
        TSimpleRTTI<T>.New(Entity).TableName(aTableName);
        FQuery.SQL.Clear;
        FQuery.SQL.Add('DELETE FROM ' + aTableName + ' WHERE ' + aField + ' = :pValue');
        FQuery.Params.ParamByName('pValue').Value := aValue;
        FQuery.ExecSQL;
    finally
        FreeAndNil(Entity);
    end;
end;

destructor TSimpleDAO<T>.Destroy;
begin
    FreeAndNil(FList);
    FreeAndNil(FScopes);
    FreeAndNil(FActiveScopes);
    FreeAndNil(FRawParams);
    FreeAndNil(FCache);
    FreeAndNil(FSkillRunner);
    inherited;
end;

function TSimpleDAO<T>.Find(aBindList: Boolean = True): iSimpleDAO<T>;
var
    aSQL: String;
    I: Integer;
    SW: TStopwatch;
begin
    Result := Self;
    ApplyScopes;
    TSimpleSQL<T>.New(nil).Fields(FSQLAttribute.Fields).Join(FSQLAttribute.Join)
      .Where(FSQLAttribute.Where).GroupBy(FSQLAttribute.GroupBy)
      .OrderBy(FSQLAttribute.OrderBy)
      .Skip(FSQLAttribute.GetSkip)
      .Take(FSQLAttribute.GetTake)
      .DatabaseType(FQuery.SQLType)
      .Select(aSQL);
    FQuery.DataSet.DisableControls;
    try
      SW := TStopwatch.StartNew;
      FQuery.Open(aSQL);
      SW.Stop;
      if Assigned(FLogger) then
        FLogger.Log(aSQL, FQuery.Params, SW.ElapsedMilliseconds);
      if aBindList then
      begin
          TSimpleRTTI<T>.New(nil).DataSetToEntityList(FQuery.DataSet, FList);
          for I := 0 to FList.Count - 1 do
              LoadRelationships(FList[I]);
      end;
      FSQLAttribute.Clear;
    finally
      FQuery.DataSet.EnableControls;
    end;
end;

function TSimpleDAO<T>.Find(aId: Integer): T;
var
    aSQL: String;
    LCacheKey: String;
begin
    if FCacheEnabled then
    begin
      LCacheKey := IntToStr(aId);
      if FCache.ContainsKey(LCacheKey) then
        Exit(FCache[LCacheKey]);
    end;
    Result := T.Create;
    TSimpleSQL<T>.New(nil).SelectId(aSQL);
    FQuery.SQL.Clear;
    FQuery.SQL.Add(aSQL);
    Self.FillParameter(Result, aId);
    FQuery.Open;
    TSimpleRTTI<T>.New(nil).DataSetToEntity(FQuery.DataSet, Result);
    LoadRelationships(Result);
    if FCacheEnabled then
      FCache.AddOrSetValue(IntToStr(aId), Result);
end;
{$IFNDEF CONSOLE}

function TSimpleDAO<T>.Insert: iSimpleDAO<T>;
var
    aSQL: String;
    Entity: T;
begin
    Result := Self;
    Entity := T.Create;
    try
        TSimpleSQL<T>.New(Entity).Insert(aSQL);
        FQuery.SQL.Clear;
        FQuery.SQL.Add(aSQL);
        TSimpleRTTI<T>.New(nil).BindFormToClass(FForm, Entity);
        Self.FillParameter(Entity);
        FQuery.ExecSQL;
    finally
        FreeAndNil(Entity);
    end;
end;

{$ENDIF}

function TSimpleDAO<T>.LastID: iSimpleDAO<T>;
var
    aSQL: String;
begin
    Result := Self;
    TSimpleSQL<T>.New(nil).LastID(aSQL);
    FQuery.Open(aSQL);
end;

function TSimpleDAO<T>.LastRecord: iSimpleDAO<T>;
var
    aSQL: String;
begin
    Result := Self;
    TSimpleSQL<T>.New(nil).LastRecord(aSQL);
    FQuery.Open(aSQL);
end;

function TSimpleDAO<T>.Find(var aList: TObjectList<T>): iSimpleDAO<T>;
var
    aSQL: String;
    I: Integer;
    SW: TStopwatch;
begin
    Result := Self;
    ApplyScopes;
    TSimpleSQL<T>.New(nil).Fields(FSQLAttribute.Fields).Join(FSQLAttribute.Join)
      .Where(FSQLAttribute.Where).GroupBy(FSQLAttribute.GroupBy)
      .OrderBy(FSQLAttribute.OrderBy)
      .Skip(FSQLAttribute.GetSkip)
      .Take(FSQLAttribute.GetTake)
      .DatabaseType(FQuery.SQLType)
      .Select(aSQL);
    SW := TStopwatch.StartNew;
    FQuery.Open(aSQL);
    SW.Stop;
    if Assigned(FLogger) then
      FLogger.Log(aSQL, FQuery.Params, SW.ElapsedMilliseconds);
    TSimpleRTTI<T>.New(nil).DataSetToEntityList(FQuery.DataSet, aList);
    for I := 0 to aList.Count - 1 do
        LoadRelationships(aList[I]);
    FSQLAttribute.Clear;
end;

function TSimpleDAO<T>.Insert(aValue: T): iSimpleDAO<T>;
var
    aSQL: String;
    SW: TStopwatch;
    LAIProcessor: TSimpleAIProcessor;
    LRuleEngine: TSimpleRuleEngine;
    LSkillContext: iSimpleSkillContext;
    LTableName: String;
begin
    Result := Self;
    if Assigned(FOnBeforeInsert) then
      FOnBeforeInsert(aValue);
    TSimpleEventBus.Notify(aValue, seBeforeInsert);

    // 1. Rules (Before)
    LRuleEngine := TSimpleRuleEngine.New(FAIClient);
    try
      LRuleEngine.Evaluate(aValue, raBeforeInsert);
    finally
      FreeAndNil(LRuleEngine);
    end;

    // 2. AI Attributes
    if FAIClient <> nil then
    begin
      LAIProcessor := TSimpleAIProcessor.New(FAIClient);
      try
        LAIProcessor.Process(aValue);
      finally
        FreeAndNil(LAIProcessor);
      end;
    end;

    // 3. Skills (Before)
    TSimpleRTTI<T>.New(aValue).TableName(LTableName);
    LSkillContext := TSimpleSkillContext.New(FQuery, FAIClient, FLogger, LTableName, 'INSERT');
    FSkillRunner.RunBefore(aValue, LSkillContext, srBeforeInsert);

    try
      // 4. SQL Execution
      TSimpleSQL<T>.New(aValue).Insert(aSQL);
      FQuery.SQL.Clear;
      FQuery.SQL.Add(aSQL);
      Self.FillParameter(aValue);
      SW := TStopwatch.StartNew;
      FQuery.ExecSQL;
      SW.Stop;
      if Assigned(FLogger) then
        FLogger.Log(aSQL, FQuery.Params, SW.ElapsedMilliseconds);
      if FCacheEnabled then
        FCache.Clear;

      // 5. Skills (After)
      FSkillRunner.RunAfter(aValue, LSkillContext, srAfterInsert);

      // 6. Agent (React)
      if FAgent <> nil then
        FAgent.React(aValue, aoAfterInsert);

      if Assigned(FOnAfterInsert) then
        FOnAfterInsert(aValue);
      TSimpleEventBus.Notify(aValue, seAfterInsert);
    except
      on E: Exception do
      begin
        LSkillContext := TSimpleSkillContext.New(FQuery, FAIClient, FLogger, LTableName, 'INSERT', E.Message);
        FSkillRunner.RunOnError(aValue, LSkillContext);
        if Assigned(FOnError) then
          FOnError(aValue, E);
        raise;
      end;
    end;
end;

class function TSimpleDAO<T>.New(aQuery: iSimpleQuery): iSimpleDAO<T>;
begin
    Result := Self.Create(aQuery);
end;

procedure TSimpleDAO<T>.OnDataChange(Sender: TObject; Field: TField);
begin
    if (FList.Count > 0) and (FDataSource.DataSet.RecNo - 1 <= FList.Count) then
    begin
{$IFNDEF CONSOLE}
        if Assigned(FForm) then
            TSimpleRTTI<T>.New(nil).BindClassToForm(FForm,
              FList[FDataSource.DataSet.RecNo - 1]);
{$ENDIF}
    end;
end;

function TSimpleDAO<T>.SQL: iSimpleDAOSQLAttribute<T>;
begin
    Result := FSQLAttribute;
end;

function TSimpleDAO<T>.Logger(aLogger: iSimpleQueryLogger): iSimpleDAO<T>;
begin
    Result := Self;
    FLogger := aLogger;
end;

function TSimpleDAO<T>.AIClient(aValue: iSimpleAIClient): iSimpleDAO<T>;
begin
    Result := Self;
    FAIClient := aValue;
end;

function TSimpleDAO<T>.Skill(aSkill: iSimpleSkill): iSimpleDAO<T>;
begin
    Result := Self;
    FSkillRunner.Add(aSkill);
end;

function TSimpleDAO<T>.Agent(aAgent: iSimpleAgent): iSimpleDAO<T>;
begin
    Result := Self;
    FAgent := aAgent;
end;
{$IFNDEF CONSOLE}

function TSimpleDAO<T>.Update: iSimpleDAO<T>;
var
    aSQL: String;
    Entity: T;
begin
    Result := Self;
    Entity := T.Create;
    try
        TSimpleSQL<T>.New(Entity).Update(aSQL);
        FQuery.SQL.Clear;
        FQuery.SQL.Add(aSQL);
        TSimpleRTTI<T>.New(nil).BindFormToClass(FForm, Entity);
        Self.FillParameter(Entity);
        FQuery.ExecSQL;
    finally
        FreeAndNil(Entity)
    end;
end;
{$ENDIF}

function TSimpleDAO<T>.Update(aValue: T): iSimpleDAO<T>;
var
    aSQL: String;
    SW: TStopwatch;
    LAIProcessor: TSimpleAIProcessor;
    LRuleEngine: TSimpleRuleEngine;
    LSkillContext: iSimpleSkillContext;
    LTableName: String;
begin
    Result := Self;
    if Assigned(FOnBeforeUpdate) then
      FOnBeforeUpdate(aValue);
    TSimpleEventBus.Notify(aValue, seBeforeUpdate);

    // 1. Rules (Before)
    LRuleEngine := TSimpleRuleEngine.New(FAIClient);
    try
      LRuleEngine.Evaluate(aValue, raBeforeUpdate);
    finally
      FreeAndNil(LRuleEngine);
    end;

    // 2. AI Attributes
    if FAIClient <> nil then
    begin
      LAIProcessor := TSimpleAIProcessor.New(FAIClient);
      try
        LAIProcessor.Process(aValue);
      finally
        FreeAndNil(LAIProcessor);
      end;
    end;

    // 3. Skills (Before)
    TSimpleRTTI<T>.New(aValue).TableName(LTableName);
    LSkillContext := TSimpleSkillContext.New(FQuery, FAIClient, FLogger, LTableName, 'UPDATE');
    FSkillRunner.RunBefore(aValue, LSkillContext, srBeforeUpdate);

    try
      // 4. SQL Execution
      TSimpleSQL<T>.New(aValue).Update(aSQL);
      FQuery.SQL.Clear;
      FQuery.SQL.Add(aSQL);
      Self.FillParameter(aValue);
      SW := TStopwatch.StartNew;
      FQuery.ExecSQL;
      SW.Stop;
      if Assigned(FLogger) then
        FLogger.Log(aSQL, FQuery.Params, SW.ElapsedMilliseconds);
      if FCacheEnabled then
        FCache.Clear;

      // 5. Skills (After)
      FSkillRunner.RunAfter(aValue, LSkillContext, srAfterUpdate);

      // 6. Agent (React)
      if FAgent <> nil then
        FAgent.React(aValue, aoAfterUpdate);

      if Assigned(FOnAfterUpdate) then
        FOnAfterUpdate(aValue);
      TSimpleEventBus.Notify(aValue, seAfterUpdate);
    except
      on E: Exception do
      begin
        LSkillContext := TSimpleSkillContext.New(FQuery, FAIClient, FLogger, LTableName, 'UPDATE', E.Message);
        FSkillRunner.RunOnError(aValue, LSkillContext);
        if Assigned(FOnError) then
          FOnError(aValue, E);
        raise;
      end;
    end;
end;

function TSimpleDAO<T>.FillParameter(aInstance: T): iSimpleDAO<T>;
var
    Key: String;
    DictionaryFields: TDictionary<String, Variant>;
    DictionaryTypeFields: TDictionary<String, TFieldType>;
    FieldType: TFieldType;
begin
    DictionaryFields := TDictionary<String, Variant>.Create;
    DictionaryTypeFields := TDictionary<String, TFieldType>.Create;
    TSimpleRTTI<T>.New(aInstance).DictionaryFields(DictionaryFields);
    TSimpleRTTI<T>.New(aInstance).DictionaryTypeFields(DictionaryTypeFields);
    try
        for Key in DictionaryFields.Keys do
        begin
            if FQuery.Params.FindParam(Key) <> nil then
            begin
                if DictionaryTypeFields.TryGetValue(Key, FieldType ) then
                  FQuery.Params.ParamByName(Key).DataType := FieldType;
                if VarIsStr(DictionaryFields.Items[Key]) and
                   (Length(VarToStr(DictionaryFields.Items[Key])) > 4000) then
                  FQuery.Params.ParamByName(Key).AsMemo := VarToStr(DictionaryFields.Items[Key])
                else
                  FQuery.Params.ParamByName(Key).Value := DictionaryFields.Items[Key];
            end;
        end;
    finally
        FreeAndNil(DictionaryFields);
        FreeAndNil(DictionaryTypeFields);
    end;
end;

function TSimpleDAO<T>.FillParameter(aInstance: T; aId: Variant): iSimpleDAO<T>;
var
    I: Integer;
    ListFields: TList<String>;
begin
    ListFields := TList<String>.Create;
    TSimpleRTTI<T>.New(aInstance).ListFields(ListFields);
    try
        for I := 0 to Pred(ListFields.Count) do
        begin
            if FQuery.Params.FindParam(ListFields[I]) <> nil then
                FQuery.Params.ParamByName(ListFields[I]).Value := aId;
        end;
    finally
        FreeAndNil(ListFields);
    end;
end;

function TSimpleDAO<T>.Find(aKey: String; aValue: Variant): iSimpleDAO<T>;
var
    aSQL: String;
    LParamCast: String;
    LContext: TRttiContext;
    LType: TRttiType;
    LProp: TRttiProperty;
begin
    Result := Self;
    LParamCast := '';
    LContext := TRttiContext.Create;
    try
      LType := LContext.GetType(TypeInfo(T));
      for LProp in LType.GetProperties do
      begin
        if (LowerCase(LProp.FieldName) = LowerCase(aKey)) or
           (LowerCase(LProp.Name) = LowerCase(aKey)) then
        begin
          if LProp.IsUuid then
            LParamCast := '::uuid';
          Break;
        end;
      end;
    finally
      LContext.Free;
    end;
    TSimpleSQL<T>.New(nil).Where(aKey + ' = :pValue' + LParamCast).Select(aSQL);
    FQuery.SQL.Clear;
    FQuery.SQL.Add(aSQL);
    FQuery.Params.ParamByName('pValue').Value := aValue;
    FQuery.Open;
end;

procedure TSimpleDAO<T>.LoadRelationships(aEntity: T);
var
  ctxRtti: TRttiContext;
  typRtti: TRttiType;
  prpRtti: TRttiProperty;
  Info: PTypeInfo;
  Rel: Relationship;
  aSQL: string;
  FKValue: Variant;
  FKProp: TRttiProperty;
  RelObj: TObject;
  RelField: TField;
  RelProp: TRttiProperty;
  RelType: TRttiType;
  RelTableName: string;
  RelPKName: string;
  RelPKProp: TRttiProperty;
begin
  Info := System.TypeInfo(T);
  ctxRtti := TRttiContext.Create;
  try
    typRtti := ctxRtti.GetType(Info);
    for prpRtti in typRtti.GetProperties do
    begin
      // HasMany: use TSimpleLazyLoader<T> explicitly in entity constructor
      // Runtime generic instantiation via RTTI is not feasible in Delphi,
      // so HasMany relationships should be set up by the developer using
      // TSimpleLazyLoader<TRelatedEntity>.Create(Query, 'fk_field', PKValue)
      if prpRtti.IsHasMany then
        Continue;

      if not (prpRtti.IsBelongsTo or prpRtti.IsHasOne) then
        Continue;

      if prpRtti.PropertyType.TypeKind <> tkClass then
        Continue;

      Rel := prpRtti.GetRelationship;
      if (Rel = nil) or (Rel.ForeignKey = '') then
        Continue;

      // Get FK value from the entity
      FKProp := typRtti.GetProperty(Rel.ForeignKey);
      if FKProp = nil then
        Continue;
      FKValue := FKProp.GetValue(Pointer(aEntity)).AsVariant;

      // Create related object instance
      RelObj := prpRtti.PropertyType.AsInstance.MetaclassType.Create;

      // Get the related entity's table name and PK using its RTTI
      RelType := ctxRtti.GetType(prpRtti.PropertyType.AsInstance.MetaclassType);

      RelTableName := '';
      RelPKName := '';

      if RelType.Tem<Tabela> then
        RelTableName := RelType.GetAttribute<Tabela>.Name;

      RelPKProp := RelType.GetPKField;
      if RelPKProp <> nil then
        RelPKName := RelPKProp.FieldName;

      if (RelTableName = '') or (RelPKName = '') then
      begin
        FreeAndNil(RelObj);
        Continue;
      end;

      aSQL := 'SELECT * FROM ' + RelTableName + ' WHERE ' + RelPKName + ' = :pValue';
      FQuery.SQL.Clear;
      FQuery.SQL.Add(aSQL);
      FQuery.Params.ParamByName('pValue').Value := FKValue;
      FQuery.Open;

      // Map dataset fields to related object properties
      if not FQuery.DataSet.IsEmpty then
      begin
        for RelProp in RelType.GetProperties do
        begin
          if RelProp.IsIgnore then
            Continue;
          RelField := FQuery.DataSet.FindField(RelProp.FieldName);
          if RelField = nil then
            Continue;

          case RelProp.PropertyType.TypeKind of
            tkInteger, tkInt64:
              RelProp.SetValue(RelObj, RelField.AsInteger);
            tkFloat:
              RelProp.SetValue(RelObj, RelField.AsFloat);
            tkUString, tkString, tkWString, tkLString:
              RelProp.SetValue(RelObj, RelField.AsString);
          end;
        end;
      end;

      // Set the related object on the main entity
      prpRtti.SetValue(Pointer(aEntity), RelObj);

      FQuery.DataSet.Close;
    end;
  finally
    ctxRtti.Free;
  end;
end;

procedure TSimpleDAO<T>.ExecuteCascadeDelete(aValue: T);
var
  LCtx: TRttiContext;
  LType: TRttiType;
  LProp: TRttiProperty;
  LRelation: Relationship;
  LPKProp: TRttiProperty;
  LPKValue: TValue;
begin
  LCtx := TRttiContext.Create;
  try
    LType := LCtx.GetType(TObject(aValue).ClassType);
    LPKProp := LType.GetPKField;
    if LPKProp = nil then
      Exit;

    LPKValue := LPKProp.GetValue(Pointer(aValue));

    for LProp in LType.GetProperties do
    begin
      if not LProp.IsCascadeDelete then
        Continue;

      LRelation := LProp.GetRelationship;
      if LRelation = nil then
        Continue;

      FQuery.SQL.Clear;
      FQuery.SQL.Add('DELETE FROM ' + LRelation.EntityName +
        ' WHERE ' + LRelation.ForeignKey + ' = :pCascadeFK');
      FQuery.Params.ParamByName('pCascadeFK').Value := LPKValue.AsVariant;
      FQuery.ExecSQL;
    end;
  finally
    LCtx.Free;
  end;
end;

function TSimpleDAO<T>.InsertBatch(aList: TObjectList<T>): iSimpleDAO<T>;
var
  Item: T;
begin
  Result := Self;
  FQuery.StartTransaction;
  try
    for Item in aList do
      Insert(Item);
    FQuery.Commit;
  except
    on E: Exception do
    begin
      FQuery.Rollback;
      raise;
    end;
  end;
end;

function TSimpleDAO<T>.UpdateBatch(aList: TObjectList<T>): iSimpleDAO<T>;
var
  Item: T;
begin
  Result := Self;
  FQuery.StartTransaction;
  try
    for Item in aList do
      Update(Item);
    FQuery.Commit;
  except
    on E: Exception do
    begin
      FQuery.Rollback;
      raise;
    end;
  end;
end;

function TSimpleDAO<T>.DeleteBatch(aList: TObjectList<T>): iSimpleDAO<T>;
var
  Item: T;
begin
  Result := Self;
  FQuery.StartTransaction;
  try
    for Item in aList do
      Delete(Item);
    FQuery.Commit;
  except
    on E: Exception do
    begin
      FQuery.Rollback;
      raise;
    end;
  end;
end;

function TSimpleDAO<T>.BulkInsert(aList: TObjectList<T>): iSimpleDAO<T>;
var
  LTableName, LFields: String;
  LSQL: String;
  LDictFields: TDictionary<String, Variant>;
  LDictTypeFields: TDictionary<String, TFieldType>;
  LFieldType: TFieldType;
  LFieldList: TList<String>;
  LEnumCastMap: TDictionary<String, String>;
  I, J, LBatchStart, LBatchEnd: Integer;
  LParamName, LParamSQL, LEnumCast: String;
  LBatchSize: Integer;
  LContext: TRttiContext;
  LType: TRttiType;
  LProp: TRttiProperty;
  LInfo: PTypeInfo;
  SW: TStopwatch;
begin
  Result := Self;
  if aList.Count = 0 then
    Exit;

  LBatchSize := 100;

  TSimpleRTTI<T>.New(aList[0]).TableName(LTableName);

  LFieldList := TList<String>.Create;
  try
    LEnumCastMap := TDictionary<String, String>.Create;
    try
      LInfo := System.TypeInfo(T);
      LContext := TRttiContext.Create;
      try
        LType := LContext.GetType(LInfo);
        for LProp in LType.GetProperties do
        begin
          if LProp.IsAutoInc then
            Continue;
          if LProp.IsIgnore then
            Continue;
          LFieldList.Add(LProp.FieldName);

          if LProp.IsEnum then
            LEnumCastMap.Add(LProp.FieldName, '::' + LProp.EnumName)
          else if LProp.IsUuid then
            LEnumCastMap.Add(LProp.FieldName, '::uuid');
        end;
      finally
        LContext.Free;
      end;

      if LFieldList.Count = 0 then
        Exit;

      LFields := '';
      for J := 0 to LFieldList.Count - 1 do
      begin
        if J > 0 then
          LFields := LFields + ', ';
        LFields := LFields + LFieldList[J];
      end;

      FQuery.StartTransaction;
      try
        LBatchStart := 0;
        while LBatchStart < aList.Count do
        begin
          LBatchEnd := LBatchStart + LBatchSize - 1;
          if LBatchEnd >= aList.Count then
            LBatchEnd := aList.Count - 1;

          LSQL := 'INSERT INTO ' + LTableName + ' (' + LFields + ') VALUES ';

          for I := LBatchStart to LBatchEnd do
          begin
            if I > LBatchStart then
              LSQL := LSQL + ', ';
            LSQL := LSQL + '(';
            for J := 0 to LFieldList.Count - 1 do
            begin
              if J > 0 then
                LSQL := LSQL + ', ';
              LParamSQL := ':' + LFieldList[J] + '_' + IntToStr(I - LBatchStart);
              if LEnumCastMap.TryGetValue(LFieldList[J], LEnumCast) then
                LParamSQL := LParamSQL + LEnumCast;
              LSQL := LSQL + LParamSQL;
            end;
            LSQL := LSQL + ')';
          end;

          FQuery.SQL.Clear;
          FQuery.SQL.Add(LSQL);

          for I := LBatchStart to LBatchEnd do
          begin
            LDictFields := TDictionary<String, Variant>.Create;
            try
              LDictTypeFields := TDictionary<String, TFieldType>.Create;
              try
                TSimpleRTTI<T>.New(aList[I]).DictionaryFields(LDictFields);
                TSimpleRTTI<T>.New(aList[I]).DictionaryTypeFields(LDictTypeFields);
                for J := 0 to LFieldList.Count - 1 do
                begin
                  LParamName := LFieldList[J] + '_' + IntToStr(I - LBatchStart);
                  if FQuery.Params.FindParam(LParamName) <> nil then
                  begin
                    if LDictTypeFields.TryGetValue(LFieldList[J], LFieldType) then
                      FQuery.Params.ParamByName(LParamName).DataType := LFieldType;
                    if LDictFields.ContainsKey(LFieldList[J]) then
                    begin
                      if VarIsStr(LDictFields[LFieldList[J]]) and
                         (Length(VarToStr(LDictFields[LFieldList[J]])) > 4000) then
                        FQuery.Params.ParamByName(LParamName).AsMemo := VarToStr(LDictFields[LFieldList[J]])
                      else
                        FQuery.Params.ParamByName(LParamName).Value := LDictFields[LFieldList[J]];
                    end;
                  end;
                end;
              finally
                FreeAndNil(LDictTypeFields);
              end;
            finally
              FreeAndNil(LDictFields);
            end;
          end;

          SW := TStopwatch.StartNew;
          FQuery.ExecSQL;
          SW.Stop;
          if Assigned(FLogger) then
            FLogger.Log(LSQL, FQuery.Params, SW.ElapsedMilliseconds);

          LBatchStart := LBatchEnd + 1;
        end;
        FQuery.Commit;
        if FCacheEnabled then
          FCache.Clear;
      except
        on E: Exception do
        begin
          FQuery.Rollback;
          raise;
        end;
      end;
    finally
      FreeAndNil(LEnumCastMap);
    end;
  finally
    FreeAndNil(LFieldList);
  end;
end;

function TSimpleDAO<T>.Count: Integer;
var
  aSQL: String;
begin
  ApplyScopes;
  TSimpleSQL<T>.New(nil)
    .DatabaseType(FQuery.SQLType)
    .Where(FSQLAttribute.Where)
    .Join(FSQLAttribute.Join)
    .Count(aSQL);

  FQuery.SQL.Clear;
  FQuery.SQL.Add(aSQL);
  FQuery.Open;
  Result := FQuery.DataSet.Fields[0].AsInteger;
end;

function TSimpleDAO<T>.Sum(const aField: String): Double;
var
  aSQL: String;
begin
  ApplyScopes;
  TSimpleSQL<T>.New(nil)
    .DatabaseType(FQuery.SQLType)
    .Where(FSQLAttribute.Where)
    .Join(FSQLAttribute.Join)
    .Aggregate(aSQL, 'SUM', aField);

  FQuery.SQL.Clear;
  FQuery.SQL.Add(aSQL);
  FQuery.Open;
  Result := FQuery.DataSet.Fields[0].AsFloat;
end;

function TSimpleDAO<T>.Min(const aField: String): Double;
var
  aSQL: String;
begin
  ApplyScopes;
  TSimpleSQL<T>.New(nil)
    .DatabaseType(FQuery.SQLType)
    .Where(FSQLAttribute.Where)
    .Join(FSQLAttribute.Join)
    .Aggregate(aSQL, 'MIN', aField);

  FQuery.SQL.Clear;
  FQuery.SQL.Add(aSQL);
  FQuery.Open;
  Result := FQuery.DataSet.Fields[0].AsFloat;
end;

function TSimpleDAO<T>.Max(const aField: String): Double;
var
  aSQL: String;
begin
  ApplyScopes;
  TSimpleSQL<T>.New(nil)
    .DatabaseType(FQuery.SQLType)
    .Where(FSQLAttribute.Where)
    .Join(FSQLAttribute.Join)
    .Aggregate(aSQL, 'MAX', aField);

  FQuery.SQL.Clear;
  FQuery.SQL.Add(aSQL);
  FQuery.Open;
  Result := FQuery.DataSet.Fields[0].AsFloat;
end;

function TSimpleDAO<T>.Avg(const aField: String): Double;
var
  aSQL: String;
begin
  ApplyScopes;
  TSimpleSQL<T>.New(nil)
    .DatabaseType(FQuery.SQLType)
    .Where(FSQLAttribute.Where)
    .Join(FSQLAttribute.Join)
    .Aggregate(aSQL, 'AVG', aField);

  FQuery.SQL.Clear;
  FQuery.SQL.Add(aSQL);
  FQuery.Open;
  Result := FQuery.DataSet.Fields[0].AsFloat;
end;

function TSimpleDAO<T>.Exists(const aField: String; aValue: Variant): Boolean;
var
  aSQL: String;
begin
  TSimpleSQL<T>.New(nil)
    .DatabaseType(FQuery.SQLType)
    .Where(aField + ' = :pValue')
    .Count(aSQL);

  FQuery.SQL.Clear;
  FQuery.SQL.Add(aSQL);
  FQuery.Params.ParamByName('pValue').Value := aValue;
  FQuery.Open;
  Result := FQuery.DataSet.Fields[0].AsInteger > 0;
end;

procedure TSimpleDAO<T>.ApplyScopes;
var
  LScope: String;
  LScopeWhere: String;
begin
  if FActiveScopes.Count = 0 then
    Exit;

  LScopeWhere := '';
  for LScope in FActiveScopes do
  begin
    if LScopeWhere <> '' then
      LScopeWhere := LScopeWhere + ' and ';
    LScopeWhere := LScopeWhere + LScope;
  end;

  if FSQLAttribute.Where <> '' then
    FSQLAttribute.Where(FSQLAttribute.Where + ' and ' + LScopeWhere)
  else
    FSQLAttribute.Where(LScopeWhere);

  FActiveScopes.Clear;
end;

function TSimpleDAO<T>.RegisterScope(const aName, aWhere: String): iSimpleDAO<T>;
begin
  Result := Self;
  FScopes.AddOrSetValue(LowerCase(aName), aWhere);
end;

function TSimpleDAO<T>.Scope(const aName: String): iSimpleDAO<T>;
begin
  Result := Self;
  if FScopes.ContainsKey(LowerCase(aName)) then
    FActiveScopes.Add(FScopes[LowerCase(aName)]);
end;

function TSimpleDAO<T>.ClearScopes: iSimpleDAO<T>;
begin
  Result := Self;
  FActiveScopes.Clear;
end;

function TSimpleDAO<T>.FindOrCreate(const aField: String; aValue: Variant; aEntity: T): T;
var
  aSQL: String;
begin
  TSimpleSQL<T>.New(nil)
    .DatabaseType(FQuery.SQLType)
    .Where(aField + ' = :pValue')
    .Select(aSQL);

  FQuery.SQL.Clear;
  FQuery.SQL.Add(aSQL);
  FQuery.Params.ParamByName('pValue').Value := aValue;
  FQuery.Open;

  if FQuery.DataSet.IsEmpty then
  begin
    Insert(aEntity);
    Result := aEntity;
  end
  else
  begin
    Result := T.Create;
    TSimpleRTTI<T>.New(nil).DataSetToEntity(FQuery.DataSet, Result);
  end;
end;

function TSimpleDAO<T>.UpdateOrCreate(const aField: String; aValue: Variant; aEntity: T): T;
var
  aSQL: String;
begin
  TSimpleSQL<T>.New(nil)
    .DatabaseType(FQuery.SQLType)
    .Where(aField + ' = :pValue')
    .Select(aSQL);

  FQuery.SQL.Clear;
  FQuery.SQL.Add(aSQL);
  FQuery.Params.ParamByName('pValue').Value := aValue;
  FQuery.Open;

  if FQuery.DataSet.IsEmpty then
    Insert(aEntity)
  else
    Update(aEntity);

  Result := aEntity;
end;

function TSimpleDAO<T>.OnBeforeInsert(aCallback: TSimpleCallback): iSimpleDAO<T>;
begin
  Result := Self;
  FOnBeforeInsert := aCallback;
end;

function TSimpleDAO<T>.OnAfterInsert(aCallback: TSimpleCallback): iSimpleDAO<T>;
begin
  Result := Self;
  FOnAfterInsert := aCallback;
end;

function TSimpleDAO<T>.OnBeforeUpdate(aCallback: TSimpleCallback): iSimpleDAO<T>;
begin
  Result := Self;
  FOnBeforeUpdate := aCallback;
end;

function TSimpleDAO<T>.OnAfterUpdate(aCallback: TSimpleCallback): iSimpleDAO<T>;
begin
  Result := Self;
  FOnAfterUpdate := aCallback;
end;

function TSimpleDAO<T>.OnBeforeDelete(aCallback: TSimpleCallback): iSimpleDAO<T>;
begin
  Result := Self;
  FOnBeforeDelete := aCallback;
end;

function TSimpleDAO<T>.OnAfterDelete(aCallback: TSimpleCallback): iSimpleDAO<T>;
begin
  Result := Self;
  FOnAfterDelete := aCallback;
end;

function TSimpleDAO<T>.OnError(aCallback: TSimpleErrorCallback): iSimpleDAO<T>;
begin
  Result := Self;
  FOnError := aCallback;
end;

function TSimpleDAO<T>.RawSQL(const aSQL: String): iSimpleDAO<T>;
begin
  Result := Self;
  FRawSQL := aSQL;
  FRawParams.Clear;
end;

function TSimpleDAO<T>.RawSQLWithParams(const aSQL: String;
  const aParamNames: array of String;
  const aParamValues: array of Variant): iSimpleDAO<T>;
var
  I: Integer;
begin
  Result := Self;
  FRawSQL := aSQL;
  FRawParams.Clear;
  for I := 0 to High(aParamNames) do
    FRawParams.Add(aParamNames[I], aParamValues[I]);
end;

function TSimpleDAO<T>.FindRaw: TObjectList<T>;
var
  LKey: String;
begin
  Result := TObjectList<T>.Create;
  FQuery.SQL.Clear;
  FQuery.SQL.Add(FRawSQL);

  for LKey in FRawParams.Keys do
    FQuery.Params.ParamByName(LKey).Value := FRawParams[LKey];

  FQuery.Open;
  TSimpleRTTI<T>.New(nil).DataSetToEntityList(FQuery.DataSet, Result);
  FRawSQL := '';
  FRawParams.Clear;
end;

function TSimpleDAO<T>.FindAs<R>(var aList: TObjectList<R>): iSimpleDAO<T>;
var
  aSQL: String;
  LContext: TRttiContext;
  LType: TRttiType;
  LProp: TRttiProperty;
  LField: TField;
  LObj: R;
  LFieldName: String;
  LKey: String;
begin
  Result := Self;

  if FRawSQL <> '' then
  begin
    FQuery.SQL.Clear;
    FQuery.SQL.Add(FRawSQL);
    for LKey in FRawParams.Keys do
      FQuery.Params.ParamByName(LKey).Value := FRawParams[LKey];
    FQuery.Open;
    FRawSQL := '';
    FRawParams.Clear;
  end
  else
  begin
    ApplyScopes;
    TSimpleSQL<T>.New(nil).Fields(FSQLAttribute.Fields).Join(FSQLAttribute.Join)
      .Where(FSQLAttribute.Where).GroupBy(FSQLAttribute.GroupBy)
      .OrderBy(FSQLAttribute.OrderBy)
      .Skip(FSQLAttribute.GetSkip)
      .Take(FSQLAttribute.GetTake)
      .DatabaseType(FQuery.SQLType)
      .Select(aSQL);
    FQuery.Open(aSQL);
    FSQLAttribute.Clear;
  end;

  LContext := TRttiContext.Create;
  try
    LType := LContext.GetType(TypeInfo(R));
    while not FQuery.DataSet.Eof do
    begin
      LObj := R.Create;
      try
        for LProp in LType.GetProperties do
        begin
          LFieldName := LProp.FieldName;

          LField := FQuery.DataSet.FindField(LFieldName);
          if (LField = nil) and LProp.EhCampo then
            LField := FQuery.DataSet.FindField(LProp.Name);
          if LField = nil then
            Continue;

          if LField.IsNull then
            Continue;

          case LProp.PropertyType.TypeKind of
            tkInteger, tkInt64:
              LProp.SetValue(Pointer(LObj), LField.AsInteger);
            tkFloat:
              LProp.SetValue(Pointer(LObj), LField.AsFloat);
            tkUString, tkString, tkWString, tkLString:
              LProp.SetValue(Pointer(LObj), LField.AsString);
          end;
        end;
        aList.Add(LObj);
      except
        LObj.Free;
        raise;
      end;
      FQuery.DataSet.Next;
    end;
  finally
    LContext.Free;
  end;
end;

function TSimpleDAO<T>.Ask(const aQuestion: String): TDataSet;
var
  LNLQuery: TSimpleNLQuery;
begin
  if FAIClient = nil then
    raise Exception.Create('Ask requires an AI client. Call .AIClient(...) first.');

  LNLQuery := TSimpleNLQuery.New(FQuery, FAIClient);
  try
    LNLQuery.RegisterEntity(System.TypeInfo(T));
    Result := LNLQuery.Ask(aQuestion);
  finally
    FreeAndNil(LNLQuery);
  end;
end;

function TSimpleDAO<T>.ExecRawSQL(const aSQL: String): iSimpleDAO<T>;
begin
  Result := Self;
  FQuery.SQL.Clear;
  FQuery.SQL.Add(aSQL);
  FQuery.ExecSQL;
end;

function TSimpleDAO<T>.EnableCache: iSimpleDAO<T>;
begin
  Result := Self;
  FCacheEnabled := True;
end;

function TSimpleDAO<T>.DisableCache: iSimpleDAO<T>;
begin
  Result := Self;
  FCacheEnabled := False;
end;

function TSimpleDAO<T>.ClearCache: iSimpleDAO<T>;
begin
  Result := Self;
  FCache.Clear;
end;

end.

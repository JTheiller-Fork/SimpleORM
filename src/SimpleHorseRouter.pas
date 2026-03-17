unit SimpleHorseRouter;

interface

uses
  SimpleInterface, SimpleAttributes, SimpleDAO, SimpleRTTI, SimpleSerializer,
  SimpleSwagger,
  System.SysUtils, System.Rtti, System.JSON, System.TypInfo,
  System.Generics.Collections,
  Horse;

type
  TEntityCallback = reference to procedure(aEntity: TObject; var aContinue: Boolean);
  TEntityAfterCallback = reference to procedure(aEntity: TObject);
  TDeleteCallback = reference to procedure(aId: string; var aContinue: Boolean);

  TSimpleHorseRouterConfig = class
  private
    FOnBeforeInsert: TEntityCallback;
    FOnAfterInsert: TEntityAfterCallback;
    FOnBeforeUpdate: TEntityCallback;
    FOnBeforeDelete: TDeleteCallback;
  public
    function OnBeforeInsert(aProc: TEntityCallback): TSimpleHorseRouterConfig;
    function OnAfterInsert(aProc: TEntityAfterCallback): TSimpleHorseRouterConfig;
    function OnBeforeUpdate(aProc: TEntityCallback): TSimpleHorseRouterConfig;
    function OnBeforeDelete(aProc: TDeleteCallback): TSimpleHorseRouterConfig;
  end;

  TSimpleHorseRouter = class
  private
    class var FSwagger: TSimpleSwagger;
  public
    class function RegisterEntity<T: class, constructor>(
      aApp: THorse; aQuery: iSimpleQuery; aPath: string = ''
    ): TSimpleHorseRouterConfig;
    class procedure EnableSwagger(aApp: THorse;
      const aTitle: String = 'SimpleORM API';
      const aVersion: String = '1.0.0');
    class function GetSwagger: TSimpleSwagger;
    class destructor Destroy;
  end;

var
  _RegisteredConfigs: TObjectList<TSimpleHorseRouterConfig>;

implementation

{ TSimpleHorseRouterConfig }

function TSimpleHorseRouterConfig.OnBeforeInsert(aProc: TEntityCallback): TSimpleHorseRouterConfig;
begin
  FOnBeforeInsert := aProc;
  Result := Self;
end;

function TSimpleHorseRouterConfig.OnAfterInsert(aProc: TEntityAfterCallback): TSimpleHorseRouterConfig;
begin
  FOnAfterInsert := aProc;
  Result := Self;
end;

function TSimpleHorseRouterConfig.OnBeforeUpdate(aProc: TEntityCallback): TSimpleHorseRouterConfig;
begin
  FOnBeforeUpdate := aProc;
  Result := Self;
end;

function TSimpleHorseRouterConfig.OnBeforeDelete(aProc: TDeleteCallback): TSimpleHorseRouterConfig;
begin
  FOnBeforeDelete := aProc;
  Result := Self;
end;

{ TSimpleHorseRouter }

class destructor TSimpleHorseRouter.Destroy;
begin
  FreeAndNil(FSwagger);
end;

class function TSimpleHorseRouter.GetSwagger: TSimpleSwagger;
begin
  if FSwagger = nil then
    FSwagger := TSimpleSwagger.Create;
  Result := FSwagger;
end;

class procedure TSimpleHorseRouter.EnableSwagger(aApp: THorse;
  const aTitle: String; const aVersion: String);
begin
  GetSwagger.Title(aTitle).Version(aVersion);

  aApp.Get('/swagger.json',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LJSON: TJSONObject;
    begin
      try
        LJSON := GetSwagger.Generate;
        Res.Send<TJSONObject>(LJSON).Status(200);
      except
        on E: Exception do
          Res.Send<TJSONObject>(
            TJSONObject.Create.AddPair('error', E.Message)
          ).Status(500);
      end;
    end
  );
end;

class function TSimpleHorseRouter.RegisterEntity<T>(
  aApp: THorse; aQuery: iSimpleQuery; aPath: string): TSimpleHorseRouterConfig;
var
  LConfig: TSimpleHorseRouterConfig;
  LPath: string;
  LTableName: string;
begin
  LConfig := TSimpleHorseRouterConfig.Create;
  _RegisteredConfigs.Add(LConfig);
  Result := LConfig;

  if aPath <> '' then
    LPath := aPath
  else
  begin
    TSimpleRTTI<T>.New(nil).TableName(LTableName);
    LPath := '/' + LowerCase(LTableName);
  end;

  { Register entity with Swagger if enabled }
  if FSwagger <> nil then
    FSwagger.RegisterEntity(System.TypeInfo(T), LPath);

  { GET /path - List all with optional skip/take }
  aApp.Get(LPath,
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LDAO: iSimpleDAO<T>;
      LList: TObjectList<T>;
      LJSONArray: TJSONArray;
      LResult: TJSONObject;
      LSkipStr, LTakeStr: string;
      LSkip, LTake: Integer;
    begin
      try
        LDAO := TSimpleDAO<T>.New(aQuery);
        LList := TObjectList<T>.Create;
        try
          LSkipStr := Req.Query['skip'];
          LTakeStr := Req.Query['take'];

          if (LSkipStr <> '') or (LTakeStr <> '') then
          begin
            LSkip := 0;
            LTake := 0;
            if LSkipStr <> '' then
              LSkip := StrToIntDef(LSkipStr, 0);
            if LTakeStr <> '' then
              LTake := StrToIntDef(LTakeStr, 0);

            LDAO.SQL
              .Skip(LSkip)
              .Take(LTake)
              .&End
              .Find(LList);
          end
          else
            LDAO.Find(LList);

          LJSONArray := TSimpleSerializer.EntityListToJSONArray<T>(LList);
          LResult := TJSONObject.Create;
          LResult.AddPair('data', LJSONArray);
          LResult.AddPair('count', TJSONNumber.Create(LList.Count));

          Res.Send<TJSONObject>(LResult).Status(200);
        finally
          LList.Free;
        end;
      except
        on E: Exception do
          Res.Send<TJSONObject>(
            TJSONObject.Create.AddPair('error', E.Message)
          ).Status(500);
      end;
    end
  );

  { GET /path/:id - Find by primary key }
  aApp.Get(LPath + '/:id',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LDAO: iSimpleDAO<T>;
      LEntity: T;
      LId: Integer;
      LJSON: TJSONObject;
    begin
      try
        LId := StrToIntDef(Req.Params['id'], 0);
        LDAO := TSimpleDAO<T>.New(aQuery);
        LEntity := LDAO.Find(LId);
        try
          if LEntity = nil then
          begin
            Res.Send<TJSONObject>(
              TJSONObject.Create.AddPair('error', 'Not found')
            ).Status(404);
            Exit;
          end;

          LJSON := TSimpleSerializer.EntityToJSON<T>(LEntity);
          Res.Send<TJSONObject>(LJSON).Status(200);
        finally
          LEntity.Free;
        end;
      except
        on E: Exception do
          Res.Send<TJSONObject>(
            TJSONObject.Create.AddPair('error', E.Message)
          ).Status(500);
      end;
    end
  );

  { POST /path - Insert entity from body JSON }
  aApp.Post(LPath,
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LDAO: iSimpleDAO<T>;
      LEntity: T;
      LJSONBody: TJSONObject;
      LJSONResult: TJSONObject;
      LContinue: Boolean;
    begin
      try
        LJSONBody := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
        if LJSONBody = nil then
          raise Exception.Create('Invalid JSON body');
        try
          LEntity := TSimpleSerializer.JSONToEntity<T>(LJSONBody);
        finally
          LJSONBody.Free;
        end;

        try
          if Assigned(LConfig.FOnBeforeInsert) then
          begin
            LContinue := True;
            LConfig.FOnBeforeInsert(LEntity, LContinue);
            if not LContinue then
            begin
              Res.Send<TJSONObject>(
                TJSONObject.Create.AddPair('error', 'Operation cancelled')
              ).Status(400);
              Exit;
            end;
          end;

          LDAO := TSimpleDAO<T>.New(aQuery);
          LDAO.Insert(LEntity);

          if Assigned(LConfig.FOnAfterInsert) then
            LConfig.FOnAfterInsert(LEntity);

          LJSONResult := TSimpleSerializer.EntityToJSON<T>(LEntity);
          Res.Send<TJSONObject>(LJSONResult).Status(201);
        finally
          LEntity.Free;
        end;
      except
        on E: Exception do
          Res.Send<TJSONObject>(
            TJSONObject.Create.AddPair('error', E.Message)
          ).Status(500);
      end;
    end
  );

  { PUT /path/:id - Update entity from body JSON }
  aApp.Put(LPath + '/:id',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LDAO: iSimpleDAO<T>;
      LEntity: T;
      LJSONBody: TJSONObject;
      LJSONResult: TJSONObject;
      LContinue: Boolean;
      LPK: string;
      LContext: TRttiContext;
      LType: TRttiType;
      LProp: TRttiProperty;
      LAttr: TCustomAttribute;
    begin
      try
        LJSONBody := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
        if LJSONBody = nil then
          raise Exception.Create('Invalid JSON body');
        try
          LEntity := TSimpleSerializer.JSONToEntity<T>(LJSONBody);
        finally
          LJSONBody.Free;
        end;

        try
          // Set PK from URL :id param on the entity
          TSimpleRTTI<T>.New(nil).PrimaryKey(LPK);
          LContext := TRttiContext.Create;
          LType := LContext.GetType(TObject(LEntity).ClassType);
          for LProp in LType.GetProperties do
          begin
            for LAttr in LProp.GetAttributes do
            begin
              if (LAttr is Campo) and (Campo(LAttr).Name = LPK) then
              begin
                case LProp.PropertyType.TypeKind of
                  tkInteger:
                    LProp.SetValue(TObject(LEntity), StrToIntDef(Req.Params['id'], 0));
                  tkInt64:
                    LProp.SetValue(TObject(LEntity), StrToInt64Def(Req.Params['id'], 0));
                  tkUString, tkString, tkLString, tkWString:
                    LProp.SetValue(TObject(LEntity), Req.Params['id']);
                end;
                Break;
              end;
            end;
          end;

          if Assigned(LConfig.FOnBeforeUpdate) then
          begin
            LContinue := True;
            LConfig.FOnBeforeUpdate(LEntity, LContinue);
            if not LContinue then
            begin
              Res.Send<TJSONObject>(
                TJSONObject.Create.AddPair('error', 'Operation cancelled')
              ).Status(400);
              Exit;
            end;
          end;

          LDAO := TSimpleDAO<T>.New(aQuery);
          LDAO.Update(LEntity);

          LJSONResult := TSimpleSerializer.EntityToJSON<T>(LEntity);
          Res.Send<TJSONObject>(LJSONResult).Status(200);
        finally
          LEntity.Free;
        end;
      except
        on E: Exception do
          Res.Send<TJSONObject>(
            TJSONObject.Create.AddPair('error', E.Message)
          ).Status(500);
      end;
    end
  );

  { DELETE /path/:id - Delete by primary key }
  aApp.Delete(LPath + '/:id',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    var
      LDAO: iSimpleDAO<T>;
      LId: string;
      LPK: string;
      LContinue: Boolean;
    begin
      try
        LId := Req.Params['id'];

        if Assigned(LConfig.FOnBeforeDelete) then
        begin
          LContinue := True;
          LConfig.FOnBeforeDelete(LId, LContinue);
          if not LContinue then
          begin
            Res.Send<TJSONObject>(
              TJSONObject.Create.AddPair('error', 'Operation cancelled')
            ).Status(400);
            Exit;
          end;
        end;

        TSimpleRTTI<T>.New(nil).PrimaryKey(LPK);

        LDAO := TSimpleDAO<T>.New(aQuery);
        LDAO.Delete(LPK, LId);

        Res.Status(204);
      except
        on E: Exception do
          Res.Send<TJSONObject>(
            TJSONObject.Create.AddPair('error', E.Message)
          ).Status(500);
      end;
    end
  );
end;

initialization
  _RegisteredConfigs := TObjectList<TSimpleHorseRouterConfig>.Create(True);

finalization
  FreeAndNil(_RegisteredConfigs);

end.

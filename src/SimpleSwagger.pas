unit SimpleSwagger;

interface

uses
  SimpleAttributes,
  System.SysUtils, System.Classes, System.Rtti, System.JSON,
  System.TypInfo, System.Generics.Collections;

type
  TSwaggerEntityInfo = record
    TypeInfo: PTypeInfo;
    Path: String;
  end;

  TSimpleSwagger = class
  private
    FTitle: String;
    FVersion: String;
    FDescription: String;
    FBasePath: String;
    FEntities: TList<TSwaggerEntityInfo>;

    function DelphiTypeToJSONSchemaType(aTypeKind: TTypeKind; aTypeHandle: PTypeInfo): TJSONObject;
    function GenerateSchemaForEntity(aTypeInfo: PTypeInfo): TJSONObject;
    function GeneratePathsForEntity(aTypeInfo: PTypeInfo; const aPath: String;
      const aSchemaName: String): TJSONObject;
    function GetSchemaName(aTypeInfo: PTypeInfo): String;
    function GetTableName(aTypeInfo: PTypeInfo): String;
    function GetPKFieldName(aTypeInfo: PTypeInfo): String;
    function BuildErrorResponse(const aDescription: String): TJSONObject;
    function BuildRefObject(const aSchemaName: String): TJSONObject;
    procedure MergeJSONObject(aTarget, aSource: TJSONObject);
  public
    constructor Create;
    destructor Destroy; override;

    function Title(const aValue: String): TSimpleSwagger;
    function Version(const aValue: String): TSimpleSwagger;
    function Description(const aValue: String): TSimpleSwagger;
    function BasePath(const aValue: String): TSimpleSwagger;
    function RegisterEntity(aTypeInfo: PTypeInfo; const aPath: String): TSimpleSwagger;
    function Generate: TJSONObject;
    function GenerateAsString: String;
  end;

implementation

{ TSimpleSwagger }

constructor TSimpleSwagger.Create;
begin
  inherited Create;
  FTitle := 'SimpleORM API';
  FVersion := '1.0.0';
  FDescription := 'Auto-generated API documentation';
  FBasePath := '/';
  FEntities := TList<TSwaggerEntityInfo>.Create;
end;

destructor TSimpleSwagger.Destroy;
begin
  FreeAndNil(FEntities);
  inherited;
end;

function TSimpleSwagger.Title(const aValue: String): TSimpleSwagger;
begin
  FTitle := aValue;
  Result := Self;
end;

function TSimpleSwagger.Version(const aValue: String): TSimpleSwagger;
begin
  FVersion := aValue;
  Result := Self;
end;

function TSimpleSwagger.Description(const aValue: String): TSimpleSwagger;
begin
  FDescription := aValue;
  Result := Self;
end;

function TSimpleSwagger.BasePath(const aValue: String): TSimpleSwagger;
begin
  FBasePath := aValue;
  Result := Self;
end;

function TSimpleSwagger.RegisterEntity(aTypeInfo: PTypeInfo; const aPath: String): TSimpleSwagger;
var
  LInfo: TSwaggerEntityInfo;
begin
  LInfo.TypeInfo := aTypeInfo;
  LInfo.Path := aPath;
  FEntities.Add(LInfo);
  Result := Self;
end;

function TSimpleSwagger.DelphiTypeToJSONSchemaType(aTypeKind: TTypeKind;
  aTypeHandle: PTypeInfo): TJSONObject;
begin
  Result := TJSONObject.Create;

  case aTypeKind of
    tkInteger:
    begin
      Result.AddPair('type', 'integer');
      Result.AddPair('format', 'int32');
    end;
    tkInt64:
    begin
      Result.AddPair('type', 'integer');
      Result.AddPair('format', 'int64');
    end;
    tkFloat:
    begin
      if aTypeHandle = System.TypeInfo(TDateTime) then
      begin
        Result.AddPair('type', 'string');
        Result.AddPair('format', 'date-time');
      end
      else
      begin
        Result.AddPair('type', 'number');
        Result.AddPair('format', 'double');
      end;
    end;
    tkUString, tkString, tkLString, tkWString:
      Result.AddPair('type', 'string');
    tkEnumeration:
    begin
      if aTypeHandle = System.TypeInfo(Boolean) then
        Result.AddPair('type', 'boolean')
      else
        Result.AddPair('type', 'string');
    end;
  else
    Result.AddPair('type', 'string');
  end;
end;

function TSimpleSwagger.GetSchemaName(aTypeInfo: PTypeInfo): String;
var
  LName: String;
begin
  LName := String(aTypeInfo.Name);
  { Remove leading T from class name if present }
  if (Length(LName) > 1) and (LName[1] = 'T') then
    Result := Copy(LName, 2, Length(LName) - 1)
  else
    Result := LName;
end;

function TSimpleSwagger.GetTableName(aTypeInfo: PTypeInfo): String;
var
  LContext: TRttiContext;
  LType: TRttiType;
  LAttr: TCustomAttribute;
begin
  Result := '';
  LContext := TRttiContext.Create;
  try
    LType := LContext.GetType(aTypeInfo);
    if LType <> nil then
    begin
      for LAttr in LType.GetAttributes do
      begin
        if LAttr is Tabela then
        begin
          Result := Tabela(LAttr).Name;
          Exit;
        end;
      end;
      { Fallback: use class name without T prefix }
      Result := GetSchemaName(aTypeInfo);
    end;
  finally
    LContext.Free;
  end;
end;

function TSimpleSwagger.GetPKFieldName(aTypeInfo: PTypeInfo): String;
var
  LContext: TRttiContext;
  LType: TRttiType;
  LProp: TRttiProperty;
  LAttr: TCustomAttribute;
  LHasPK: Boolean;
  LCampoName: String;
begin
  Result := 'id';
  LContext := TRttiContext.Create;
  try
    LType := LContext.GetType(aTypeInfo);
    if LType = nil then
      Exit;

    for LProp in LType.GetProperties do
    begin
      LHasPK := False;
      LCampoName := LProp.Name;

      for LAttr in LProp.GetAttributes do
      begin
        if LAttr is PK then
          LHasPK := True;
        if LAttr is Campo then
          LCampoName := Campo(LAttr).Name;
      end;

      if LHasPK then
      begin
        Result := LCampoName;
        Exit;
      end;
    end;
  finally
    LContext.Free;
  end;
end;

function TSimpleSwagger.GenerateSchemaForEntity(aTypeInfo: PTypeInfo): TJSONObject;
var
  LContext: TRttiContext;
  LType: TRttiType;
  LProp: TRttiProperty;
  LAttr: TCustomAttribute;
  LProperties: TJSONObject;
  LRequired: TJSONArray;
  LPropSchema: TJSONObject;
  LCampoName: String;
  LHasCampo: Boolean;
  LHasIgnore: Boolean;
  LHasPK: Boolean;
  LHasAutoInc: Boolean;
  LHasNotNull: Boolean;
  LHasNotZero: Boolean;
begin
  Result := TJSONObject.Create;
  LProperties := TJSONObject.Create;
  LRequired := TJSONArray.Create;

  Result.AddPair('type', 'object');

  LContext := TRttiContext.Create;
  try
    LType := LContext.GetType(aTypeInfo);
    if LType = nil then
      Exit;

    for LProp in LType.GetProperties do
    begin
      LHasCampo := False;
      LHasIgnore := False;
      LHasPK := False;
      LHasAutoInc := False;
      LHasNotNull := False;
      LHasNotZero := False;
      LCampoName := LProp.Name;

      for LAttr in LProp.GetAttributes do
      begin
        if LAttr is Ignore then
          LHasIgnore := True;
        if LAttr is Campo then
        begin
          LHasCampo := True;
          LCampoName := Campo(LAttr).Name;
        end;
        if LAttr is PK then
          LHasPK := True;
        if LAttr is AutoInc then
          LHasAutoInc := True;
        if LAttr is NotNull then
          LHasNotNull := True;
        if LAttr is NotZero then
          LHasNotZero := True;
      end;

      if LHasIgnore then
        Continue;

      { Skip properties without [Campo] — they are not mapped }
      if not LHasCampo then
        Continue;

      { Skip relationship properties (HasOne, BelongsTo, HasMany, BelongsToMany) }
      if (LProp.PropertyType.TypeKind = tkClass) then
        Continue;

      LPropSchema := DelphiTypeToJSONSchemaType(
        LProp.PropertyType.TypeKind,
        LProp.PropertyType.Handle
      );

      if LHasAutoInc then
        LPropSchema.AddPair('readOnly', TJSONTrue.Create);

      LProperties.AddPair(LCampoName, LPropSchema);

      { Add to required if PK (non-AutoInc) or NotNull or NotZero }
      if (LHasPK and (not LHasAutoInc)) or LHasNotNull or LHasNotZero then
        LRequired.Add(LCampoName);
    end;

    Result.AddPair('properties', LProperties);
    if LRequired.Count > 0 then
      Result.AddPair('required', LRequired)
    else
      LRequired.Free;
  finally
    LContext.Free;
  end;
end;

function TSimpleSwagger.BuildErrorResponse(const aDescription: String): TJSONObject;
var
  LContent: TJSONObject;
  LMediaType: TJSONObject;
  LSchema: TJSONObject;
  LProps: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('description', aDescription);

  LSchema := TJSONObject.Create;
  LSchema.AddPair('type', 'object');
  LProps := TJSONObject.Create;
  LProps.AddPair('error', TJSONObject.Create.AddPair('type', 'string'));
  LSchema.AddPair('properties', LProps);

  LMediaType := TJSONObject.Create;
  LMediaType.AddPair('schema', LSchema);

  LContent := TJSONObject.Create;
  LContent.AddPair('application/json', LMediaType);

  Result.AddPair('content', LContent);
end;

function TSimpleSwagger.BuildRefObject(const aSchemaName: String): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('$ref', '#/components/schemas/' + aSchemaName);
end;

function TSimpleSwagger.GeneratePathsForEntity(aTypeInfo: PTypeInfo;
  const aPath: String; const aSchemaName: String): TJSONObject;
var
  LListPath: TJSONObject;
  LItemPath: TJSONObject;
  LGetList: TJSONObject;
  LGetItem: TJSONObject;
  LPostOp: TJSONObject;
  LPutOp: TJSONObject;
  LDeleteOp: TJSONObject;
  LResponses: TJSONObject;
  LContent: TJSONObject;
  LMediaType: TJSONObject;
  LSchema: TJSONObject;
  LDataSchema: TJSONObject;
  LDataProps: TJSONObject;
  LItemsSchema: TJSONObject;
  LParameters: TJSONArray;
  LParam: TJSONObject;
  LParamSchema: TJSONObject;
  LRequestBody: TJSONObject;
  LReqContent: TJSONObject;
  LReqMediaType: TJSONObject;
  LTags: TJSONArray;
  LPKField: String;
  LPathWithId: String;
begin
  Result := TJSONObject.Create;
  LPKField := GetPKFieldName(aTypeInfo);
  LPathWithId := aPath + '/{id}';

  { --- GET /path (list) --- }
  LGetList := TJSONObject.Create;
  LTags := TJSONArray.Create;
  LTags.Add(aSchemaName);
  LGetList.AddPair('tags', LTags);
  LGetList.AddPair('summary', 'List all ' + aSchemaName);
  LGetList.AddPair('operationId', 'list' + aSchemaName);

  { Query parameters: skip and take }
  LParameters := TJSONArray.Create;

  LParam := TJSONObject.Create;
  LParam.AddPair('name', 'skip');
  LParam.AddPair('in', 'query');
  LParam.AddPair('required', TJSONFalse.Create);
  LParam.AddPair('description', 'Number of records to skip');
  LParamSchema := TJSONObject.Create;
  LParamSchema.AddPair('type', 'integer');
  LParam.AddPair('schema', LParamSchema);
  LParameters.Add(LParam);

  LParam := TJSONObject.Create;
  LParam.AddPair('name', 'take');
  LParam.AddPair('in', 'query');
  LParam.AddPair('required', TJSONFalse.Create);
  LParam.AddPair('description', 'Number of records to return');
  LParamSchema := TJSONObject.Create;
  LParamSchema.AddPair('type', 'integer');
  LParam.AddPair('schema', LParamSchema);
  LParameters.Add(LParam);

  LGetList.AddPair('parameters', LParameters);

  { Response 200 }
  LResponses := TJSONObject.Create;

  LItemsSchema := TJSONObject.Create;
  LItemsSchema.AddPair('type', 'array');
  LItemsSchema.AddPair('items', BuildRefObject(aSchemaName));

  LDataProps := TJSONObject.Create;
  LDataProps.AddPair('data', LItemsSchema);
  LDataSchema := TJSONObject.Create;
  LDataSchema.AddPair('type', 'object');
  LDataSchema.AddPair('properties', LDataProps);

  LMediaType := TJSONObject.Create;
  LMediaType.AddPair('schema', LDataSchema);

  LContent := TJSONObject.Create;
  LContent.AddPair('application/json', LMediaType);

  LResponses.AddPair('200', TJSONObject.Create
    .AddPair('description', 'Successful operation')
    .AddPair('content', LContent));
  LResponses.AddPair('500', BuildErrorResponse('Internal server error'));

  LGetList.AddPair('responses', LResponses);

  { --- POST /path --- }
  LPostOp := TJSONObject.Create;
  LTags := TJSONArray.Create;
  LTags.Add(aSchemaName);
  LPostOp.AddPair('tags', LTags);
  LPostOp.AddPair('summary', 'Create a new ' + aSchemaName);
  LPostOp.AddPair('operationId', 'create' + aSchemaName);

  { Request body }
  LReqMediaType := TJSONObject.Create;
  LReqMediaType.AddPair('schema', BuildRefObject(aSchemaName));
  LReqContent := TJSONObject.Create;
  LReqContent.AddPair('application/json', LReqMediaType);
  LRequestBody := TJSONObject.Create;
  LRequestBody.AddPair('required', TJSONTrue.Create);
  LRequestBody.AddPair('content', LReqContent);
  LPostOp.AddPair('requestBody', LRequestBody);

  LResponses := TJSONObject.Create;

  LMediaType := TJSONObject.Create;
  LMediaType.AddPair('schema', BuildRefObject(aSchemaName));
  LContent := TJSONObject.Create;
  LContent.AddPair('application/json', LMediaType);
  LResponses.AddPair('201', TJSONObject.Create
    .AddPair('description', 'Entity created')
    .AddPair('content', LContent));
  LResponses.AddPair('400', BuildErrorResponse('Invalid request'));
  LResponses.AddPair('500', BuildErrorResponse('Internal server error'));

  LPostOp.AddPair('responses', LResponses);

  { Build list path object }
  LListPath := TJSONObject.Create;
  LListPath.AddPair('get', LGetList);
  LListPath.AddPair('post', LPostOp);

  Result.AddPair(aPath, LListPath);

  { --- ID parameter for item paths --- }
  LParameters := TJSONArray.Create;
  LParam := TJSONObject.Create;
  LParam.AddPair('name', 'id');
  LParam.AddPair('in', 'path');
  LParam.AddPair('required', TJSONTrue.Create);
  LParam.AddPair('description', 'Entity primary key (' + LPKField + ')');
  LParamSchema := TJSONObject.Create;
  LParamSchema.AddPair('type', 'string');
  LParam.AddPair('schema', LParamSchema);
  LParameters.Add(LParam);

  { --- GET /path/{id} --- }
  LGetItem := TJSONObject.Create;
  LTags := TJSONArray.Create;
  LTags.Add(aSchemaName);
  LGetItem.AddPair('tags', LTags);
  LGetItem.AddPair('summary', 'Find ' + aSchemaName + ' by ID');
  LGetItem.AddPair('operationId', 'get' + aSchemaName + 'ById');
  LGetItem.AddPair('parameters', LParameters);

  LResponses := TJSONObject.Create;

  LMediaType := TJSONObject.Create;
  LMediaType.AddPair('schema', BuildRefObject(aSchemaName));
  LContent := TJSONObject.Create;
  LContent.AddPair('application/json', LMediaType);
  LResponses.AddPair('200', TJSONObject.Create
    .AddPair('description', 'Successful operation')
    .AddPair('content', LContent));
  LResponses.AddPair('404', BuildErrorResponse('Entity not found'));
  LResponses.AddPair('500', BuildErrorResponse('Internal server error'));

  LGetItem.AddPair('responses', LResponses);

  { --- PUT /path/{id} --- }
  LPutOp := TJSONObject.Create;
  LTags := TJSONArray.Create;
  LTags.Add(aSchemaName);
  LPutOp.AddPair('tags', LTags);
  LPutOp.AddPair('summary', 'Update ' + aSchemaName + ' by ID');
  LPutOp.AddPair('operationId', 'update' + aSchemaName);

  { Reuse same parameters array clone for PUT }
  LParameters := TJSONArray.Create;
  LParam := TJSONObject.Create;
  LParam.AddPair('name', 'id');
  LParam.AddPair('in', 'path');
  LParam.AddPair('required', TJSONTrue.Create);
  LParam.AddPair('description', 'Entity primary key (' + LPKField + ')');
  LParamSchema := TJSONObject.Create;
  LParamSchema.AddPair('type', 'string');
  LParam.AddPair('schema', LParamSchema);
  LParameters.Add(LParam);
  LPutOp.AddPair('parameters', LParameters);

  LReqMediaType := TJSONObject.Create;
  LReqMediaType.AddPair('schema', BuildRefObject(aSchemaName));
  LReqContent := TJSONObject.Create;
  LReqContent.AddPair('application/json', LReqMediaType);
  LRequestBody := TJSONObject.Create;
  LRequestBody.AddPair('required', TJSONTrue.Create);
  LRequestBody.AddPair('content', LReqContent);
  LPutOp.AddPair('requestBody', LRequestBody);

  LResponses := TJSONObject.Create;

  LMediaType := TJSONObject.Create;
  LMediaType.AddPair('schema', BuildRefObject(aSchemaName));
  LContent := TJSONObject.Create;
  LContent.AddPair('application/json', LMediaType);
  LResponses.AddPair('200', TJSONObject.Create
    .AddPair('description', 'Entity updated')
    .AddPair('content', LContent));
  LResponses.AddPair('400', BuildErrorResponse('Invalid request'));
  LResponses.AddPair('500', BuildErrorResponse('Internal server error'));

  LPutOp.AddPair('responses', LResponses);

  { --- DELETE /path/{id} --- }
  LDeleteOp := TJSONObject.Create;
  LTags := TJSONArray.Create;
  LTags.Add(aSchemaName);
  LDeleteOp.AddPair('tags', LTags);
  LDeleteOp.AddPair('summary', 'Delete ' + aSchemaName + ' by ID');
  LDeleteOp.AddPair('operationId', 'delete' + aSchemaName);

  LParameters := TJSONArray.Create;
  LParam := TJSONObject.Create;
  LParam.AddPair('name', 'id');
  LParam.AddPair('in', 'path');
  LParam.AddPair('required', TJSONTrue.Create);
  LParam.AddPair('description', 'Entity primary key (' + LPKField + ')');
  LParamSchema := TJSONObject.Create;
  LParamSchema.AddPair('type', 'string');
  LParam.AddPair('schema', LParamSchema);
  LParameters.Add(LParam);
  LDeleteOp.AddPair('parameters', LParameters);

  LResponses := TJSONObject.Create;
  LResponses.AddPair('204', TJSONObject.Create
    .AddPair('description', 'Entity deleted'));
  LResponses.AddPair('400', BuildErrorResponse('Operation cancelled'));
  LResponses.AddPair('500', BuildErrorResponse('Internal server error'));

  LDeleteOp.AddPair('responses', LResponses);

  { Build item path object }
  LItemPath := TJSONObject.Create;
  LItemPath.AddPair('get', LGetItem);
  LItemPath.AddPair('put', LPutOp);
  LItemPath.AddPair('delete', LDeleteOp);

  Result.AddPair(LPathWithId, LItemPath);
end;

procedure TSimpleSwagger.MergeJSONObject(aTarget, aSource: TJSONObject);
var
  I: Integer;
  LPair: TJSONPair;
begin
  for I := 0 to aSource.Count - 1 do
  begin
    LPair := aSource.Pairs[I];
    aTarget.AddPair(TJSONPair.Create(LPair.JsonString.Value,
      LPair.JsonValue.Clone as TJSONValue));
  end;
end;

function TSimpleSwagger.Generate: TJSONObject;
var
  LInfo: TJSONObject;
  LPaths: TJSONObject;
  LSchemas: TJSONObject;
  LComponents: TJSONObject;
  LEntityPaths: TJSONObject;
  LSchemaName: String;
  LTableName: String;
  LPath: String;
  I: Integer;
  LEntity: TSwaggerEntityInfo;
begin
  Result := TJSONObject.Create;

  { OpenAPI version }
  Result.AddPair('openapi', '3.0.3');

  { Info }
  LInfo := TJSONObject.Create;
  LInfo.AddPair('title', FTitle);
  LInfo.AddPair('version', FVersion);
  LInfo.AddPair('description', FDescription);
  Result.AddPair('info', LInfo);

  { Paths and Schemas }
  LPaths := TJSONObject.Create;
  LSchemas := TJSONObject.Create;

  for I := 0 to FEntities.Count - 1 do
  begin
    LEntity := FEntities[I];
    LSchemaName := GetSchemaName(LEntity.TypeInfo);
    LTableName := GetTableName(LEntity.TypeInfo);

    { Determine path }
    if LEntity.Path <> '' then
      LPath := LEntity.Path
    else
      LPath := '/' + LowerCase(LTableName);

    { Generate schema }
    LSchemas.AddPair(LSchemaName, GenerateSchemaForEntity(LEntity.TypeInfo));

    { Generate paths }
    LEntityPaths := GeneratePathsForEntity(LEntity.TypeInfo, LPath, LSchemaName);
    try
      MergeJSONObject(LPaths, LEntityPaths);
    finally
      LEntityPaths.Free;
    end;
  end;

  Result.AddPair('paths', LPaths);

  { Components }
  LComponents := TJSONObject.Create;
  LComponents.AddPair('schemas', LSchemas);
  Result.AddPair('components', LComponents);
end;

function TSimpleSwagger.GenerateAsString: String;
var
  LJSON: TJSONObject;
begin
  LJSON := Generate;
  try
    Result := LJSON.ToString;
  finally
    LJSON.Free;
  end;
end;

end.

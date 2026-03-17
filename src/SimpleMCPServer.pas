unit SimpleMCPServer;

interface

uses
  System.JSON, System.SysUtils, System.Classes, System.Generics.Collections,
  System.Rtti, System.TypInfo, SimpleInterface, SimpleTypes, SimpleMCPTypes;

type
  TSimpleMCPServer = class
  private
    FTools: TDictionary<String, TMCPTool>;
    FEntityInfos: TList<TMCPEntityInfo>;
    FToken: String;
    FInitialized: Boolean;

    function ProcessInitialize(aId: TJSONValue): TJSONObject;
    function ProcessToolsList(aId: TJSONValue): TJSONObject;
    function ProcessToolsCall(aId: TJSONValue; aParams: TJSONObject): TJSONObject;
    function BuildJsonRpcResponse(aId: TJSONValue; aResult: TJSONValue): TJSONObject;
    function BuildJsonRpcError(aId: TJSONValue; aCode: Integer; aMessage: String): TJSONObject;
    function BuildToolResult(aText: String; aIsError: Boolean = False): TJSONObject;
    procedure RegisterTool(aTool: TMCPTool);
  public
    constructor Create;
    destructor Destroy; override;
    class function New: TSimpleMCPServer;

    function RegisterEntity<T: class, constructor>(aQuery: iSimpleQuery; aPermissions: TMCPPermissions): TSimpleMCPServer;
    function EnableRawQuery(aQuery: iSimpleQuery): TSimpleMCPServer;
    function Token(aValue: String): TSimpleMCPServer;
    function ProcessMessage(aJSON: String): String;
    function ValidateToken(aRequestToken: String): Boolean;
    procedure StartStdio;
    procedure StartHttp(aPort: Integer);

    property Tools: TDictionary<String, TMCPTool> read FTools;
    property IsInitialized: Boolean read FInitialized;
  end;

implementation

uses
  SimpleAttributes, SimpleRTTIHelper, SimpleDAO, SimpleRTTI,
  SimpleSerializer, SimpleMigration, SimpleValidator, Data.DB,
  SimpleMCPTransport.Stdio, SimpleMCPTransport.Http;

{ TSimpleMCPServer }

constructor TSimpleMCPServer.Create;
var
  LTool: TMCPTool;
begin
  inherited Create;
  FTools := TDictionary<String, TMCPTool>.Create;
  FEntityInfos := TList<TMCPEntityInfo>.Create;
  FToken := '';
  FInitialized := False;

  LTool.Name := 'list_entities';
  LTool.Description := 'Lists all registered entities with their table names and permissions';
  LTool.InputSchema := TJSONObject.Create;
  LTool.InputSchema.AddPair('type', 'object');
  LTool.InputSchema.AddPair('properties', TJSONObject.Create);
  LTool.Handler :=
    function(const aArguments: TJSONObject): TJSONObject
    var
      LArray: TJSONArray;
      LObj: TJSONObject;
      LPermsArray: TJSONArray;
      LInfo: TMCPEntityInfo;
      LPerm: TMCPPermission;
    begin
      LArray := TJSONArray.Create;
      for LInfo in FEntityInfos do
      begin
        LObj := TJSONObject.Create;
        LObj.AddPair('table', LInfo.TableName);
        LPermsArray := TJSONArray.Create;
        for LPerm := Low(TMCPPermission) to High(TMCPPermission) do
        begin
          if LPerm in LInfo.Permissions then
            LPermsArray.Add(GetEnumName(TypeInfo(TMCPPermission), Ord(LPerm)));
        end;
        LObj.AddPair('permissions', LPermsArray);
        LArray.AddElement(LObj);
      end;
      try
        Result := BuildToolResult(LArray.ToString);
      finally
        LArray.Free;
      end;
    end;
  RegisterTool(LTool);
end;

destructor TSimpleMCPServer.Destroy;
var
  LPair: TPair<String, TMCPTool>;
begin
  for LPair in FTools do
    LPair.Value.InputSchema.Free;
  FreeAndNil(FTools);
  FreeAndNil(FEntityInfos);
  inherited;
end;

class function TSimpleMCPServer.New: TSimpleMCPServer;
begin
  Result := Self.Create;
end;

procedure TSimpleMCPServer.RegisterTool(aTool: TMCPTool);
begin
  FTools.Add(LowerCase(aTool.Name), aTool);
end;

function TSimpleMCPServer.Token(aValue: String): TSimpleMCPServer;
begin
  Result := Self;
  FToken := aValue;
end;

function TSimpleMCPServer.ValidateToken(aRequestToken: String): Boolean;
begin
  Result := (FToken = '') or (FToken = aRequestToken);
end;

function TSimpleMCPServer.ProcessInitialize(aId: TJSONValue): TJSONObject;
var
  LResult: TJSONObject;
  LCapabilities: TJSONObject;
  LServerInfo: TJSONObject;
begin
  FInitialized := True;

  LResult := TJSONObject.Create;
  LResult.AddPair('protocolVersion', MCP_PROTOCOL_VERSION);

  LCapabilities := TJSONObject.Create;
  LCapabilities.AddPair('tools', TJSONObject.Create);
  LResult.AddPair('capabilities', LCapabilities);

  LServerInfo := TJSONObject.Create;
  LServerInfo.AddPair('name', MCP_SERVER_NAME);
  LServerInfo.AddPair('version', MCP_SERVER_VERSION);
  LResult.AddPair('serverInfo', LServerInfo);

  Result := BuildJsonRpcResponse(aId, LResult);
end;

function TSimpleMCPServer.ProcessToolsList(aId: TJSONValue): TJSONObject;
var
  LToolsArray: TJSONArray;
  LToolObj: TJSONObject;
  LPair: TPair<String, TMCPTool>;
  LResult: TJSONObject;
begin
  LToolsArray := TJSONArray.Create;
  for LPair in FTools do
  begin
    LToolObj := TJSONObject.Create;
    LToolObj.AddPair('name', LPair.Value.Name);
    LToolObj.AddPair('description', LPair.Value.Description);
    LToolObj.AddPair('inputSchema', LPair.Value.InputSchema.Clone as TJSONObject);
    LToolsArray.AddElement(LToolObj);
  end;

  LResult := TJSONObject.Create;
  LResult.AddPair('tools', LToolsArray);

  Result := BuildJsonRpcResponse(aId, LResult);
end;

function TSimpleMCPServer.ProcessToolsCall(aId: TJSONValue; aParams: TJSONObject): TJSONObject;
var
  LToolName: String;
  LTool: TMCPTool;
  LArguments: TJSONObject;
  LArgsValue: TJSONValue;
  LToolResult: TJSONObject;
begin
  LToolName := aParams.GetValue<String>('name', '');
  if LToolName = '' then
    Exit(BuildJsonRpcError(aId, MCP_INVALID_PARAMS, 'Missing tool name'));

  if not FTools.TryGetValue(LowerCase(LToolName), LTool) then
    Exit(BuildJsonRpcError(aId, MCP_METHOD_NOT_FOUND, 'Tool not found: ' + LToolName));

  LArgsValue := aParams.FindValue('arguments');
  if (LArgsValue <> nil) and (LArgsValue is TJSONObject) then
    LArguments := LArgsValue as TJSONObject
  else
    LArguments := TJSONObject.Create;

  try
    try
      LToolResult := LTool.Handler(LArguments);
      Result := BuildJsonRpcResponse(aId, LToolResult);
    except
      on E: Exception do
        Result := BuildJsonRpcResponse(aId, BuildToolResult('Error: ' + E.Message, True));
    end;
  finally
    if (LArgsValue = nil) or not (LArgsValue is TJSONObject) then
      LArguments.Free;
  end;
end;

function TSimpleMCPServer.BuildJsonRpcResponse(aId: TJSONValue; aResult: TJSONValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  if aId <> nil then
    Result.AddPair('id', aId.Clone as TJSONValue)
  else
    Result.AddPair('id', TJSONNull.Create);
  Result.AddPair('result', aResult);
end;

function TSimpleMCPServer.BuildJsonRpcError(aId: TJSONValue; aCode: Integer; aMessage: String): TJSONObject;
var
  LError: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  if aId <> nil then
    Result.AddPair('id', aId.Clone as TJSONValue)
  else
    Result.AddPair('id', TJSONNull.Create);

  LError := TJSONObject.Create;
  LError.AddPair('code', TJSONNumber.Create(aCode));
  LError.AddPair('message', aMessage);
  Result.AddPair('error', LError);
end;

function TSimpleMCPServer.BuildToolResult(aText: String; aIsError: Boolean): TJSONObject;
var
  LContent: TJSONArray;
  LItem: TJSONObject;
begin
  Result := TJSONObject.Create;

  LContent := TJSONArray.Create;
  LItem := TJSONObject.Create;
  LItem.AddPair('type', 'text');
  LItem.AddPair('text', aText);
  LContent.AddElement(LItem);
  Result.AddPair('content', LContent);

  if aIsError then
    Result.AddPair('isError', TJSONTrue.Create);
end;

function TSimpleMCPServer.ProcessMessage(aJSON: String): String;
var
  LParsed: TJSONValue;
  LObj: TJSONObject;
  LMethod: String;
  LId: TJSONValue;
  LParams: TJSONObject;
  LParamsValue: TJSONValue;
  LResponse: TJSONObject;
begin
  Result := '';

  LParsed := TJSONObject.ParseJSONValue(aJSON);
  if LParsed = nil then
  begin
    LResponse := BuildJsonRpcError(nil, MCP_PARSE_ERROR, 'Parse error');
    try
      Result := LResponse.ToString;
    finally
      LResponse.Free;
    end;
    Exit;
  end;

  try
    if not (LParsed is TJSONObject) then
    begin
      LResponse := BuildJsonRpcError(nil, MCP_INVALID_REQUEST, 'Invalid request');
      try
        Result := LResponse.ToString;
      finally
        LResponse.Free;
      end;
      Exit;
    end;

    LObj := LParsed as TJSONObject;
    LId := LObj.FindValue('id');

    // Notification (no id) - return empty
    if LId = nil then
      Exit;

    LMethod := LObj.GetValue<String>('method', '');

    LParamsValue := LObj.FindValue('params');
    if (LParamsValue <> nil) and (LParamsValue is TJSONObject) then
      LParams := LParamsValue as TJSONObject
    else
      LParams := nil;

    if LMethod = 'initialize' then
      LResponse := ProcessInitialize(LId)
    else if LMethod = 'tools/list' then
      LResponse := ProcessToolsList(LId)
    else if LMethod = 'tools/call' then
    begin
      if LParams = nil then
      begin
        LResponse := BuildJsonRpcError(LId, MCP_INVALID_PARAMS, 'Missing params');
      end
      else
        LResponse := ProcessToolsCall(LId, LParams);
    end
    else if LMethod = 'ping' then
      LResponse := BuildJsonRpcResponse(LId, TJSONObject.Create)
    else
      LResponse := BuildJsonRpcError(LId, MCP_METHOD_NOT_FOUND, 'Method not found: ' + LMethod);

    try
      Result := LResponse.ToString;
    finally
      LResponse.Free;
    end;
  finally
    LParsed.Free;
  end;
end;

function TSimpleMCPServer.RegisterEntity<T>(aQuery: iSimpleQuery; aPermissions: TMCPPermissions): TSimpleMCPServer;
var
  LCtx: TRttiContext;
  LType: TRttiType;
  LTableName: String;
  LPrefix: String;
  LInfo: TMCPEntityInfo;
  LTool: TMCPTool;
  LProps: TJSONObject;
  LSchema: TJSONObject;
  LRequired: TJSONArray;
  LProp: TRttiProperty;
  LPropObj: TJSONObject;
  LPropType: String;
  LPKName: String;
begin
  Result := Self;

  LCtx := TRttiContext.Create;
  try
    LType := LCtx.GetType(TypeInfo(T));

    if not LType.IsTabela then
      raise Exception.Create('Entity must have [Tabela] attribute');

    LTableName := LType.GetAttribute<Tabela>.Name;
    LPrefix := LowerCase(LTableName);

    // Get primary key name
    LPKName := '';
    TSimpleRTTI<T>.New(nil).PrimaryKey(LPKName);

    LInfo.TableName := LTableName;
    LInfo.Permissions := aPermissions;

    // mcpRead tools
    if mcpRead in aPermissions then
    begin
      // prefix_describe
      LTool.Name := LPrefix + '_describe';
      LTool.Description := 'Describes the fields of the ' + LTableName + ' entity';
      LSchema := TJSONObject.Create;
      LSchema.AddPair('type', 'object');
      LSchema.AddPair('properties', TJSONObject.Create);
      LTool.InputSchema := LSchema;
      LTool.Handler :=
        function(const aArguments: TJSONObject): TJSONObject
        var
          LDescCtx: TRttiContext;
          LDescType: TRttiType;
          LDescProp: TRttiProperty;
          LFieldsArray: TJSONArray;
          LFieldObj: TJSONObject;
          LFieldType: String;
        begin
          LFieldsArray := TJSONArray.Create;
          LDescCtx := TRttiContext.Create;
          try
            LDescType := LDescCtx.GetType(TypeInfo(T));
            for LDescProp in LDescType.GetProperties do
            begin
              if LDescProp.IsIgnore then
                Continue;
              if not LDescProp.EhCampo then
                Continue;

              LFieldObj := TJSONObject.Create;
              LFieldObj.AddPair('name', LDescProp.FieldName);
              LFieldObj.AddPair('property', LDescProp.Name);

              case LDescProp.PropertyType.TypeKind of
                tkInteger, tkInt64:
                  LFieldType := 'integer';
                tkFloat:
                begin
                  if LDescProp.PropertyType.Handle = TypeInfo(TDateTime) then
                    LFieldType := 'datetime'
                  else
                    LFieldType := 'float';
                end;
                tkUString, tkString, tkLString, tkWString:
                  LFieldType := 'string';
                tkEnumeration:
                begin
                  if LDescProp.PropertyType.Handle = TypeInfo(Boolean) then
                    LFieldType := 'boolean'
                  else
                    LFieldType := 'enum';
                end;
              else
                LFieldType := 'unknown';
              end;
              LFieldObj.AddPair('type', LFieldType);

              if LDescProp.EhChavePrimaria then
                LFieldObj.AddPair('primaryKey', TJSONTrue.Create);
              if LDescProp.IsAutoInc then
                LFieldObj.AddPair('autoIncrement', TJSONTrue.Create);
              if LDescProp.IsNotNull then
                LFieldObj.AddPair('notNull', TJSONTrue.Create);

              LFieldsArray.AddElement(LFieldObj);
            end;
          finally
            LDescCtx.Free;
          end;
          try
            Result := BuildToolResult(LFieldsArray.ToString);
          finally
            LFieldsArray.Free;
          end;
        end;
      RegisterTool(LTool);

      // prefix_query
      LTool.Name := LPrefix + '_query';
      LTool.Description := 'Queries ' + LTableName + ' records with optional filtering, ordering and pagination';
      LSchema := TJSONObject.Create;
      LSchema.AddPair('type', 'object');
      LProps := TJSONObject.Create;
      LPropObj := TJSONObject.Create;
      LPropObj.AddPair('type', 'string');
      LPropObj.AddPair('description', 'WHERE clause for filtering');
      LProps.AddPair('where', LPropObj);
      LPropObj := TJSONObject.Create;
      LPropObj.AddPair('type', 'string');
      LPropObj.AddPair('description', 'ORDER BY clause for sorting');
      LProps.AddPair('orderBy', LPropObj);
      LPropObj := TJSONObject.Create;
      LPropObj.AddPair('type', 'integer');
      LPropObj.AddPair('description', 'Number of records to skip');
      LProps.AddPair('skip', LPropObj);
      LPropObj := TJSONObject.Create;
      LPropObj.AddPair('type', 'integer');
      LPropObj.AddPair('description', 'Number of records to take');
      LProps.AddPair('take', LPropObj);
      LSchema.AddPair('properties', LProps);
      LTool.InputSchema := LSchema;
      LTool.Handler :=
        function(const aArguments: TJSONObject): TJSONObject
        var
          LWhere, LOrderBy: String;
          LSkip, LTake: Integer;
          LDAO: iSimpleDAO<T>;
          LList: TObjectList<T>;
          LJsonArray: TJSONArray;
        begin
          LWhere := aArguments.GetValue<String>('where', '');
          LOrderBy := aArguments.GetValue<String>('orderBy', '');
          LSkip := aArguments.GetValue<Integer>('skip', 0);
          LTake := aArguments.GetValue<Integer>('take', 0);

          LDAO := TSimpleDAO<T>.New(aQuery);
          LList := TObjectList<T>.Create;
          try
            if (LWhere <> '') or (LOrderBy <> '') or (LSkip > 0) or (LTake > 0) then
            begin
              if LWhere <> '' then
                LDAO.SQL.Where(LWhere);
              if LOrderBy <> '' then
                LDAO.SQL.OrderBy(LOrderBy);
              if LSkip > 0 then
                LDAO.SQL.Skip(LSkip);
              if LTake > 0 then
                LDAO.SQL.Take(LTake);
              LDAO.SQL.&End.Find(LList);
            end
            else
              LDAO.Find(LList);

            LJsonArray := TSimpleSerializer.EntityListToJSONArray<T>(LList);
            try
              Result := BuildToolResult(LJsonArray.ToString);
            finally
              LJsonArray.Free;
            end;
          finally
            LList.Free;
          end;
        end;
      RegisterTool(LTool);

      // prefix_get
      LTool.Name := LPrefix + '_get';
      LTool.Description := 'Gets a single ' + LTableName + ' record by ID';
      LSchema := TJSONObject.Create;
      LSchema.AddPair('type', 'object');
      LProps := TJSONObject.Create;
      LPropObj := TJSONObject.Create;
      LPropObj.AddPair('type', 'integer');
      LPropObj.AddPair('description', 'The ID of the record to retrieve');
      LProps.AddPair('id', LPropObj);
      LSchema.AddPair('properties', LProps);
      LRequired := TJSONArray.Create;
      LRequired.Add('id');
      LSchema.AddPair('required', LRequired);
      LTool.InputSchema := LSchema;
      LTool.Handler :=
        function(const aArguments: TJSONObject): TJSONObject
        var
          LId: Integer;
          LDAO: iSimpleDAO<T>;
          LEntity: T;
          LJsonObj: TJSONObject;
        begin
          LId := aArguments.GetValue<Integer>('id', 0);
          if LId = 0 then
          begin
            Result := BuildToolResult('Missing or invalid id parameter', True);
            Exit;
          end;

          LDAO := TSimpleDAO<T>.New(aQuery);
          LEntity := LDAO.Find(LId);
          if TObject(LEntity) = nil then
          begin
            Result := BuildToolResult('Record not found with id ' + IntToStr(LId), True);
            Exit;
          end;
          try
            LJsonObj := TSimpleSerializer.EntityToJSON<T>(LEntity);
            try
              Result := BuildToolResult(LJsonObj.ToString);
            finally
              LJsonObj.Free;
            end;
          finally
            TObject(LEntity).Free;
          end;
        end;
      RegisterTool(LTool);
    end;

    // mcpInsert
    if mcpInsert in aPermissions then
    begin
      LTool.Name := LPrefix + '_insert';
      LTool.Description := 'Inserts a new record into ' + LTableName;
      LSchema := TJSONObject.Create;
      LSchema.AddPair('type', 'object');
      LProps := TJSONObject.Create;
      LPropObj := TJSONObject.Create;
      LPropObj.AddPair('type', 'object');
      LPropObj.AddPair('description', 'The entity data to insert as a JSON object');
      LProps.AddPair('data', LPropObj);
      LSchema.AddPair('properties', LProps);
      LRequired := TJSONArray.Create;
      LRequired.Add('data');
      LSchema.AddPair('required', LRequired);
      LTool.InputSchema := LSchema;
      LTool.Handler :=
        function(const aArguments: TJSONObject): TJSONObject
        var
          LDataValue: TJSONValue;
          LDataObj: TJSONObject;
          LDAO: iSimpleDAO<T>;
          LEntity: T;
        begin
          LDataValue := aArguments.FindValue('data');
          if (LDataValue = nil) or not (LDataValue is TJSONObject) then
          begin
            Result := BuildToolResult('Missing or invalid data parameter', True);
            Exit;
          end;

          LDataObj := LDataValue as TJSONObject;
          LEntity := TSimpleSerializer.JSONToEntity<T>(LDataObj);
          try
            TSimpleValidator.Validate(TObject(LEntity));
            LDAO := TSimpleDAO<T>.New(aQuery);
            LDAO.Insert(LEntity);
            Result := BuildToolResult('Record inserted successfully');
          finally
            TObject(LEntity).Free;
          end;
        end;
      RegisterTool(LTool);
    end;

    // mcpUpdate
    if mcpUpdate in aPermissions then
    begin
      LTool.Name := LPrefix + '_update';
      LTool.Description := 'Updates an existing record in ' + LTableName;
      LSchema := TJSONObject.Create;
      LSchema.AddPair('type', 'object');
      LProps := TJSONObject.Create;
      LPropObj := TJSONObject.Create;
      LPropObj.AddPair('type', 'object');
      LPropObj.AddPair('description', 'The entity data to update as a JSON object (must include primary key)');
      LProps.AddPair('data', LPropObj);
      LSchema.AddPair('properties', LProps);
      LRequired := TJSONArray.Create;
      LRequired.Add('data');
      LSchema.AddPair('required', LRequired);
      LTool.InputSchema := LSchema;
      LTool.Handler :=
        function(const aArguments: TJSONObject): TJSONObject
        var
          LDataValue: TJSONValue;
          LDataObj: TJSONObject;
          LDAO: iSimpleDAO<T>;
          LEntity: T;
        begin
          LDataValue := aArguments.FindValue('data');
          if (LDataValue = nil) or not (LDataValue is TJSONObject) then
          begin
            Result := BuildToolResult('Missing or invalid data parameter', True);
            Exit;
          end;

          LDataObj := LDataValue as TJSONObject;
          LEntity := TSimpleSerializer.JSONToEntity<T>(LDataObj);
          try
            TSimpleValidator.Validate(TObject(LEntity));
            LDAO := TSimpleDAO<T>.New(aQuery);
            LDAO.Update(LEntity);
            Result := BuildToolResult('Record updated successfully');
          finally
            TObject(LEntity).Free;
          end;
        end;
      RegisterTool(LTool);
    end;

    // mcpDelete
    if mcpDelete in aPermissions then
    begin
      LTool.Name := LPrefix + '_delete';
      LTool.Description := 'Deletes a record from ' + LTableName + ' by ID';
      LSchema := TJSONObject.Create;
      LSchema.AddPair('type', 'object');
      LProps := TJSONObject.Create;
      LPropObj := TJSONObject.Create;
      LPropObj.AddPair('type', 'string');
      LPropObj.AddPair('description', 'The ID value of the record to delete');
      LProps.AddPair('id', LPropObj);
      LSchema.AddPair('properties', LProps);
      LRequired := TJSONArray.Create;
      LRequired.Add('id');
      LSchema.AddPair('required', LRequired);
      LTool.InputSchema := LSchema;
      LTool.Handler :=
        function(const aArguments: TJSONObject): TJSONObject
        var
          LIdStr: String;
          LDAO: iSimpleDAO<T>;
        begin
          LIdStr := aArguments.GetValue<String>('id', '');
          if LIdStr = '' then
          begin
            Result := BuildToolResult('Missing or invalid id parameter', True);
            Exit;
          end;

          LDAO := TSimpleDAO<T>.New(aQuery);
          LDAO.Delete(LPKName, LIdStr);
          Result := BuildToolResult('Record deleted successfully');
        end;
      RegisterTool(LTool);
    end;

    // mcpCount
    if mcpCount in aPermissions then
    begin
      LTool.Name := LPrefix + '_count';
      LTool.Description := 'Counts records in ' + LTableName + ' with optional filtering';
      LSchema := TJSONObject.Create;
      LSchema.AddPair('type', 'object');
      LProps := TJSONObject.Create;
      LPropObj := TJSONObject.Create;
      LPropObj.AddPair('type', 'string');
      LPropObj.AddPair('description', 'Optional WHERE clause for filtering');
      LProps.AddPair('where', LPropObj);
      LSchema.AddPair('properties', LProps);
      LTool.InputSchema := LSchema;
      LTool.Handler :=
        function(const aArguments: TJSONObject): TJSONObject
        var
          LWhere: String;
          LDAO: iSimpleDAO<T>;
          LCount: Integer;
        begin
          LWhere := aArguments.GetValue<String>('where', '');
          LDAO := TSimpleDAO<T>.New(aQuery);

          if LWhere <> '' then
            LCount := LDAO.SQL.Where(LWhere).&End.Count
          else
            LCount := LDAO.Count;

          Result := BuildToolResult(IntToStr(LCount));
        end;
      RegisterTool(LTool);
    end;

    // mcpDDL
    if mcpDDL in aPermissions then
    begin
      LTool.Name := LPrefix + '_ddl';
      LTool.Description := 'Generates the CREATE TABLE DDL for ' + LTableName;
      LSchema := TJSONObject.Create;
      LSchema.AddPair('type', 'object');
      LSchema.AddPair('properties', TJSONObject.Create);
      LTool.InputSchema := LSchema;
      LTool.Handler :=
        function(const aArguments: TJSONObject): TJSONObject
        var
          LDDL: String;
        begin
          LDDL := TSimpleMigration.GenerateCreateTable<T>(aQuery.SQLType);
          Result := BuildToolResult(LDDL);
        end;
      RegisterTool(LTool);
    end;
  finally
    LCtx.Free;
  end;

  FEntityInfos.Add(LInfo);
end;

function TSimpleMCPServer.EnableRawQuery(aQuery: iSimpleQuery): TSimpleMCPServer;
var
  LTool: TMCPTool;
  LSchema: TJSONObject;
  LProps: TJSONObject;
  LPropObj: TJSONObject;
  LRequired: TJSONArray;
begin
  Result := Self;

  LTool.Name := 'raw_query';
  LTool.Description := 'Executes a raw SQL SELECT query and returns results as JSON';
  LSchema := TJSONObject.Create;
  LSchema.AddPair('type', 'object');
  LProps := TJSONObject.Create;
  LPropObj := TJSONObject.Create;
  LPropObj.AddPair('type', 'string');
  LPropObj.AddPair('description', 'The SQL SELECT query to execute');
  LProps.AddPair('sql', LPropObj);
  LSchema.AddPair('properties', LProps);
  LRequired := TJSONArray.Create;
  LRequired.Add('sql');
  LSchema.AddPair('required', LRequired);
  LTool.InputSchema := LSchema;
  LTool.Handler :=
    function(const aArguments: TJSONObject): TJSONObject
    var
      LSQL: String;
      LUpperSQL: String;
      LResultArray: TJSONArray;
      LRowObj: TJSONObject;
      LField: TField;
      I: Integer;
    begin
      LSQL := aArguments.GetValue<String>('sql', '');
      if LSQL = '' then
      begin
        Result := BuildToolResult('Missing sql parameter', True);
        Exit;
      end;

      LUpperSQL := UpperCase(Trim(LSQL));

      // Security: only allow SELECT statements
      if not LUpperSQL.StartsWith('SELECT') then
      begin
        Result := BuildToolResult('Only SELECT statements are allowed', True);
        Exit;
      end;

      // Block semicolons (prevents multi-statement injection)
      if Pos(';', LUpperSQL) > 0 then
      begin
        Result := BuildToolResult('Semicolons are not allowed in queries', True);
        Exit;
      end;

      // Block dangerous keywords
      if (Pos('INSERT ', LUpperSQL) > 0) or
         (Pos('UPDATE ', LUpperSQL) > 0) or
         (Pos('DELETE ', LUpperSQL) > 0) or
         (Pos('DROP ', LUpperSQL) > 0) or
         (Pos('ALTER ', LUpperSQL) > 0) or
         (Pos('CREATE ', LUpperSQL) > 0) or
         (Pos('TRUNCATE ', LUpperSQL) > 0) or
         (Pos('EXEC ', LUpperSQL) > 0) or
         (Pos('EXECUTE ', LUpperSQL) > 0) or
         (Pos('GRANT ', LUpperSQL) > 0) or
         (Pos('REVOKE ', LUpperSQL) > 0) or
         (Pos(' INTO ', LUpperSQL) > 0) then
      begin
        Result := BuildToolResult('SQL contains blocked keywords', True);
        Exit;
      end;

      aQuery.SQL.Clear;
      aQuery.SQL.Add(LSQL);
      aQuery.Open;

      LResultArray := TJSONArray.Create;
      try
        aQuery.DataSet.First;
        while not aQuery.DataSet.Eof do
        begin
          LRowObj := TJSONObject.Create;
          for I := 0 to aQuery.DataSet.FieldCount - 1 do
          begin
            LField := aQuery.DataSet.Fields[I];
            if LField.IsNull then
              LRowObj.AddPair(LField.FieldName, TJSONNull.Create)
            else
            begin
              case LField.DataType of
                ftInteger, ftSmallint, ftWord, ftAutoInc, ftLargeint:
                  LRowObj.AddPair(LField.FieldName, TJSONNumber.Create(LField.AsLargeInt));
                ftFloat, ftCurrency, ftBCD, ftFMTBcd, ftExtended, ftSingle:
                  LRowObj.AddPair(LField.FieldName, TJSONNumber.Create(LField.AsFloat));
                ftBoolean:
                begin
                  if LField.AsBoolean then
                    LRowObj.AddPair(LField.FieldName, TJSONTrue.Create)
                  else
                    LRowObj.AddPair(LField.FieldName, TJSONFalse.Create);
                end;
              else
                LRowObj.AddPair(LField.FieldName, LField.AsString);
              end;
            end;
          end;
          LResultArray.AddElement(LRowObj);
          aQuery.DataSet.Next;
        end;

        Result := BuildToolResult(LResultArray.ToString);
      finally
        LResultArray.Free;
      end;
    end;
  RegisterTool(LTool);
end;

procedure TSimpleMCPServer.StartStdio;
begin
  SimpleMCPTransport.Stdio.RunStdioLoop(Self);
end;

procedure TSimpleMCPServer.StartHttp(aPort: Integer);
begin
  SimpleMCPTransport.Http.StartHttpTransport(Self, aPort);
end;

end.

unit SimpleLogger;

interface

uses
  Data.DB, System.Classes;

type
  iSimpleQueryLogger = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    procedure Log(const aSQL: string; aParams: TParams; aDurationMs: Int64);
  end;

  TSimpleQueryLoggerConsole = class(TInterfacedObject, iSimpleQueryLogger)
  public
    constructor Create;
    class function New: iSimpleQueryLogger;
    procedure Log(const aSQL: string; aParams: TParams; aDurationMs: Int64);
  end;

implementation

uses
  System.SysUtils,
  System.Variants
  {$IFDEF MSWINDOWS}
  , Winapi.Windows
  {$ENDIF};

{ TSimpleQueryLoggerConsole }

constructor TSimpleQueryLoggerConsole.Create;
begin
  inherited;
end;

class function TSimpleQueryLoggerConsole.New: iSimpleQueryLogger;
begin
  Result := Self.Create;
end;

procedure TSimpleQueryLoggerConsole.Log(const aSQL: string; aParams: TParams; aDurationMs: Int64);
var
  LogMsg: string;
  I: Integer;
begin
  LogMsg := System.SysUtils.Format('[SimpleORM] SQL: %s | Duration: %dms', [aSQL, aDurationMs]);
  if Assigned(aParams) and (aParams.Count > 0) then
  begin
    LogMsg := LogMsg + ' | Params: ';
    for I := 0 to aParams.Count - 1 do
      LogMsg := LogMsg + aParams[I].Name + '=' + VarToStr(aParams[I].Value) + '; ';
  end;
  {$IFDEF MSWINDOWS}
  OutputDebugString(PChar(LogMsg));
  {$ENDIF}
  {$IFDEF CONSOLE}
  WriteLn(LogMsg);
  {$ENDIF}
end;

end.

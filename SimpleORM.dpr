program SimpleORM;

uses
  Vcl.Forms,
  SimpleDAO in 'src\SimpleDAO.pas',
  SimpleInterface in 'src\SimpleInterface.pas',
  SimpleAttributes in 'src\SimpleAttributes.pas',
  SimpleRTTI in 'src\SimpleRTTI.pas',
  SimpleSQL in 'src\SimpleSQL.pas',
  SimpleQueryFiredac in 'src\SimpleQueryFiredac.pas',
  SimpleQueryRestDW in 'src\SimpleQueryRestDW.pas',
  SimpleSerializer in 'src\SimpleSerializer.pas',
  SimpleQueryHorse in 'src\SimpleQueryHorse.pas',
  SimpleHorseRouter in 'src\SimpleHorseRouter.pas',
  SimpleQuerySupabase in 'src\SimpleQuerySupabase.pas',
  SimpleSupabaseAuth in 'src\SimpleSupabaseAuth.pas',
  SimpleSupabaseRealtime in 'src\SimpleSupabaseRealtime.pas',
  SimpleDataMigration in 'src\SimpleDataMigration.pas',
  SimpleEvents in 'src\SimpleEvents.pas',
  SimpleQueryOptimizer in 'src\SimpleQueryOptimizer.pas',
  SimpleNLQuery in 'src\SimpleNLQuery.pas',
  SimpleSwagger in 'src\SimpleSwagger.pas',
  SimpleSeeder in 'src\SimpleSeeder.pas',
  SimpleAutoIndex in 'src\SimpleAutoIndex.pas',
  SimpleSkillMessaging in 'src\SimpleSkillMessaging.pas',
  SimpleExportSheets in 'src\SimpleExportSheets.pas';

{$R *.res}

begin
  Application.Initialize;
  ReportMemoryLeaksOnShutdown := True;
  Application.MainFormOnTaskbar := True;
  Application.Run;
end.

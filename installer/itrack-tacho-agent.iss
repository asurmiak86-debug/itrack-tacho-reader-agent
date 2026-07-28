; i-track Tacho Agent — instalator Windows
; Wersja wykorzystuje:
; - Node.js dołączony w dist\runtime\node.exe
; - komplet node_modules z natywnym pcsclite.node
; - NSSM do uruchamiania agenta jako usługi Windows
; - app.ps1 jako panel i ikona w zasobniku systemowym

#define MyAppName "i-track Tacho Agent"
#define MyAppVersion "0.5.1"
#define MyAppPublisher "AS-NET / i-track.pl"
#define MyAppURL "https://i-track.pl"
#define MyServiceName "iTrackTachoAgent"

[Setup]
AppId={{B4B8F3B0-6C2A-4E8E-9C3E-181AC71A60E1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL=https://ddd.i-track.pl

DefaultDirName={autopf}\i-track\Tacho Agent
DefaultGroupName=i-track
DisableProgramGroupPage=yes

PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

OutputDir=..\output
OutputBaseFilename=i-track-Tacho-Agent-Setup-{#MyAppVersion}

SetupIconFile=..\assets\itrack.ico
UninstallDisplayIcon={app}\assets\itrack.ico
UninstallDisplayName={#MyAppName}

Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes

CloseApplications=yes
RestartApplications=no

[Languages]
Name: "polish"; MessagesFile: "compiler:Languages\Polish.isl"

[Files]
; Pełna aplikacja przygotowana przez scripts\build-windows.ps1:
; runtime\node.exe, node_modules, agent.js, diagnostic.js, app.ps1 itd.
Source: "..\dist\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; NSSM — wrapper poprawnej usługi Windows
Source: "nssm.exe"; DestDir: "{app}"; Flags: ignoreversion

; Branding i-track
Source: "..\assets\itrack.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "..\assets\itrack-gray.ico"; DestDir: "{app}\assets"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\assets\itrack-yellow.ico"; DestDir: "{app}\assets"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\assets\itrack-blue.ico"; DestDir: "{app}\assets"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\assets\itrack-green.ico"; DestDir: "{app}\assets"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\assets\itrack-red.ico"; DestDir: "{app}\assets"; Flags: ignoreversion skipifsourcedoesntexist

; Pliki informacyjne
Source: "..\.env.example"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Dirs]
Name: "{commonappdata}\i-track\Tacho Agent"; Permissions: users-modify
Name: "{commonappdata}\i-track\Tacho Agent\logs"; Permissions: users-modify

[Icons]
; Panel statusu w menu Start
Name: "{group}\{#MyAppName} — status"; \
    Filename: "powershell.exe"; \
    Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\app.ps1"""; \
    WorkingDir: "{app}"; \
    IconFilename: "{app}\assets\itrack.ico"

; Diagnostyka połączenia
Name: "{group}\{#MyAppName} — diagnostyka"; \
    Filename: "{app}\diagnostic.cmd"; \
    WorkingDir: "{app}"; \
    IconFilename: "{app}\assets\itrack.ico"; \
    Check: DiagnosticExists

; Folder logów
Name: "{group}\{#MyAppName} — logi"; \
    Filename: "{commonappdata}\i-track\Tacho Agent\logs"

; Platforma DDD
Name: "{group}\ddd.i-track.pl"; \
    Filename: "https://ddd.i-track.pl"

; Automatyczny start ikony po zalogowaniu użytkownika
Name: "{userstartup}\i-track Tacho Agent"; \
    Filename: "powershell.exe"; \
    Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\app.ps1"""; \
    WorkingDir: "{app}"; \
    IconFilename: "{app}\assets\itrack.ico"

[Run]
; Zatrzymanie starej usługi, jeśli już istnieje
Filename: "{cmd}"; \
    Parameters: "/C sc.exe stop {#MyServiceName}"; \
    Flags: runhidden waituntilterminated; \
    Check: ServiceExists; \
    StatusMsg: "Zatrzymywanie poprzedniej wersji usługi..."

; Usunięcie poprzedniej definicji usługi
Filename: "{cmd}"; \
    Parameters: "/C sc.exe delete {#MyServiceName}"; \
    Flags: runhidden waituntilterminated; \
    Check: ServiceExists; \
    StatusMsg: "Usuwanie poprzedniej wersji usługi..."

; Windows może potrzebować chwili na usunięcie usługi
Filename: "{cmd}"; \
    Parameters: "/C timeout /T 2 /NOBREAK"; \
    Flags: runhidden waituntilterminated

; Rejestracja Node.js jako usługi za pomocą NSSM
Filename: "{app}\nssm.exe"; \
    Parameters: "install {#MyServiceName} ""{app}\runtime\node.exe"""; \
    Flags: runhidden waituntilterminated; \
    StatusMsg: "Rejestrowanie usługi i-track..."

; agent.js jako parametr node.exe
Filename: "{app}\nssm.exe"; \
    Parameters: "set {#MyServiceName} AppParameters ""{app}\agent.js"""; \
    Flags: runhidden waituntilterminated

; Katalog roboczy
Filename: "{app}\nssm.exe"; \
    Parameters: "set {#MyServiceName} AppDirectory ""{app}"""; \
    Flags: runhidden waituntilterminated

; Nazwa widoczna w services.msc
Filename: "{app}\nssm.exe"; \
    Parameters: "set {#MyServiceName} DisplayName ""{#MyAppName}"""; \
    Flags: runhidden waituntilterminated

; Opis usługi
Filename: "{app}\nssm.exe"; \
    Parameters: "set {#MyServiceName} Description ""Agent czytnika kart tachografu i-track — łączy fizyczny czytnik z platformą ddd.i-track.pl."""; \
    Flags: runhidden waituntilterminated

; Automatyczny start usługi
Filename: "{app}\nssm.exe"; \
    Parameters: "set {#MyServiceName} Start SERVICE_AUTO_START"; \
    Flags: runhidden waituntilterminated

; Restart po awarii procesu Node.js
Filename: "{app}\nssm.exe"; \
    Parameters: "set {#MyServiceName} AppExit Default Restart"; \
    Flags: runhidden waituntilterminated

Filename: "{app}\nssm.exe"; \
    Parameters: "set {#MyServiceName} AppRestartDelay 5000"; \
    Flags: runhidden waituntilterminated

; Log standardowego wyjścia aplikacji
Filename: "{app}\nssm.exe"; \
    Parameters: "set {#MyServiceName} AppStdout ""{commonappdata}\i-track\Tacho Agent\logs\stdout.log"""; \
    Flags: runhidden waituntilterminated

; Log błędów
Filename: "{app}\nssm.exe"; \
    Parameters: "set {#MyServiceName} AppStderr ""{commonappdata}\i-track\Tacho Agent\logs\stderr.log"""; \
    Flags: runhidden waituntilterminated

; Rotacja plików logów
Filename: "{app}\nssm.exe"; \
    Parameters: "set {#MyServiceName} AppRotateFiles 1"; \
    Flags: runhidden waituntilterminated

Filename: "{app}\nssm.exe"; \
    Parameters: "set {#MyServiceName} AppRotateOnline 1"; \
    Flags: runhidden waituntilterminated

Filename: "{app}\nssm.exe"; \
    Parameters: "set {#MyServiceName} AppRotateBytes 5242880"; \
    Flags: runhidden waituntilterminated

; Uruchomienie usługi
Filename: "{app}\nssm.exe"; \
    Parameters: "start {#MyServiceName}"; \
    Flags: runhidden waituntilterminated; \
    StatusMsg: "Uruchamianie usługi i-track..."

; Uruchomienie panelu i ikony obok zegarka
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\app.ps1"""; \
    WorkingDir: "{app}"; \
    Flags: nowait postinstall skipifsilent; \
    Description: "Uruchom panel statusu i-track Tacho Agent"

[UninstallRun]
; Zatrzymanie usługi przed usunięciem programu
Filename: "{app}\nssm.exe"; \
    Parameters: "stop {#MyServiceName}"; \
    Flags: runhidden waituntilterminated skipifdoesntexist

; Usunięcie usługi z Windows
Filename: "{app}\nssm.exe"; \
    Parameters: "remove {#MyServiceName} confirm"; \
    Flags: runhidden waituntilterminated skipifdoesntexist

[UninstallDelete]
Type: files; Name: "{userstartup}\i-track Tacho Agent.lnk"

; Logów i konfiguracji w ProgramData nie usuwamy automatycznie,
; żeby nie utracić ustawień, identyfikatora i historii diagnostycznej.

[Code]
function ServiceExists: Boolean;
var
  ResultCode: Integer;
begin
  Exec(
    ExpandConstant('{cmd}'),
    '/C sc.exe query {#MyServiceName}',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );

  Result := ResultCode = 0;
end;

function DiagnosticExists: Boolean;
begin
  Result := FileExists(
    ExpandConstant('{app}\diagnostic.cmd')
  );
end;

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;

  if not Exec(
    ExpandConstant('{cmd}'),
    '/C sc.exe query SCardSvr',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
  begin
    MsgBox(
      'Nie udało się sprawdzić usługi Windows Smart Card.',
      mbInformation,
      MB_OK
    );
  end;
end;

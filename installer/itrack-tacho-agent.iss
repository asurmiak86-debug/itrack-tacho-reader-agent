; i-track Tacho Agent — instalator Windows (Inno Setup 6).
; Buduje się automatycznie przez .github/workflows/build-windows.yml (GitHub Actions,
; runner Windows) — NIE da się zbudować z tego serwera Linux (natywny moduł czytnika kart
; trzeba skompilować na docelowej platformie).
;
; Zakres instalacji:
;  - kopiuje dist\itrack-tacho-agent.exe (spakowany przez pkg, klient NIE potrzebuje Node.js),
;    app.ps1 (okno statusu + ikona w zasobniku), warianty ikon (assets\itrack-*.ico),
;  - rejestruje usługę Windows przez NSSM (installer\nssm.exe — MUSISZ dodać przed buildem,
;    64-bit, https://nssm.cc/download) — zwykłe `sc.exe create` wskazujące na zwykły proces
;    Node/pkg NIE działa niezawodnie jako usługa Windows (proces nie implementuje protokołu
;    Service Control Manager), więc świadomie używamy sprawdzonego, dedykowanego narzędzia
;    zamiast ryzykować cichy błąd "1053: usługa nie odpowiedziała na czas",
;  - dodaje skrót do folderu Autostart bieżącego użytkownika dla app.ps1 (okno/ikona wymaga
;    sesji zalogowanego użytkownika — usługa działa niezależnie, w tle, zawsze, nawet bez
;    zalogowanego użytkownika).

#define MyAppName "i-track Tacho Agent"
#define MyAppVersion "0.5.0"
#define MyAppPublisher "i-track"
#define MyAppExeName "itrack-tacho-agent.exe"
#define MyServiceName "iTrackTachoAgent"

[Setup]
AppId={{B4B8F3B0-6C2A-4E8E-9C3E-ITRACKTACHOAGENT}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\i-track\Tacho Agent
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=..\output
OutputBaseFilename=i-track-Tacho-Agent-Setup-{#MyAppVersion}
SetupIconFile=..\assets\itrack.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "polish"; MessagesFile: "compiler:Languages\Polish.isl"

[Files]
Source: "..\dist\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\app.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\itrack.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "..\assets\itrack-gray.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "..\assets\itrack-yellow.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "..\assets\itrack-blue.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "..\assets\itrack-green.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "..\assets\itrack-red.ico"; DestDir: "{app}\assets"; Flags: ignoreversion
Source: "..\.env.example"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "nssm.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName} — status"; Filename: "powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\app.ps1"""; IconFilename: "{app}\assets\itrack.ico"
Name: "{userstartup}\i-track Tacho Agent (status)"; Filename: "powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\app.ps1"""; IconFilename: "{app}\assets\itrack.ico"

[Run]
; NSSM: rejestruje .exe jako prawdziwą usługę Windows (poprawnie odpowiada na SCM, w
; przeciwieństwie do gołego `sc.exe create` wskazującego wprost na zwykły proces).
Filename: "{app}\nssm.exe"; Parameters: "install {#MyServiceName} ""{app}\{#MyAppExeName}"""; Flags: runhidden; StatusMsg: "Rejestrowanie usługi..."
Filename: "{app}\nssm.exe"; Parameters: "set {#MyServiceName} DisplayName ""{#MyAppName}"""; Flags: runhidden
Filename: "{app}\nssm.exe"; Parameters: "set {#MyServiceName} Description ""Agent czytnika kart tachografu i-track — łączy fizyczny czytnik z panelem ddd.i-track.pl."""; Flags: runhidden
Filename: "{app}\nssm.exe"; Parameters: "set {#MyServiceName} Start SERVICE_AUTO_START"; Flags: runhidden
Filename: "{app}\nssm.exe"; Parameters: "set {#MyServiceName} AppExit Default Restart"; Flags: runhidden
Filename: "{app}\nssm.exe"; Parameters: "set {#MyServiceName} AppRestartDelay 5000"; Flags: runhidden
Filename: "{app}\nssm.exe"; Parameters: "start {#MyServiceName}"; Flags: runhidden; StatusMsg: "Uruchamianie usługi..."
Filename: "powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\app.ps1"""; Flags: nowait postinstall skipifsilent; Description: "Uruchom okno statusu teraz"

[UninstallRun]
Filename: "{app}\nssm.exe"; Parameters: "stop {#MyServiceName}"; Flags: runhidden
Filename: "{app}\nssm.exe"; Parameters: "remove {#MyServiceName} confirm"; Flags: runhidden

[UninstallDelete]
Type: files; Name: "{userstartup}\i-track Tacho Agent (status).lnk"

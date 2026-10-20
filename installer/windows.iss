; Inno-Setup-Skript für den Windows-Installer.
; Wird in GitHub Actions gebaut:  ISCC /DAppVersion=1.2.3 installer\windows.iss
; Installation pro Benutzer (ohne Administratorrechte), damit Auto-Updates still laufen können.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppName "Führerschein Quiz Südtirol"
#define AppExe "FuehrerscheinQuiz.exe"

[Setup]
AppId={{7E2B9C41-5A3D-4F8E-9B6C-2D1A0F4E8C73}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=laufish44
AppPublisherURL=https://github.com/laufish44/fuehrerschein-quiz-suedtirol
AppSupportURL=https://github.com/laufish44/fuehrerschein-quiz-suedtirol/issues
AppUpdatesURL=https://github.com/laufish44/fuehrerschein-quiz-suedtirol/releases
DefaultDirName={localappdata}\Programs\FuehrerscheinQuizSuedtirol
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=FuehrerscheinQuiz-{#AppVersion}-windows-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force
RestartApplications=no

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "it"; MessagesFile: "compiler:Languages\Italian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Alte Dateien früherer Versionen entfernen (die App liegt komplett im Programmordner).
Type: filesandordirs; Name: "{app}\data"

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; Läuft auch bei stillen Updates (/VERYSILENT) und startet die App danach neu.
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall

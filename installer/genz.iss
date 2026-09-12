; Windows installer for GENz+, built with Inno Setup 6.
;
; Compile on Windows with:
;     "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\genz.iss
;
; It packages whatever is in SourceDir — by default the folder `flutter build
; windows --release` produces. To build from a folder downloaded from GitHub
; Actions instead, override it:
;     ISCC.exe /DSourceDir="C:\path\to\genz-windows" installer\genz.iss
;
; The result lands in installer\Output.

#define AppName "GENz+"
#define AppVersion "1.3.7"
#define AppPublisher "GENz+"
#define AppExe "genz.exe"

#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
; Never change AppId: it is how Windows recognises an existing install, so
; keeping it stable is what makes the next version upgrade in place rather
; than appearing a second time in Installed apps.
AppId={{8F3C1A62-4D7B-4E9A-9C2E-5B71A0D6F4E3}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=GENzPlus-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Flutter builds 64-bit only.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Offers "for everyone" (needs admin) or "just me" (does not), so someone
; without an administrator password can still install it.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; The desktop shortcut is a choice, ticked by default.
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; The whole build folder: genz.exe alone will not start — it needs the DLLs
; beside it and the data\ folder holding the Flutter assets.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Flutter's Windows build does not carry the Visual C++ runtime, and the app
// will not start without it. Present on most Windows 10/11 machines, so this
// warns and carries on rather than blocking the install.
function InitializeSetup(): Boolean;
begin
  Result := True;
  if not FileExists(ExpandConstant('{sys}\msvcp140.dll')) then
  begin
    MsgBox('GENz+ needs the Microsoft Visual C++ Redistributable (x64), which does not appear to be installed.'
      + #13#10#13#10 + 'Setup will continue, but if GENz+ does not start, install it from:'
      + #13#10 + 'https://aka.ms/vs/17/release/vc_redist.x64.exe',
      mbInformation, MB_OK);
  end;
end;

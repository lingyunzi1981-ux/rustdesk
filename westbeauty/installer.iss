#include "native-build-date.iss"
#define AppVersion "2.1.0"
[Setup]
AppId={{B5A4D980-6F1E-4E20-9A0A-57DFAE516B21}
AppName=西美远控
AppVersion={#AppVersion}
AppPublisher=West Beauty Group
DefaultDirName={autopf}\West Beauty Group\西美远控
DefaultGroupName=西美远控
UninstallDisplayName=西美远控
UninstallDisplayIcon={app}\WestBeautyRemote.exe
OutputDir=SignOutput
OutputBaseFilename=西美远控-Setup-x64-2.1.0-rc1
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
SetupIconFile=flutter\windows\runner\resources\app_icon.ico
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
VersionInfoDescription=西美远控安装程序
VersionInfoCompany=West Beauty Group
MinVersion=10.0

[Languages]
Name: "chinesesimp"; MessagesFile: "ChineseSimplified.isl"

[Files]
Source: "rustdesk\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Only remove the obsolete V2 executable, preserving settings and all user data.
Type: files; Name: "{app}\rustdesk.exe"

[Registry]
Root: HKLM; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{{B5A4D980-6F1E-4E20-9A0A-57DFAE516B21}_is1"; ValueType: string; ValueName: "BuildDate"; ValueData: "{#NativeBuildDate}"; Flags: uninsdeletevalue
Root: HKLM; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{{B5A4D980-6F1E-4E20-9A0A-57DFAE516B21}_is1"; ValueType: string; ValueName: "Version"; ValueData: "1.4.9"; Flags: uninsdeletevalue

[Icons]
Name: "{autodesktop}\西美远控"; Filename: "{app}\WestBeautyRemote.exe"; WorkingDir: "{app}"
Name: "{group}\西美远控"; Filename: "{app}\WestBeautyRemote.exe"; WorkingDir: "{app}"
Name: "{group}\卸载西美远控"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\WestBeautyRemote.exe"; Description: "启动西美远控"; Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallRun]
; Remove an existing user-enabled service before removing its executable.
Filename: "{app}\WestBeautyRemote.exe"; Parameters: "--uninstall-service"; Flags: runhidden waituntilterminated; RunOnceId: "StopWestBeautyService"; Check: HasWestBeautyService

[Code]
function HasWestBeautyService: Boolean;
begin
  Result := RegKeyExists(HKLM, 'SYSTEM\CurrentControlSet\Services\WestBeautyRemote');
end;

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
function GetWestBeautyUninstallKey(Param: String): String;
begin
  Result := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{B5A4D980-6F1E-4E20-9A0A-57DFAE516B21}_is1';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  UninstallKey, ActualBuildDate: String;
begin
  if CurStep = ssPostInstall then
  begin
    UninstallKey := GetWestBeautyUninstallKey('');
    if not RegWriteStringValue(HKLM64, UninstallKey, 'BuildDate', '{#NativeBuildDate}') then
      RaiseException('无法保存西美远控安装版本信息');
    if not RegWriteStringValue(HKLM64, UninstallKey, 'Version', '1.4.9') then
      RaiseException('无法保存西美远控核心版本信息');
    if not RegQueryStringValue(HKLM64, UninstallKey, 'BuildDate', ActualBuildDate) then
      RaiseException('无法验证西美远控安装版本信息');
    if ActualBuildDate <> '{#NativeBuildDate}' then
      RaiseException('西美远控安装版本校验失败');
    Log('West Beauty native build metadata verified: ' + ActualBuildDate);
  end;
end;

function HasWestBeautyService: Boolean;
begin
  Result := RegKeyExists(HKLM, 'SYSTEM\CurrentControlSet\Services\WestBeautyRemote');
end;

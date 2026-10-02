param([Parameter(Mandatory=$true)][string]$SourceInstaller)
$ErrorActionPreference='Stop'
$repo=(Get-Location).Path
$source=(Resolve-Path $SourceInstaller).Path
$input=Join-Path $env:RUNNER_TEMP 'WestBeautyNativeInput'
$stage=Join-Path $repo 'repackage'
New-Item -ItemType Directory -Force "$stage/rustdesk","$stage/flutter/windows/runner/resources" | Out-Null
$install=Start-Process $source -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$input+'"')) -Wait -PassThru
if($install.ExitCode -ne 0){throw 'Source candidate extraction install failed'}
try {
  Get-ChildItem $input -Force | Where-Object {$_.Name -notlike 'unins*'} | Copy-Item -Destination "$stage/rustdesk" -Recurse -Force
} finally {
  Start-Process (Join-Path $input 'unins000.exe') -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait
}
python -m pip install --disable-pip-version-check pillow
if($LASTEXITCODE -ne 0){throw 'Pillow installation failed'}
python ./westbeauty/generate_branding.py .
if($LASTEXITCODE -ne 0){throw 'Brand asset generation failed'}
Copy-Item ./branding/app.svg "$stage/rustdesk/data/flutter_assets/assets/icon.svg" -Force
Copy-Item ./branding/app.ico "$stage/flutter/windows/runner/resources/app_icon.ico" -Force
Copy-Item ./westbeauty/OPEN_SOURCE_NOTICE.txt "$stage/rustdesk/OPEN_SOURCE_NOTICE.txt" -Force
Copy-Item ./westbeauty/installer.iss "$stage/installer.iss"
Copy-Item ./westbeauty/ChineseSimplified.isl "$stage/ChineseSimplified.isl"
$nativeExe="$stage/rustdesk/WestBeautyRemote.exe"
$probe=Start-Process $nativeExe -ArgumentList '--build-date' -PassThru -Wait -RedirectStandardOutput "$stage/native-build-date.txt"
if($probe.ExitCode -ne 0){throw 'Native build date probe failed'}
$stamp=(Get-Content "$stage/native-build-date.txt" -Raw).Trim()
if($stamp -notmatch '^[0-9TZ+ .:-]+$'){throw "Invalid native build date"}
('#define NativeBuildDate "'+$stamp+'"')|Set-Content "$stage/native-build-date.iss" -Encoding UTF8
$provenance=[ordered]@{native_commit='bcccafcd0bcf412028c69f1cdf0064ba650aad1f';native_build_run=36978271316;packaging_commit=$env:GITHUB_SHA;source_installer_sha256=(Get-FileHash $source -Algorithm SHA256).Hash;native_executable_sha256=(Get-FileHash $nativeExe -Algorithm SHA256).Hash;native_build_date=$stamp;packaging_changes=@('Write exact native BuildDate to installer registration','Replace existing SVG titlebar asset with West Beauty branding');signature='NotSigned';acceptance='See Windows QA results; physical Windows 10/11 and dual-end tests pending'}
$provenance|ConvertTo-Json -Depth 5|Set-Content "$stage/rustdesk/BUILD_PROVENANCE.json" -Encoding UTF8
choco install innosetup -y --no-progress
if($LASTEXITCODE -ne 0){throw 'Inno Setup installation failed'}
Push-Location $stage
try { & 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' installer.iss; if($LASTEXITCODE -ne 0){throw 'Installer compilation failed'} } finally { Pop-Location }
Get-FileHash "$stage/SignOutput/西美远控-Setup-x64-2.1.0-rc1.exe" -Algorithm SHA256|Format-List

param(
  [Parameter(Mandatory=$true)][string]$Installer,
  [string]$OutputDirectory = 'qa-results',
  [string]$UpgradeFrom = '',
  [switch]$Baseline
)
$ErrorActionPreference = 'Stop'
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$results = [Collections.Generic.List[object]]::new()
function Record([string]$name, [bool]$passed, $detail) {
  $results.Add([ordered]@{check=$name; passed=$passed; detail=$detail})
  Write-Host "$name : $passed : $detail"
}
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class WindowProbe {
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
'@
function Capture($process, [string]$name) {
  $process.Refresh()
  $rect = New-Object WindowProbe+Rect
  if ($process.MainWindowHandle -eq 0 -or -not [WindowProbe]::GetWindowRect($process.MainWindowHandle, [ref]$rect)) { return $null }
  $w=$rect.Right-$rect.Left; $h=$rect.Bottom-$rect.Top
  if ($w -lt 100 -or $h -lt 100) { return $null }
  $bmp = New-Object Drawing.Bitmap $w,$h
  $graphics=[Drawing.Graphics]::FromImage($bmp)
  $dc=$graphics.GetHdc()
  try { $printed=[WindowProbe]::PrintWindow($process.MainWindowHandle,$dc,2) } finally { $graphics.ReleaseHdc($dc) }
  $bmp.Save((Join-Path $OutputDirectory "$name.png"))
  $colors=[Collections.Generic.HashSet[int]]::new(); $white=0; $black=0; $total=0
  for($y=50;$y -lt ($h-30);$y+=4) { for($x=30;$x -lt ($w-30);$x+=4) {
    $c=$bmp.GetPixel($x,$y); $null=$colors.Add($c.ToArgb()); $total++
    if($c.R -gt 245 -and $c.G -gt 245 -and $c.B -gt 245) {$white++}
    if($c.R -lt 10 -and $c.G -lt 10 -and $c.B -lt 10) {$black++}
  }}
  $graphics.Dispose(); $bmp.Dispose()
  return [ordered]@{printed=$printed;width=$w;height=$h;colors=$colors.Count;whiteFraction=$white/[Math]::Max(1,$total);blackFraction=$black/[Math]::Max(1,$total)}
}
$appDir=Join-Path $env:ProgramFiles 'West Beauty Group\西美远控'
$exeName=if($Baseline){'rustdesk.exe'}else{'WestBeautyRemote.exe'}
$exe=Join-Path $appDir $exeName
$runStart=Get-Date
try {
  $installerPath=(Resolve-Path $Installer).Path
  if($UpgradeFrom) {
    $old=Start-Process (Resolve-Path $UpgradeFrom).Path -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -PassThru
    if(-not $old.WaitForExit(120000) -or $old.ExitCode -ne 0){throw 'Could not prepare original V2 upgrade fixture'}
    Record 'upgrade_fixture_ready' (Test-Path (Join-Path $appDir 'rustdesk.exe')) 'V2 installed before candidate'
  }
  Record 'installer_sha256' $true (Get-FileHash $installerPath -Algorithm SHA256).Hash
  Record 'authenticode_status_observed' $true ((Get-AuthenticodeSignature $installerPath).Status.ToString())
  $timer=[Diagnostics.Stopwatch]::StartNew()
  $install=Start-Process $installerPath -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+(Join-Path $OutputDirectory 'install.log')+'"')) -PassThru
  if(-not $install.WaitForExit(120000)){ throw 'Installer timed out after 120 seconds' }
  Record 'clean_install_exit_zero' ($install.ExitCode -eq 0) "exit=$($install.ExitCode), milliseconds=$($timer.ElapsedMilliseconds)"
  Record 'executable_present' (Test-Path $exe) $exeName
  if(-not $Baseline){Record 'obsolete_v2_executable_removed' (-not (Test-Path (Join-Path $appDir 'rustdesk.exe'))) 'rustdesk.exe absent'}
  $required=@('librustdesk.dll','flutter_windows.dll','data\app.so','data\icudtl.dat','data\flutter_assets\AssetManifest.bin')
  foreach($file in $required){Record "runtime_file_$file" (Test-Path (Join-Path $appDir $file)) $file}
  $reg='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{B5A4D980-6F1E-4E20-9A0A-57DFAE516B21}_is1'
  $installed=Get-ItemProperty $reg
  Record 'uninstall_registration' ($installed.DisplayName -eq '西美远控') $installed.DisplayName
  Record 'install_location_registration' ($installed.InstallLocation.TrimEnd('\') -eq $appDir) $installed.InstallLocation
  $shortcut=Join-Path $env:PUBLIC 'Desktop\西美远控.lnk'
  # WScript.Shell returns an empty TargetPath for these valid Unicode links on
  # the hosted image. Shell.Application resolves the actual Unicode target.
  $shell=New-Object -ComObject Shell.Application
  $shortcutItem=$shell.NameSpace((Split-Path $shortcut)).ParseName((Split-Path $shortcut -Leaf))
  $shortcutTarget=$shortcutItem.ExtendedProperty('System.Link.TargetParsingPath')
  $shortcutInfo=@{path=$shortcut;exists=(Test-Path $shortcut);target=$shortcutTarget}
  Record 'desktop_shortcut' ((Test-Path $shortcut) -and $shortcutTarget -eq $exe) ($shortcutInfo|ConvertTo-Json -Compress)
  if(Test-Path $shortcut){Copy-Item $shortcut (Join-Path $OutputDirectory 'desktop-shortcut.lnk')}
  if(-not $Baseline) {
    $probe=Start-Process $exe -ArgumentList '--check-install' -PassThru -Wait -RedirectStandardOutput (Join-Path $OutputDirectory 'installed-state.txt')
    Record 'native_installed_state' ($probe.ExitCode -eq 0 -and (Get-Content (Join-Path $OutputDirectory 'installed-state.txt') -Raw).Trim() -eq 'true') (Get-Content (Join-Path $OutputDirectory 'installed-state.txt') -Raw)
    $stamp=Start-Process $exe -ArgumentList '--build-date' -PassThru -Wait -RedirectStandardOutput (Join-Path $OutputDirectory 'native-build-date.txt')
    $nativeDate=(Get-Content (Join-Path $OutputDirectory 'native-build-date.txt') -Raw).Trim()
    Record 'installed_build_date_matches_native' ($stamp.ExitCode -eq 0 -and $nativeDate -and $installed.BuildDate -eq $nativeDate) "registry=$($installed.BuildDate), native=$nativeDate"
    Record 'branded_titlebar_asset' ((Get-Content (Join-Path $appDir 'data\flutter_assets\assets\icon.svg') -Raw).Contains('West Beauty Group')) 'West Beauty SVG'
  }
  $timer.Restart()
  $version=Start-Process $exe -ArgumentList '--version' -PassThru -Wait -RedirectStandardOutput (Join-Path $OutputDirectory 'version.txt') -RedirectStandardError (Join-Path $OutputDirectory 'version-error.txt')
  Record 'native_core_version' ($version.ExitCode -eq 0 -and (Get-Content (Join-Path $OutputDirectory 'version.txt') -Raw).Trim() -eq '1.4.9') "exit=$($version.ExitCode), milliseconds=$($timer.ElapsedMilliseconds)"
  $timer.Restart()
  # The upstream --no-server flag suppresses the local remote-control server.
  # No device connection or unattended access is created by this test.
  $app=Start-Process $exe -ArgumentList '--no-server' -PassThru -WorkingDirectory $appDir -RedirectStandardOutput (Join-Path $OutputDirectory 'stdout.txt') -RedirectStandardError (Join-Path $OutputDirectory 'stderr.txt')
  $rendered=$false; $capture=$null
  foreach($seconds in @(2,3,5,5)) {
    Start-Sleep -Seconds $seconds; $app.Refresh()
    if($app.HasExited) { break }
    $capture=Capture $app ("main-"+$timer.ElapsedMilliseconds)
    if($capture -and $capture.printed -and $capture.colors -gt 50 -and $capture.whiteFraction -lt 0.97 -and $capture.blackFraction -lt 0.97){$rendered=$true;break}
  }
  Record 'main_window_rendered' $rendered (@{elapsedMs=$timer.ElapsedMilliseconds;capture=$capture}|ConvertTo-Json -Compress)
  $app.Refresh()
  Record 'main_window_responsive' (-not $app.HasExited -and $app.Responding -and $app.MainWindowHandle -ne 0) $app.MainWindowTitle
  if(-not $app.HasExited) {
    $other=Start-Process $shortcut -ArgumentList '--no-server' -PassThru
    Start-Sleep -Seconds 3
    $windows=@(Get-Process | Where-Object {$_.Path -eq $exe -and $_.MainWindowHandle -ne 0})
    Record 'repeated_shortcut_launch_single_window' ($windows.Count -eq 1) "window_count=$($windows.Count)"
    $null=Capture $app 'repeated-launch'
  }
} catch {Record 'unexpected_exception' $false $_.Exception.Message}
finally {
  Get-Process | Where-Object {$_.Path -eq $exe} | Stop-Process -Force -ErrorAction SilentlyContinue
  # Inno can rename an upgrade uninstaller to unins001.exe; follow its registered path.
  $uninstallKey='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{B5A4D980-6F1E-4E20-9A0A-57DFAE516B21}_is1'
  $uninstallCommand=(Get-ItemProperty $uninstallKey -ErrorAction SilentlyContinue).UninstallString
  $uninstaller=if($uninstallCommand){$uninstallCommand.Trim('"')}else{''}
  $validUninstaller=$uninstaller -and $uninstaller.StartsWith($appDir+'\',[StringComparison]::OrdinalIgnoreCase) -and ([IO.Path]::GetFileName($uninstaller) -match '^unins[0-9]+\.exe$') -and (Test-Path $uninstaller)
  Record 'registered_uninstaller_exists' ([bool]$validUninstaller) $uninstaller
  if($validUninstaller) {
    $uninstall=Start-Process $uninstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG="'+(Join-Path $OutputDirectory 'uninstall.log')+'"')) -PassThru
    if($uninstall.WaitForExit(60000)) {Record 'uninstall_exit_zero' ($uninstall.ExitCode -eq 0) $uninstall.ExitCode} else {Record 'uninstall_exit_zero' $false 'timeout'}
    Record 'uninstall_removes_executable' (-not (Test-Path $exe)) $exeName
    Record 'uninstall_removes_shortcut' (-not (Test-Path (Join-Path $env:PUBLIC 'Desktop\西美远控.lnk'))) 'desktop shortcut'
    Record 'uninstall_removes_registration' (-not (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{B5A4D980-6F1E-4E20-9A0A-57DFAE516B21}_is1')) 'uninstall key'
  }
  $summary=[ordered]@{os=(Get-CimInstance Win32_OperatingSystem).Caption;baseline=[bool]$Baseline;upgrade=[bool]$UpgradeFrom;started=$runStart.ToUniversalTime().ToString('o');checks=$results;limitations=@('Windows Server CI only; Windows 10/11 physical-device acceptance pending','No remote device connection, unattended access, reboot, UAC or dual-end test','Screenshot metrics are automated heuristics and require visual review','Unsigned builds are not release-ready until distribution/signing is resolved')}
  $summary | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $OutputDirectory 'results.json') -Encoding UTF8
}
if(-not $Baseline -and @($results|Where-Object{-not $_.passed}).Count -gt 0){throw 'Windows acceptance failed; inspect results.json and screenshots'}

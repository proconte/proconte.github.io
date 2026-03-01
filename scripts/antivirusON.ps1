$adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
$currentId = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentId)
if (-not $principal.IsInRole($adminRole)) {
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell.exe -ArgumentList $args -Verb RunAs
    exit
}

$RegKeys = @(
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search", "DisableRemovableDriveIndexing", 0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Search", "PreventIndexingRemovableDrives", 0),
    @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer", "NoDriveTypeAutoRun", 145),
    @("HKLM:\Software\Policies\Microsoft\Windows\Explorer", "NoAutorun", 0),
    @("HKLM:\Software\Policies\Microsoft\Windows\Explorer", "DisableAutoplay", 0),
    @("HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters", "AllowInsecureGuestAuth", 0),
    @("HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem", "LongPathsEnabled", 0),
    @("HKCU:\Control Panel\Desktop\WindowMetrics", "IconSpacing", "-1125"),
    @("HKCU:\Control Panel\Desktop\WindowMetrics", "IconVerticalSpacing", "-1125"),
    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System", "EnableLUA", 1),
    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System", "ConsentPromptBehaviorAdmin", 5),
    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System", "PromptOnSecureDesktop", 1),
    @("HKLM:\SOFTWARE\Microsoft\Windows Defender\Features", "TamperProtection", 1),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender", "DisableAntiSpyware", 0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet", "SpyNetReporting", 1),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet", "SubmitSamplesConsent", 1),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection", "DisableRealtimeMonitoring", 0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection", "DisableHeuristicRealTimeMonitoring", 0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\System", "EnableSmartScreen", 1),
    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer", "SmartScreenEnabled", "Warn"),
    @("HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost", "EnableWebContentEvaluation", 1),
    @("HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy", "VerifiedAndReputablePolicyState", 1)
)

foreach ($rk in $RegKeys) {
    if (!(Test-Path $rk[0])) { New-Item -Path $rk[0] -Force | Out-Null }
    Set-ItemProperty -Path $rk[0] -Name $rk[1] -Value $rk[2] -Force -ErrorAction SilentlyContinue
}

powercfg /change monitor-timeout-ac 10
powercfg /change monitor-timeout-dc 5
powercfg /change standby-timeout-ac 30
powercfg /change standby-timeout-dc 15

Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false -DisableIntrusionPreventionSystem $false -DisableIOAVProtection $false -MAPSReporting 2 -SubmitSamplesConsent 1 -PUAProtection Enabled -EnableControlledFolderAccess Enabled -EnableNetworkProtection Enabled -ErrorAction SilentlyContinue

Set-ProcessMitigation -System -Enable DEP, BottomUp, HighEntropy, SEHOP -ErrorAction SilentlyContinue

$PhotoExts = @(".jpg", ".jpeg", ".gif", ".png", ".bmp", ".tiff", ".ico")
foreach ($ext in $PhotoExts) {
    $path = "HKCU:\Software\Classes\$ext"
    if (Test-Path $path) {
        Remove-ItemProperty -Path $path -Name "(Default)" -ErrorAction SilentlyContinue
    }
}

Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Command Processor" -Name "AutoRun" -ErrorAction SilentlyContinue
Set-SmbClientConfiguration -RequireSecuritySignature $true -Force -ErrorAction SilentlyContinue

$menuPaths = @("Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\RunAsAdminCmd", "Registry::HKEY_CLASSES_ROOT\Directory\shell\RunAsAdminCmd")
foreach ($mPath in $menuPaths) {
    if (Test-Path $mPath) { Remove-Item -Path $mPath -Recurse -Force -ErrorAction SilentlyContinue }
}

$Advn = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $Advn -Name "HideFileExt" -Value 1 -Force
Set-ItemProperty -Path $Advn -Name "UseCompactMode" -Value 0 -Force
$clsidPath = "HKCU:\Software\Classes\CLSID\{86CA1AA0-34AA-4E8B-A509-50C905BAE2A2}"
if (Test-Path $clsidPath) { Remove-Item -Path $clsidPath -Recurse -Force -ErrorAction SilentlyContinue }

Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe
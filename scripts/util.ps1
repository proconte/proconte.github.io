$adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
$currentId = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentId)
if (-not $principal.IsInRole($adminRole)) {
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell.exe -ArgumentList $args -Verb RunAs
    exit
}

$RegKeys = @(
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search", "DisableRemovableDriveIndexing", 1),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\Search", "PreventIndexingRemovableDrives", 1),
    @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer", "NoDriveTypeAutoRun", 255),
    @("HKLM:\Software\Policies\Microsoft\Windows\Explorer", "NoAutorun", 1),
    @("HKLM:\Software\Policies\Microsoft\Windows\Explorer", "DisableAutoplay", 1),
    @("HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters", "AllowInsecureGuestAuth", 1),
    @("HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem", "LongPathsEnabled", 1),
    @("HKCU:\Control Panel\Desktop\WindowMetrics", "IconSpacing", "-1200"),
    @("HKCU:\Control Panel\Desktop\WindowMetrics", "IconVerticalSpacing", "-700"),
    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System", "EnableLUA", 0),
    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System", "ConsentPromptBehaviorAdmin", 0),
    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System", "PromptOnSecureDesktop", 0),
    @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\System", "EnableSmartScreen", 0),
    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer", "SmartScreenEnabled", "Off"),
    @("HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost", "EnableWebContentEvaluation", 0),
    @("HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy", "VerifiedAndReputablePolicyState", 0),
    @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "AutoCheckSelect", 1),
    @("HKCU:\AppEvents\Schemes", "(Default)", ".None"),
    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation", "DisableStartupSound", 1),
    @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System", "DisableStartupSound", 1),
    @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel", "AllItemsIconView", 1),
    @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel", "StartupPage", 1)
)

foreach ($rk in $RegKeys) {
    if (!(Test-Path $rk[0])) { New-Item -Path $rk[0] -Force | Out-Null }
    Set-ItemProperty -Path $rk[0] -Name $rk[1] -Value $rk[2] -Force -ErrorAction SilentlyContinue
}

powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0

# Exclusiones de Windows Defender
Add-MpPreference -ExclusionPath "C:\util", "C:\temp" -ErrorAction SilentlyContinue

$PhotoExts = @(".jpg", ".jpeg", ".gif", ".png", ".bmp", ".tiff", ".ico")
foreach ($ext in $PhotoExts) {
    $path = "HKCU:\Software\Classes\$ext"
    if (!(Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name "(Default)" -Value "PhotoViewer.FileAssoc.Tiff" -Force
}

if (!(Test-Path "HKCU:\Software\Microsoft\Command Processor")) { New-Item -Path "HKCU:\Software\Microsoft\Command Processor" -Force | Out-Null }
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Command Processor" -Name "AutoRun" -Value "chcp 65001 >nul" -Force
Set-SmbClientConfiguration -RequireSecuritySignature $false -Force -ErrorAction SilentlyContinue

$menuPaths = @("Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\RunAsAdminCmd", "Registry::HKEY_CLASSES_ROOT\Directory\shell\RunAsAdminCmd")
foreach ($mPath in $menuPaths) {
    if (!(Test-Path $mPath)) { New-Item -Path $mPath -Force | Out-Null }
    Set-ItemProperty -Path $mPath -Name "(Default)" -Value "CMD admin" -Force
    Set-ItemProperty -Path $mPath -Name "Icon" -Value "cmd.exe" -Force
    $cmdPath = "$mPath\command"
    if (!(Test-Path $cmdPath)) { New-Item -Path $cmdPath -Force | Out-Null }
    Set-ItemProperty -Path $cmdPath -Name "(Default)" -Value "powershell -command ""Start-Process cmd -ArgumentList '/k cd /d %V' -Verb RunAs""" -Force
}

$Advn = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$CUFT = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes"
$LMFT = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes"
Set-ItemProperty -Path $Advn -Name "HideFileExt" -Value 0 -Force
Set-ItemProperty -Path $Advn -Name "UseCompactMode" -Value 1 -Force
Set-ItemProperty -Path "HKCU:\Software\Classes\CLSID\{86CA1AA0-34AA-4E8B-A509-50C905BAE2A2}\InprocServer32" -Name "(Default)" -Value "" -Force -ErrorAction SilentlyContinue

if (Test-Path $CUFT) { Remove-Item -Path $CUFT -Recurse -Force }
Copy-Item -Path $LMFT -Destination "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Recurse -Force

$Cols = "prop:0(34)System.ItemNameDisplay;0System.Size;0System.ItemType;0System.DateModified;0System.DateCreated"
Get-ChildItem -Path $CUFT | ForEach-Object {
    $folderTypePath = $_.PSPath
    # Forzar en la raíz del tipo de carpeta y en sus vistas (TopViews)
    $subKeys = @("", "\TopViews")
    foreach ($subKey in $subKeys) {
        $targetPath = "$folderTypePath$subKey"
        if ($subKey -eq "\TopViews" -and !(Test-Path $targetPath)) {
            # Intentar ver si hay subcarpetas dentro de TopViews (normalmente GUIDs)
            continue 
        }
        
        # Si es TopViews, aplicar a sus hijos (que son los GUIDs de las vistas reales)
        if ($subKey -eq "\TopViews") {
            Get-ChildItem -Path $targetPath -ErrorAction SilentlyContinue | ForEach-Object {
                Set-ItemProperty -Path $_.PSPath -Name "Mode" -Value 4 -Force
                Set-ItemProperty -Path $_.PSPath -Name "LogicalViewMode" -Value 1 -Force
                Set-ItemProperty -Path $_.PSPath -Name "GroupBy" -Value "" -Force
                Set-ItemProperty -Path $_.PSPath -Name "ColumnList" -Value $Cols -Force
                Set-ItemProperty -Path $_.PSPath -Name "SortByList" -Value "prop:System.ItemNameDisplay;System.Size" -Force
            }
        } else {
            # Aplicar directamente al tipo de carpeta si corresponde
            Set-ItemProperty -Path $targetPath -Name "Mode" -Value 4 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $targetPath -Name "LogicalViewMode" -Value 1 -Force -ErrorAction SilentlyContinue
        }
    }
}

$ShellPaths = @(
    "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU",
    "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams\Defaults"
)
foreach ($sp in $ShellPaths) { Remove-Item -Path $sp -Recurse -Force -ErrorAction SilentlyContinue }

Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe
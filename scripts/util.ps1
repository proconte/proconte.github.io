# SECCION 1: ELEVACION DE PRIVILEGIOS
# Verificacion de privilegios de administrador y elevacion de ser necesario.
$adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
$currentId = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentId)
if (-not $principal.IsInRole($adminRole)) {
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell.exe -ArgumentList $args -Verb RunAs
    exit
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "Ejecutando script con privilegios de administrador..."
Write-Host "---------------------------------------------------"

# SECCION 2: DESACTIVACION DE ADVERTENCIA DE SEGURIDAD PARA DIRECCION IP ESPECIFICA
# Asignacion de variables de entorno y modificacion del registro para catalogar la direccion IP 192.168.0.1 como zona de confianza.
Write-Host "Configurando politicas de seguridad para la direccion IP 192.168.0.1..."

[Environment]::SetEnvironmentVariable("SEE_MASK_NOZONECHECKS", "1", "User")
[Environment]::SetEnvironmentVariable("SEE_MASK_NOZONECHECKS", "1", "Machine")

$RangesPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Ranges\RangeNAS"
if (!(Test-Path $RangesPath)) { New-Item -Path $RangesPath -Force -ErrorAction SilentlyContinue | Out-Null }
Set-ItemProperty -Path $RangesPath -Name ":Range" -Value "192.168.0.1" -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $RangesPath -Name "*" -Value 1 -Force -ErrorAction SilentlyContinue

$uncPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains\192.168.0.1"
if (!(Test-Path $uncPath)) { New-Item -Path $uncPath -Force -ErrorAction SilentlyContinue | Out-Null }
Set-ItemProperty -Path $uncPath -Name "*" -Value 1 -Force -ErrorAction SilentlyContinue

$zone1Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\1"
if (!(Test-Path $zone1Path)) { New-Item -Path $zone1Path -Force -ErrorAction SilentlyContinue | Out-Null }
Set-ItemProperty -Path $zone1Path -Name "1806" -Value 0 -Force -ErrorAction SilentlyContinue

$assocPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Associations"
if (!(Test-Path $assocPath)) { New-Item -Path $assocPath -Force -ErrorAction SilentlyContinue | Out-Null }
Set-ItemProperty -Path $assocPath -Name "DefaultFileTypeRisk" -Value 6151 -Force -ErrorAction SilentlyContinue

Write-Host "Politicas de seguridad configuradas."

# SECCION 3: AJUSTES GENERALES DEL REGISTRO
# Aplicacion de configuraciones del sistema, explorador y red.
Write-Host "Aplicando configuraciones del registro del sistema..."

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
    if (!(Test-Path $rk[0])) { New-Item -Path $rk[0] -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $rk[0] -Name $rk[1] -Value $rk[2] -Force -ErrorAction SilentlyContinue
}
Write-Host "Configuraciones del registro aplicadas."

# SECCION 4: CONFIGURACION DE ENERGIA
# Modificacion de los tiempos de espera para la suspension del monitor y del sistema.
Write-Host "Configurando parametros de energia..."
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
Write-Host "Parametros de energia configurados."

# SECCION 5: EXCLUSIONES DE WINDOWS DEFENDER
# Adicion de directorios especificos a la lista de exclusiones del antivirus.
Write-Host "Alistando exclusiones en Windows Defender..."
$PathsToExclude = @("C:\util", "C:\temp")
foreach ($path in $PathsToExclude) {
    if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }
    Add-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
}
Write-Host "Exclusiones agregadas."

# SECCION 6: VISUALIZADOR DE FOTOS
# Restauracion de la asociacion de archivos de imagen con el Visualizador de fotos clasico.
Write-Host "Configurando el Visualizador de fotos clasico..."
$PhotoExts = @(".jpg", ".jpeg", ".gif", ".png", ".bmp", ".tiff", ".ico")
foreach ($ext in $PhotoExts) {
    $path = "HKCU:\Software\Classes\$ext"
    if (!(Test-Path $path)) { New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $path -Name "(Default)" -Value "PhotoViewer.FileAssoc.Tiff" -Force -ErrorAction SilentlyContinue
}
Write-Host "Visualizador de fotos configurado."

# SECCION 7: CONFIGURACION DE CONSOLA Y RED
# Establecimiento de la codificacion UTF-8 para las consolas y deshabilitacion de firmas de seguridad SMB.
Write-Host "Configurando codificacion de caracteres en consola y parametros de red SMB..."
if (!(Test-Path "HKCU:\Software\Microsoft\Command Processor")) { New-Item -Path "HKCU:\Software\Microsoft\Command Processor" -Force -ErrorAction SilentlyContinue | Out-Null }
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Command Processor" -Name "AutoRun" -Value "chcp 65001 >nul" -Force -ErrorAction SilentlyContinue

$psProfiles = @("$HOME\Documents\WindowsPowerShell\profile.ps1", "$HOME\Documents\PowerShell\profile.ps1")
$utf8Command = "`n[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`n[Console]::InputEncoding = [System.Text.Encoding]::UTF8"

foreach ($prof in $psProfiles) {
    $profDir = Split-Path $prof -Parent
    if (!(Test-Path $profDir)) { New-Item -ItemType Directory -Path $profDir -Force -ErrorAction SilentlyContinue | Out-Null }
    if (!(Test-Path $prof)) { New-Item -ItemType File -Path $prof -Force -ErrorAction SilentlyContinue | Out-Null }
    $currentContent = Get-Content -Path $prof -Raw -ErrorAction SilentlyContinue
    if ($currentContent -notmatch "\[Console\]::OutputEncoding") {
        Add-Content -Path $prof -Value $utf8Command -Force -ErrorAction SilentlyContinue
    }
}

Set-SmbClientConfiguration -RequireSecuritySignature $false -Force -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "Configuracion de consola y red completada."

# SECCION 8: MENU CONTEXTUAL
# Incorporacion de la opcion para ejecutar linea de comandos con privilegios de administrador desde el explorador.
Write-Host "Modificando el menu contextual..."
$menuPaths = @("Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\RunAsAdminCmd", "Registry::HKEY_CLASSES_ROOT\Directory\shell\RunAsAdminCmd")
foreach ($mPath in $menuPaths) {
    if (!(Test-Path $mPath)) { New-Item -Path $mPath -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $mPath -Name "(Default)" -Value "CMD admin" -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $mPath -Name "Icon" -Value "cmd.exe" -Force -ErrorAction SilentlyContinue
    $cmdPath = "$mPath\command"
    if (!(Test-Path $cmdPath)) { New-Item -Path $cmdPath -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $cmdPath -Name "(Default)" -Value "powershell -command ""Start-Process cmd -ArgumentList '/k cd /d %V' -Verb RunAs""" -Force -ErrorAction SilentlyContinue
}
Write-Host "Menu contextual modificado."

# SECCION 9: CONFIGURACION DEL EXPLORADOR DE ARCHIVOS
# Activacion del modo compacto, visualizacion de extensiones y menu contextual clasico.
Write-Host "Configurando el explorador de archivos..."
$Advn = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
$CUFT = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes"
$LMFT = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes"
Set-ItemProperty -Path $Advn -Name "HideFileExt" -Value 0 -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $Advn -Name "UseCompactMode" -Value 1 -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Classes\CLSID\{86CA1AA0-34AA-4E8B-A509-50C905BAE2A2}\InprocServer32" -Name "(Default)" -Value "" -Force -ErrorAction SilentlyContinue
Write-Host "Explorador de archivos configurado."

# SECCION 10: VISTAS DE CARPETAS
# Estandarizacion de la vista de Detalles para todos los directorios.
Write-Host "Estandarizando la vista de carpetas a Detalles..."
if (Test-Path $CUFT) { Remove-Item -Path $CUFT -Recurse -Force -ErrorAction SilentlyContinue }
Copy-Item -Path $LMFT -Destination "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Recurse -Force -ErrorAction SilentlyContinue

$Cols = "prop:0(34)System.ItemNameDisplay;0System.Size;0System.ItemType;0System.DateModified;0System.DateCreated"
Get-ChildItem -Path $CUFT -ErrorAction SilentlyContinue | ForEach-Object {
    $Top = "$($_.PSPath)\TopViews"
    if (Test-Path $Top) {
        Get-ChildItem -Path $Top -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty -Path $_.PSPath -Name "Mode" -Value 4 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $_.PSPath -Name "LogicalViewMode" -Value 1 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $_.PSPath -Name "GroupBy" -Value "" -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $_.PSPath -Name "ColumnList" -Value $Cols -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $_.PSPath -Name "SortByList" -Value "prop:System.ItemNameDisplay;System.Size" -Force -ErrorAction SilentlyContinue
        }
    }
}
Write-Host "Vista de carpetas estandarizada."

# SECCION 11: REINICIO DEL EXPLORADOR
# Eliminacion de las caches de vistas del explorador y reinicio del proceso.
Write-Host "Eliminando caches de vistas y reiniciando el proceso del explorador..."
$ShellPaths = @(
    "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU",
    "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams\Defaults"
)
foreach ($sp in $ShellPaths) { Remove-Item -Path $sp -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host "Ejecucion del script finalizada."
Write-Host "---------------------------------------------------"
Read-Host -Prompt "Presione Enter para cerrar la consola y reiniciar el explorador de Windows..."

Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe
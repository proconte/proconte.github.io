#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

try { [Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false) } catch {}
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { $OutputEncoding           = [System.Text.UTF8Encoding]::new($false) } catch {}

function Write-Step {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host ("[{0}] [{1}] {2}" -f $ts, $Level, $Message)
}

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevateMinimized {
    if (Test-IsAdministrator) {
        Write-Step "Privilegios de administrador confirmados"
        return $true
    }

    try {
        Write-Step "Elevar privilegios (UAC) en modo minimizado"
        $args = @(
            '-NoProfile',
            '-ExecutionPolicy','Bypass',
            '-WindowStyle','Minimized',
            '-File', ('"{0}"' -f $PSCommandPath)
        )
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -WindowStyle Minimized | Out-Null
        return $false
    } catch {
        Write-Step ("No elevar privilegios. Detalle: {0}" -f $_.Exception.Message) 'ERROR'
        exit 1
    }
}

function Get-FreeBytes {
    param([Parameter(Mandatory=$true)][string]$DriveLetter)
    $d = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}:'" -f $DriveLetter.TrimEnd(':'))
    return [int64]$d.FreeSpace
}

function Format-Bytes {
    param([Parameter(Mandatory=$true)][int64]$Bytes)
    $units = 'B','KB','MB','GB','TB'
    $i = 0
    $v = [double]$Bytes
    while ($v -ge 1024 -and $i -lt ($units.Count - 1)) { $v /= 1024; $i++ }
    return ("{0:N2} {1}" -f $v, $units[$i])
}

function Invoke-ExternalProcess {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter()][string[]]$ArgumentList = @(),
        [int]$TimeoutMinutes = 240
    )

    Write-Step ("Ejecutar: {0} {1}" -f $FilePath, ($ArgumentList -join ' '))
    $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WindowStyle Hidden -PassThru
    try {
        $null = $p | Wait-Process -Timeout ($TimeoutMinutes * 60)
        Write-Step ("Finalizar: código {0}" -f $p.ExitCode)
        return $p.ExitCode
    } catch {
        Write-Step ("Timeout; finalizar proceso: {0}" -f $FilePath) 'WARN'
        try { $p | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
        return 1460
    }
}

function Get-ServiceState {
    param([Parameter(Mandatory=$true)][string[]]$Name)
    $state = @{}
    foreach ($n in $Name) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($null -ne $svc) { $state[$n] = $svc.Status }
    }
    return $state
}

function Stop-ServicesSafe {
    param([Parameter(Mandatory=$true)][string[]]$Name)
    foreach ($n in $Name) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($null -eq $svc) { continue }
        if ($svc.Status -ne 'Stopped') {
            try {
                Write-Step ("Detener servicio: {0}" -f $n)
                Stop-Service -Name $n -Force -ErrorAction Stop
            } catch {
                Write-Step ("No detener servicio {0}. Detalle: {1}" -f $n, $_.Exception.Message) 'WARN'
            }
        } else {
            Write-Step ("Servicio ya detenido: {0}" -f $n)
        }
    }
}

function Start-ServicesSafe {
    param([Parameter(Mandatory=$true)][hashtable]$PreviousState)
    foreach ($kv in $PreviousState.GetEnumerator()) {
        if ($kv.Value -eq 'Running') {
            try {
                Write-Step ("Iniciar servicio: {0}" -f $kv.Key)
                Start-Service -Name $kv.Key -ErrorAction Stop
            } catch {
                Write-Step ("No iniciar servicio {0}. Detalle: {1}" -f $kv.Key, $_.Exception.Message) 'WARN'
            }
        }
    }
}

function Clear-FolderContents {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [switch]$KeepFolder
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Step ("Omitir; no existe: {0}" -f $Path)
        return
    }

    Write-Step ("Limpiar: {0}" -f $Path)
    $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    foreach ($it in $items) {
        try {
            Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Step ("No eliminar: {0}. Detalle: {1}" -f $it.FullName, $_.Exception.Message) 'WARN'
        }
    }
}

function Clear-TempPaths {
    Write-Step "Limpiar temporales del sistema (TEMP/TMP/Windows\Temp/Panther)"
    $paths = @(
        $env:TEMP,
        $env:TMP,
        (Join-Path $env:windir 'Temp'),
        (Join-Path $env:windir 'Panther')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    foreach ($p in $paths) { Clear-FolderContents -Path $p -KeepFolder }
}

function Clear-UserTempsAllProfiles {
    Write-Step "Limpiar temporales en perfiles de usuario"
    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (-not (Test-Path -LiteralPath $usersRoot)) { return }

    $skip = @('Default','Default User','All Users','Public')
    $profiles = Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $skip -notcontains $_.Name }

    foreach ($pr in $profiles) {
        Write-Step ("Perfil: {0}" -f $pr.Name)

        Clear-FolderContents -Path (Join-Path $pr.FullName 'AppData\Local\Temp') -KeepFolder
        Clear-FolderContents -Path (Join-Path $pr.FullName 'AppData\Local\Microsoft\Windows\WER\ReportArchive') -KeepFolder
        Clear-FolderContents -Path (Join-Path $pr.FullName 'AppData\Local\Microsoft\Windows\WER\ReportQueue') -KeepFolder
    }
}

function Clear-WERSystem {
    Write-Step "Limpiar Windows Error Reporting (WER) a nivel de sistema"
    @(
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\Temp')
    ) | ForEach-Object { Clear-FolderContents -Path $_ -KeepFolder }
}

function Clear-WindowsUpdateCachesReset {
    Write-Step "Limpiar cachés de Windows Update (Download, DataStore, catroot2)"

    $services = @('wuauserv','UsoSvc','bits','dosvc','msiserver','cryptsvc')
    $prev = Get-ServiceState -Name $services

    Stop-ServicesSafe -Name $services
    try {
        $sd = Join-Path $env:windir 'SoftwareDistribution'
        @(
            (Join-Path $sd 'Download'),
            (Join-Path $sd 'DataStore'),
            (Join-Path $env:windir 'System32\catroot2')
        ) | ForEach-Object { Clear-FolderContents -Path $_ -KeepFolder }
    } finally {
        Start-ServicesSafe -PreviousState $prev
    }
}

function Clear-DeliveryOptimizationCacheSafe {
    Write-Step "Limpiar caché de Delivery Optimization"
    try {
        $cmd = Get-Command -Name Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            Write-Step "Usar cmdlet Delete-DeliveryOptimizationCache"
            try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop | Out-Null } catch { Write-Step ("Fallo cmdlet Delivery Optimization. Detalle: {0}" -f $_.Exception.Message) 'WARN' }
            return
        }
    } catch {}

    Write-Step "Cmdlet no disponible; usar limpieza por rutas"
    @(
        (Join-Path $env:windir 'SoftwareDistribution\DeliveryOptimization'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\DeliveryOptimization')
    ) | ForEach-Object { Clear-FolderContents -Path $_ -KeepFolder }
}

function Remove-CrashDumpsSafe {
    Write-Step "Eliminar volcados de memoria (crash dumps)"
    $memDmp = Join-Path $env:windir 'MEMORY.DMP'
    if (Test-Path -LiteralPath $memDmp) {
        try {
            Write-Step ("Eliminar: {0}" -f $memDmp)
            Remove-Item -LiteralPath $memDmp -Force -ErrorAction Stop
        } catch {
            Write-Step ("No eliminar: {0}. Detalle: {1}" -f $memDmp, $_.Exception.Message) 'WARN'
        }
    } else {
        Write-Step ("Omitir; no existe: {0}" -f $memDmp)
    }
    Clear-FolderContents -Path (Join-Path $env:windir 'Minidump') -KeepFolder
}

function Remove-WindowsOldSafe {
    $p = Join-Path $env:SystemDrive 'Windows.old'
    if (-not (Test-Path -LiteralPath $p)) { Write-Step "Omitir; Windows.old no existe"; return }
    Write-Step "Eliminar Windows.old (takeown + icacls + rd)"
    try {
        # Tomar posesión y dar permisos completos
        Invoke-ExternalProcess -FilePath 'takeown.exe' -ArgumentList @('/F', $p, '/R', '/A', '/D', 'Y') -TimeoutMinutes 10 | Out-Null
        Invoke-ExternalProcess -FilePath 'icacls.exe' -ArgumentList @($p, '/grant', 'Administradores:F', '/T', '/C', '/Q') -TimeoutMinutes 10 | Out-Null
        # Eliminar con rd que es más fiable para esta carpeta
        Invoke-ExternalProcess -FilePath 'cmd.exe' -ArgumentList @('/c', 'rd', '/s', '/q', "`"$p`"") -TimeoutMinutes 30 | Out-Null
        if (Test-Path -LiteralPath $p) {
            Write-Step "Windows.old no se eliminó completamente" 'WARN'
        } else {
            Write-Step "Windows.old eliminado correctamente"
        }
    } catch {
        Write-Step ("No eliminar Windows.old. Detalle: {0}" -f $_.Exception.Message) 'WARN'
    }
}

function Run-ComponentStoreCleanupResetBase {
    Write-Step "Limpiar almacén de componentes (DISM StartComponentCleanup + ResetBase)"

    $dism = Join-Path $env:windir 'System32\dism.exe'
    $args = @('/online','/Cleanup-Image','/StartComponentCleanup','/ResetBase')

    $code = Invoke-ExternalProcess -FilePath $dism -ArgumentList $args -TimeoutMinutes 240
    if ($code -ne 0) {
        Write-Step ("DISM finaliza con código no cero: {0}" -f $code) 'WARN'
    }
}

function Clear-DnsCacheSafe {
    Write-Step "Limpiar caché DNS"
    try { Clear-DnsClientCache } catch { Write-Step ("Fallo al limpiar DNS. Detalle: {0}" -f $_.Exception.Message) 'WARN' }
}

function Clear-RecycleBinSafe {
    Write-Step "Vaciar Papelera de reciclaje"
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null } catch { Write-Step ("Fallo al vaciar Papelera. Detalle: {0}" -f $_.Exception.Message) 'WARN' }
}

function Optimize-SystemDriveSafe {
    Write-Step "Optimización de unidad del sistema (defrag.exe /O)"
    $drive = $env:SystemDrive.TrimEnd(':')
    Invoke-ExternalProcess -FilePath (Join-Path $env:windir 'System32\defrag.exe') -ArgumentList @("$drive`:","/O","/U","/V") -TimeoutMinutes 240 | Out-Null
}

function Show-FinalPopupForeground {
    param(
        [Parameter(Mandatory=$true)][int64]$FreeBefore,
        [Parameter(Mandatory=$true)][int64]$FreeAfter,
        [Parameter(Mandatory=$true)][string]$Drive
    )

    $delta = [Math]::Max(0L, ($freeAfter - $freeBefore))

    $msg =
        "Espacio libre inicial en $Drive`: $(Format-Bytes -Bytes $FreeBefore)`r`n" +
        "Espacio libre final en $Drive`:   $(Format-Bytes -Bytes $FreeAfter)`r`n" +
        "Espacio liberado:                $(Format-Bytes -Bytes $delta)"

    try {
        $ws = New-Object -ComObject WScript.Shell
        $null = $ws.Popup($msg, 0, 'Mantenimiento Windows 11', 4096 + 64)
    } catch {
        Write-Step ("No mostrar ventana emergente. Detalle: {0}" -f $_.Exception.Message) 'WARN'
    }
}

if (-not (Invoke-SelfElevateMinimized)) { exit 0 }

try {
    Write-Step "Inicio de mantenimiento"

    $drive = $env:SystemDrive.TrimEnd(':')
    $freeBefore = Get-FreeBytes -DriveLetter $drive
    Write-Step ("Espacio libre inicial en {0}: {1}" -f $drive, (Format-Bytes -Bytes $freeBefore))

    Clear-TempPaths
    Clear-UserTempsAllProfiles
    Clear-WERSystem
    Clear-WindowsUpdateCachesReset
    Clear-DeliveryOptimizationCacheSafe
    Remove-CrashDumpsSafe
    Remove-WindowsOldSafe

    Run-ComponentStoreCleanupResetBase

    Write-Step "Continuar tras DISM"
    Clear-DnsCacheSafe
    Clear-RecycleBinSafe
    Optimize-SystemDriveSafe

    $freeAfter = Get-FreeBytes -DriveLetter $drive
    $delta = [Math]::Max(0L, ($FreeAfter - $FreeBefore))

    Write-Step "Resumen final"
    Write-Step ("Espacio libre inicial en {0}: {1}" -f $drive, (Format-Bytes -Bytes $freeBefore))
    Write-Step ("Espacio libre final en {0}: {1}" -f $drive, (Format-Bytes -Bytes $freeAfter))
    Write-Step ("Espacio liberado: {0}" -f (Format-Bytes -Bytes $delta))
    Write-Step "Fin de mantenimiento"

    Show-FinalPopupForeground -FreeBefore $freeBefore -FreeAfter $freeAfter -Drive $drive

    exit 0
} catch {
    Write-Step ("Fallo general. Detalle: {0}" -f $_.Exception.Message) 'ERROR'
    try {
        $ws2 = New-Object -ComObject WScript.Shell
        $null = $ws2.Popup(("Fallo del script.`r`n`r`n{0}" -f $_.Exception.Message), 0, 'Mantenimiento Windows 11', 4096 + 16)
    } catch {}
    exit 2
}
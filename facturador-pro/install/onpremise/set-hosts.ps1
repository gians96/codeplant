<#
=========================================================================
 set-hosts.ps1 - Agrega/actualiza las entradas hosts en una PC Windows
=========================================================================
 Apunta el dominio base y los subdominios de empresas a la IP LAN del
 servidor pro-8, para acceder por nombre mientras no haya DNS publico.

 IMPORTANTE: abrir PowerShell COMO ADMINISTRADOR.

 Uso:
   .\set-hosts.ps1 -ServerIp 192.168.1.100 -BaseDomain fe.consurtrading.org -Empresas empresa1,empresa2
   .\set-hosts.ps1 -ServerIp 192.168.1.100 -BaseDomain fe.consurtrading.org

 Idempotente: reemplaza el bloque gestionado entre marcadores BEGIN/END.
=========================================================================
#>
param(
    [Parameter(Mandatory=$true)][string]$ServerIp,
    [Parameter(Mandatory=$true)][string]$BaseDomain,
    [string[]]$Empresas = @()
)

$hostsFile = "$env:WINDIR\System32\drivers\etc\hosts"
$begin = "# >>> pro-8 ($BaseDomain) >>>"
$end   = "# <<< pro-8 ($BaseDomain) <<<"

$lines = @($begin, "$ServerIp`t$BaseDomain", "$ServerIp`tws.$BaseDomain")
foreach ($e in $Empresas) { $lines += "$ServerIp`t$e.$BaseDomain" }
$lines += $end
$block = $lines -join "`r`n"

if (-not (Test-Path $hostsFile)) { New-Item -ItemType File -Path $hostsFile -Force | Out-Null }
$content = Get-Content $hostsFile -Raw -ErrorAction SilentlyContinue
if ($null -eq $content) { $content = "" }

# Eliminar bloque previo entre marcadores (incluido)
$pattern = [regex]::Escape($begin) + "[\s\S]*?" + [regex]::Escape($end)
$content = [regex]::Replace($content, $pattern, "").TrimEnd()

$new = ($content + "`r`n" + $block).Trim() + "`r`n"
Set-Content -Path $hostsFile -Value $new -Encoding ASCII

Write-Host "OK $hostsFile actualizado:" -ForegroundColor Green
Write-Host $block

# Limpiar cache DNS para que tome efecto de inmediato
ipconfig /flushdns | Out-Null

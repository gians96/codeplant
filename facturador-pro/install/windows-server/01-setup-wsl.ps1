<#
.SYNOPSIS
    Facturador Pro-8 — Fase 1: Preparar WSL2 + Docker en Windows Server
.DESCRIPTION
    Script de PowerShell que prepara el entorno Windows Server:
    1. Verifica virtualizacion (VT-x/AMD-V)
    2. Habilita WSL2 + Virtual Machine Platform
    3. Instala Ubuntu 24.04
    4. Crea usuario seguro
    5. Instala Docker Engine nativo (NO Docker Desktop)
    6. Genera data-config.txt con credenciales

    Al terminar, muestra instrucciones para ejecutar Fase 2
    (02-install-prod.sh o 02-install-dev.sh).

    POR QUE WSL2? PHP/Laravel lee miles de archivos por request.
    En NTFS via 9P: TTFB 4-8s. En ext4 nativo (WSL): <1s.

.NOTES
    Ejecutar como Administrador:
    powershell -ExecutionPolicy Bypass -File 01-setup-wsl.ps1
#>

#Requires -RunAsAdministrator

param(
    [string]$WslUser   = "pro8admin",
    [string]$WslDistro = "Ubuntu-24.04",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# ─── Helpers ────────────────────────────────────────────────
function Write-Step { param([string]$msg) Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$msg) Write-Host "   OK: $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "   WARN: $msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$msg) Write-Host "   FAIL: $msg" -ForegroundColor Red }

function Invoke-WslScript {
    param([string]$Distro, [string]$User, [string]$Script)
    $tmpFile = [System.IO.Path]::GetTempFileName() + ".sh"
    [System.IO.File]::WriteAllText($tmpFile, $Script.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
    try {
        $wslPath = wsl -d $Distro --user $User -- wslpath -u ($tmpFile -replace '\\','/')
        wsl -d $Distro --user $User -- bash $wslPath
        return $LASTEXITCODE
    } finally {
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
    }
}

# ═════════════════════════════════════════════════════════════
#  FASE 1 — Verificar virtualizacion
# ═════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  FACTURADOR PRO-8 — Setup WSL2 + Docker"    -ForegroundColor Cyan
Write-Host "  Fase 1: Preparacion del entorno"            -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Distro:  $WslDistro"
Write-Host "Usuario: $WslUser"
Write-Host ""

Write-Step "FASE 1: Verificando virtualizacion"

$vmfw = Get-CimInstance -ClassName Win32_ComputerSystem | Select-Object -ExpandProperty HypervisorPresent
$cpuVirt = (Get-CimInstance -ClassName Win32_Processor).VirtualizationFirmwareEnabled

if ($vmfw) {
    Write-Ok "Hypervisor detectado"
} elseif ($cpuVirt -contains $true) {
    Write-Ok "VT-x/AMD-V habilitado"
} else {
    $sysinfo = systeminfo.exe 2>$null | Select-String "Hyper-V|Virtualization"
    if ($sysinfo) {
        $virtLines = $sysinfo | ForEach-Object { $_.ToString().Trim() }
        $enabled = $virtLines | Where-Object { $_ -match "Yes|Si|Enabled|Habilitad" -and $_ -notmatch "No" }
        if (-not $enabled) {
            Write-Fail "Virtualizacion NO habilitada en BIOS/UEFI."
            Write-Host "  1. Reinicia y entra al BIOS (DEL/F2/F10)" -ForegroundColor Yellow
            Write-Host "  2. Busca Intel VT-x / AMD-V / SVM Mode" -ForegroundColor Yellow
            Write-Host "  3. Cambia a Enabled, guarda y reinicia" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Warn "No se pudo verificar. Si WSL falla, habilita VT-x/AMD-V en BIOS."
    }
}

# Features de Windows
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux 2>$null
$vmpFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform 2>$null
$needReboot = $false

if ($wslFeature -and $wslFeature.State -ne "Enabled") {
    Write-Step "Habilitando WSL feature ..."
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
    $needReboot = $true
} else { Write-Ok "WSL feature habilitada" }

if ($vmpFeature -and $vmpFeature.State -ne "Enabled") {
    Write-Step "Habilitando Virtual Machine Platform ..."
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
    $needReboot = $true
} else { Write-Ok "Virtual Machine Platform habilitada" }

if ($needReboot) {
    Write-Fail "REINICIO REQUERIDO. Vuelve a ejecutar este script despues."
    $r = Read-Host "Reiniciar ahora? (s/n)"
    if ($r -eq "s") { Restart-Computer -Force }
    exit 0
}

# ═════════════════════════════════════════════════════════════
#  FASE 2 — WSL2 + Ubuntu 24.04
# ═════════════════════════════════════════════════════════════
Write-Step "FASE 2: WSL2 y $WslDistro"

wsl --update 2>$null | Out-Null
wsl --set-default-version 2 2>$null | Out-Null
Write-Ok "WSL2 actualizado"

$installedDistros = wsl --list --quiet 2>$null
$distroInstalled = $false
if ($installedDistros) {
    $clean = ($installedDistros | ForEach-Object { $_ -replace "`0","" }) | Where-Object { $_.Trim() -ne "" }
    $distroInstalled = $clean -contains $WslDistro
}

if ($distroInstalled -and -not $Force) {
    Write-Ok "$WslDistro ya instalada"
} else {
    if ($distroInstalled -and $Force) {
        Write-Warn "Reinstalando $WslDistro (-Force)"
        wsl --unregister $WslDistro 2>$null | Out-Null
    }
    Write-Host "   Instalando $WslDistro ..." -ForegroundColor Gray
    wsl --install -d $WslDistro --no-launch 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { wsl --install -d $WslDistro 2>&1 | Out-Null }
    Write-Ok "$WslDistro instalada"
}

# ═════════════════════════════════════════════════════════════
#  FASE 3 — Usuario seguro
# ═════════════════════════════════════════════════════════════
Write-Step "FASE 3: Usuario '$WslUser'"

$passChars = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#%"
$securePass = -join ((1..16) | ForEach-Object { $passChars[(Get-Random -Maximum $passChars.Length)] })

wsl -d $WslDistro --user root -- id $WslUser 2>$null | Out-Null
if ($LASTEXITCODE -eq 0 -and -not $Force) {
    Write-Ok "Usuario '$WslUser' ya existe"
} else {
    $credLine = $WslUser + ':' + $securePass
    $script = (@'
set -e
if ! id __USER__ 2>/dev/null; then
    useradd -m -s /bin/bash -G sudo __USER__
fi
echo '__CRED__' | chpasswd
echo '__USER__ ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/__USER__
chmod 440 /etc/sudoers.d/__USER__
cat > /etc/wsl.conf << 'EOF'
[user]
default=__USER__
[interop]
appendWindowsPath=true
[automount]
enabled=true
options=metadata
EOF
'@).Replace('__USER__', $WslUser).Replace('__CRED__', $credLine)

    $exit = Invoke-WslScript -Distro $WslDistro -User "root" -Script $script
    if ($exit -ne 0) {
        Write-Fail "No se pudo crear el usuario."
        Write-Host "  Abre $WslDistro desde el menu Inicio para completar la config inicial." -ForegroundColor Yellow
        exit 1
    }
    Write-Ok "Usuario '$WslUser' creado"
}

# ═════════════════════════════════════════════════════════════
#  FASE 4 — Docker Engine
# ═════════════════════════════════════════════════════════════
Write-Step "FASE 4: Docker Engine en $WslDistro"

wsl -d $WslDistro --user $WslUser -- docker info 2>$null | Out-Null
if ($LASTEXITCODE -eq 0 -and -not $Force) {
    Write-Ok "Docker ya funciona"
} else {
    Write-Host "   Instalando Docker Engine (~2 min) ..." -ForegroundColor Gray

    $script = (@'
set -e
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg lsb-release git >/dev/null 2>&1
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
ARCH=$(dpkg --print-architecture)
CODENAME=$(. /etc/os-release && echo $VERSION_CODENAME)
echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $CODENAME stable" > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
usermod -aG docker __USER__
service docker start
docker --version
docker compose version
'@).Replace('__USER__', $WslUser)

    $exit = Invoke-WslScript -Distro $WslDistro -User "root" -Script $script
    if ($exit -ne 0) { Write-Fail "Error instalando Docker."; exit 1 }
    Write-Ok "Docker Engine instalado"
}

wsl -d $WslDistro --user root -- service docker start 2>$null | Out-Null

# ═════════════════════════════════════════════════════════════
#  FASE 5 — Abrir puerto en Windows Firewall
# ═════════════════════════════════════════════════════════════
Write-Step "FASE 5: Configurando Windows Firewall"

$firewallPorts = @(80, 443, 8080)
foreach ($port in $firewallPorts) {
    $ruleName = "Facturador-Pro8-Puerto-$port"
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Ok "Regla firewall ya existe: $ruleName"
    } else {
        New-NetFirewallRule -DisplayName $ruleName `
            -Direction Inbound -Protocol TCP -LocalPort $port `
            -Action Allow -Profile Domain,Private | Out-Null
        Write-Ok "Regla firewall creada: $ruleName (puerto $port)"
    }
}

# ═════════════════════════════════════════════════════════════
#  FASE 6 — Generar data-config.txt
# ═════════════════════════════════════════════════════════════
Write-Step "FASE 6: Generando data-config.txt"

$configDate = Get-Date -Format 'yyyy-MM-dd HH:mm'
$dataConfigPath = Join-Path $ScriptDir "data-config.txt"

$configContent = @"
# ============================================
# FACTURADOR PRO-8 — DATOS DE CONFIGURACION
# Generado: $configDate
# ============================================
#
# FASE 1 — Entorno WSL2 + Docker
# ============================================
Distro:   $WslDistro
Usuario:  $WslUser
Password: $securePass

# Para ingresar al bash de WSL:
#   wsl -d $WslDistro
#
# Para iniciar Docker (si no arranca solo):
#   sudo service docker start
#
# ============================================
# FASE 2 — Se completara al ejecutar el script de instalacion
# ============================================
"@

Set-Content -Path $dataConfigPath -Value $configContent -Encoding UTF8
Write-Ok "data-config.txt generado en: $dataConfigPath"

# ═════════════════════════════════════════════════════════════
#  RESUMEN
# ═════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  FASE 1 COMPLETADA"                          -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Distro:   $WslDistro"
Write-Host "  Usuario:  $WslUser"
Write-Host "  Password: $securePass"
Write-Host "  Docker:   Instalado"
Write-Host ""
Write-Host "  Credenciales guardadas en: data-config.txt" -ForegroundColor Gray
Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  SIGUIENTE PASO — Fase 2"                    -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Ingresa a WSL:" -ForegroundColor White
Write-Host "    wsl -d $WslDistro" -ForegroundColor White
Write-Host ""
Write-Host "  Descarga y ejecuta el script de instalacion:" -ForegroundColor White
Write-Host ""
Write-Host "  PRODUCCION (con dominio, proxy, SSL):" -ForegroundColor Cyan
Write-Host "    curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/02-install-prod.sh" -ForegroundColor White
Write-Host "    chmod +x 02-install-prod.sh" -ForegroundColor White
Write-Host "    sudo ./02-install-prod.sh" -ForegroundColor White
Write-Host ""
Write-Host "  DESARROLLO (local, sin proxy ni SSL):" -ForegroundColor Cyan
Write-Host "    curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/02-install-dev.sh" -ForegroundColor White
Write-Host "    chmod +x 02-install-dev.sh" -ForegroundColor White
Write-Host "    ./02-install-dev.sh" -ForegroundColor White
Write-Host ""

# Instala Docker Desktop con winget y limita la memoria de WSL2. Pide permisos de administrador (un clic en "Si").
# Uso, en PowerShell normal:   .\scripts\instalar_docker_desktop.ps1
# Despues: reinicia si Windows lo pide, abre Docker Desktop, espera 'Engine running' y corre .\scripts\iniciar.ps1
# Seguro de repetir: si ya esta instalado lo detecta, y nunca pisa un .wslconfig existente.
# (Archivo solo ASCII a proposito: PowerShell 5.1 lee mal los acentos sin BOM.)
param([string]$PerfilUsuario = $env:USERPROFILE)   # se pasa a la ventana elevada para escribir .wslconfig en TU perfil

$ErrorActionPreference = "Continue"   # los .exe nativos escriben avisos en stderr; no deben abortar el script

function Pausa-Y-Salir([int]$codigo) { Read-Host "Enter para cerrar" | Out-Null; exit $codigo }

try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        if (-not $PSCommandPath) {
            Write-Host "[X] No pude saber la ruta del script. Guardalo como archivo .ps1 y ejecutalo con: .\scripts\instalar_docker_desktop.ps1" -ForegroundColor Red
            Pausa-Y-Salir 1
        }
        Write-Host "Se necesitan permisos de administrador; se abrira una ventana de confirmacion (UAC)..."
        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -PerfilUsuario `"$PerfilUsuario`"" -ErrorAction Stop
            Write-Host "Continua en la ventana de administrador que se abrio (la instalacion sigue alli)."
        } catch {
            Write-Host "[X] No se obtuvieron permisos de administrador (cancelaste el UAC?). Vuelve a correr el script y pulsa 'Si'." -ForegroundColor Red
            exit 1
        }
        exit 0
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "[X] winget no esta disponible. Descarga Docker Desktop desde https://www.docker.com/products/docker-desktop/ e instalalo a mano." -ForegroundColor Red
        Pausa-Y-Salir 1
    }

    $freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
    if ($freeGB -lt 8) {
        Write-Host "[X] Solo hay $freeGB GB libres en C:. Libera al menos 8 GB antes de instalar." -ForegroundColor Red
        Pausa-Y-Salir 1
    }

    Write-Host "Instalando Docker Desktop (descarga grande; puede tardar varios minutos)..."
    winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
    $code = $LASTEXITCODE
    # Codigos de winget: https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md
    #   -1978335189 (0x8A15002B) sin actualizacion aplicable / -1978335135 (0x8A150061) y -1978334963 (0x8A15010D) ya instalado
    #   -1978334967 (0x8A150109) instalado, falta reiniciar para terminar
    $yaInstalado = @(-1978335189, -1978335135, -1978334963)
    $reiniciar = $false
    if ($code -eq -1978334967) {
        $reiniciar = $true
    } elseif ($yaInstalado -contains $code) {
        Write-Host "Docker Desktop ya estaba instalado (winget codigo $code); sigo con el resto."
    } elseif ($code -ne 0) {
        Write-Host "[X] winget termino con codigo $code. Copia el mensaje de arriba y mandalo." -ForegroundColor Red
        Pausa-Y-Salir 1
    }

    # Limitar la memoria que WSL2 puede tomar (solo si el usuario no tiene ya un .wslconfig)
    $wslcfg = Join-Path $PerfilUsuario ".wslconfig"
    if (-not (Test-Path $wslcfg)) {
        Set-Content -Path $wslcfg -Value "[wsl2]`r`nmemory=4GB`r`nprocessors=2" -Encoding ASCII
        Write-Host "Creado $wslcfg (memoria de WSL2 limitada a 4 GB)."
    } else {
        Write-Host "Ya existe $wslcfg; no se modifica."
    }

    Write-Host ""
    Write-Host "[OK] Docker Desktop instalado." -ForegroundColor Green
    if ($reiniciar) { Write-Host "Windows pide REINICIAR para terminar la instalacion: reinicia el equipo ahora." -ForegroundColor Yellow }
    Write-Host "Siguiente: reinicia el equipo si Windows lo pide, abre Docker Desktop (acepta los terminos),"
    Write-Host "activa 'Start Docker Desktop when you sign in', espera 'Engine running' y corre .\scripts\iniciar.ps1"
    Write-Host "Si Docker Desktop se queja de WSL, corre en PowerShell:  wsl --update"
    Pausa-Y-Salir 0
} catch {
    Write-Host "[X] Error inesperado: $($_.Exception.Message)" -ForegroundColor Red
    Pausa-Y-Salir 1
}

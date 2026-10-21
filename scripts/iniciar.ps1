# Levanta el stack del Lab 5 en Windows (Docker Desktop) y arranca la toma de 4 dias.
# Uso, en PowerShell:   .\scripts\iniciar.ps1
# Es seguro volver a correrlo: NO sobrescribe la hora de inicio de la toma.
# (Archivo solo ASCII a proposito: PowerShell 5.1 lee mal los acentos sin BOM.)

$ErrorActionPreference = "Continue"   # los .exe nativos escriben avisos en stderr; no deben abortar el script
Set-Location (Split-Path $PSScriptRoot -Parent)

function Fail($msg) { Write-Host "[X] $msg" -ForegroundColor Red; exit 1 }
function Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }

# 1. Docker disponible y corriendo
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Fail "No se encuentra el comando 'docker'. Si acabas de instalar Docker Desktop, cierra esta ventana de PowerShell y abre otra. Si no lo has instalado: .\scripts\instalar_docker_desktop.ps1 (o ver README)."
}
# Tras un reinicio el motor tarda en arrancar: reintenta hasta ~60 s antes de rendirse
$engineUp = $false
for ($i = 0; $i -lt 12; $i++) {
    docker info *> $null
    if ($LASTEXITCODE -eq 0) { $engineUp = $true; break }
    if ($i -eq 0) { Write-Host "Esperando a que Docker Desktop responda (abrelo si no esta abierto)..." }
    Start-Sleep -Seconds 5
}
if (-not $engineUp) {
    Fail "Docker Desktop no esta corriendo. Abrelo y espera a que diga 'Engine running'; luego vuelve a correr este script."
}
Ok "Docker responde"

# 2. .env presente
if (-not (Test-Path ".env")) {
    Fail "Falta el archivo .env. Copia .env.example a .env y cambia token y claves."
}
Ok ".env encontrado"

# 3. Espacio en disco (imagenes + datos)
$freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
if ($freeGB -lt 4) { Fail "Solo hay $freeGB GB libres en C:. Libera espacio (minimo 4 GB) y reintenta." }
Ok "Espacio libre en C: $freeGB GB"

# 4. Levantar
Write-Host "Levantando servicios (la primera vez descarga imagenes, puede tardar varios minutos)..."
docker compose up -d --build
if ($LASTEXITCODE -ne 0) { Fail "docker compose up fallo. Revisa el error de arriba y manda las ultimas lineas." }

# 5. Esperar a InfluxDB healthy (hasta 3 min)
$healthy = $false
for ($i = 0; $i -lt 36; $i++) {
    $id = (docker compose ps -q influxdb)
    if ($id) {
        $state = (docker inspect --format "{{.State.Health.Status}}" $id 2>$null)
        if ($state -eq "healthy") { $healthy = $true; break }
    }
    Start-Sleep -Seconds 5
}
if (-not $healthy) { Fail "InfluxDB no llego a 'healthy'. Corre: docker compose logs influxdb" }
Ok "InfluxDB healthy"

# 6. Esperar a que el publicador publique (hasta 60 s)
$publishing = $false
for ($i = 0; $i -lt 12; $i++) {
    $logs = (docker compose logs --no-color --tail 20 publisher 2>$null) -join "`n"
    if ($logs -match "\[pub\]") { $publishing = $true; break }
    Start-Sleep -Seconds 5
}
if (-not $publishing) { Fail "El publicador no esta publicando. Corre: docker compose logs publisher mosquitto" }
Ok "El publicador esta publicando"

# 7. Registrar la hora de inicio (solo la primera vez)
New-Item -ItemType Directory -Force -Path "evidencias" | Out-Null
$startFile = "evidencias\inicio_toma.txt"
if (-not (Test-Path $startFile)) {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss") + " UTC"
    Set-Content -Path $startFile -Value "Inicio de la toma: $stamp" -Encoding ASCII
    Ok "Hora de inicio registrada en $startFile"
} else {
    Write-Host ("[--] Ya existia " + (Get-Content $startFile) + " (no se modifica)")
}

docker compose ps
Write-Host ""
Write-Host "Listo. Grafana: http://localhost:3000  (usuario admin; clave = GRAFANA_PASSWORD en .env)" -ForegroundColor Cyan
Write-Host "Si el PC se reinicia: inicia sesion, abre Docker Desktop y la toma se reanuda sola."

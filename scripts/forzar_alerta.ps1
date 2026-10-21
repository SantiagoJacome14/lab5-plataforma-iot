# Fuerza el valor de temperatura desde el publicador, espera el disparo y guarda la evidencia.
# Uso:   .\scripts\forzar_alerta.ps1            (45 C durante 150 s)
#        .\scripts\forzar_alerta.ps1 -Temperatura 50 -Segundos 200
# Seguro de repetir: solo cuenta como exito un FIRING NUEVO (posterior al momento en que se ejecuta el script).
# (Archivo solo ASCII a proposito: PowerShell 5.1 lee mal los acentos sin BOM.)
param([double]$Temperatura = 45, [int]$Segundos = 150)

$ErrorActionPreference = "Continue"   # los .exe nativos escriben avisos en stderr; no deben abortar el script
Set-Location (Split-Path $PSScriptRoot -Parent)
New-Item -ItemType Directory -Force -Path "evidencias" | Out-Null

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "[X] No se encuentra el comando 'docker'. Abre Docker Desktop / una ventana nueva de PowerShell." -ForegroundColor Red; exit 1
}

# Numero con punto decimal siempre (la configuracion regional podria usar coma)
$tStr = $Temperatura.ToString([Globalization.CultureInfo]::InvariantCulture)

# Cuantos FIRING hay ya en el log del receptor (el log conserva disparos de corridas anteriores)
function Count-Firing([string]$text) { return [regex]::Matches($text, '-\s+FIRING\s').Count }   # sensible a mayusculas
$before = (docker compose logs --no-color alert-sink 2>$null) -join "`n"
$baseline = Count-Firing $before

Write-Host "Ordenando al publicador sostener $tStr C durante $Segundos s..."
docker compose exec -T publisher python publisher.py force --temperature $tStr --seconds $Segundos
if ($LASTEXITCODE -ne 0) { Write-Host "[X] No se pudo enviar la orden. Esta corriendo el stack? (.\scripts\iniciar.ps1)" -ForegroundColor Red; exit 1 }

Write-Host "Esperando el disparo (la regla evalua cada 30 s y pasa por Pending; hasta 4 min)."
Write-Host "Mientras tanto abre Grafana > Alerting > Alert rules y captura Normal -> Pending -> Firing (evidencia 05)."
$fired = $false
$log = ""
for ($i = 0; $i -lt 24; $i++) {
    $log = (docker compose logs --no-color alert-sink 2>$null) -join "`n"
    if ((Count-Firing $log) -gt $baseline) { $fired = $true; break }
    Start-Sleep -Seconds 10
}
if ($fired) {
    Set-Content -Path "evidencias\06_alert_sink_log.txt" -Value $log -Encoding UTF8
    Write-Host "[OK] La alerta llego al webhook. Log guardado en evidencias\06_alert_sink_log.txt" -ForegroundColor Green
    ($log -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 8) -join "`n"
} else {
    Write-Host "[!!] No llego un FIRING nuevo en 4 min. Revisa: docker compose logs grafana alert-sink  y el estado de la regla en Grafana." -ForegroundColor Yellow
    Write-Host "     (Si la alerta ya estaba en Firing antes de correr esto, Grafana no reenvia hasta repeat_interval; espera a que pase a Normal y repite.)"
    exit 1
}

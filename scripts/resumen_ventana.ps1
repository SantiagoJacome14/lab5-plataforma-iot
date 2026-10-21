# Resumen de la toma para el informe: inicio, fin, total de puntos y horas con huecos.
# Uso:   .\scripts\resumen_ventana.ps1 [-Dias 4]      Guarda la salida en evidencias\07_resumen_ventana.txt
# (Archivo solo ASCII a proposito: PowerShell 5.1 lee mal los acentos sin BOM.)
param([int]$Dias = 4)

$ErrorActionPreference = "Continue"   # los .exe nativos escriben avisos en stderr; no deben abortar el script
Set-Location (Split-Path $PSScriptRoot -Parent)
New-Item -ItemType Directory -Force -Path "evidencias" | Out-Null

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "[X] No se encuentra el comando 'docker'. Abre Docker Desktop / una ventana nueva de PowerShell." -ForegroundColor Red; exit 1
}
if (-not (Test-Path ".env")) { Write-Host "[X] Falta el archivo .env" -ForegroundColor Red; exit 1 }

# Leer .env (KEY=VALUE); quita comillas envolventes como hace docker compose
$cfg = @{}
Get-Content ".env" | ForEach-Object {
    if ($_ -match "^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$") {
        $v = $Matches[2].Trim()
        if ($v.Length -ge 2 -and (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'")))) { $v = $v.Substring(1, $v.Length - 2) }
        $cfg[$Matches[1]] = $v
    }
}
$org = $cfg["INFLUX_ORG"]; $token = $cfg["INFLUX_TOKEN"]
if (-not $org -or -not $token) { Write-Host "[X] Faltan INFLUX_ORG / INFLUX_TOKEN en .env" -ForegroundColor Red; exit 1 }

# El contenedor de InfluxDB debe estar corriendo
$cid = (docker compose ps -q influxdb 2>$null)
if (-not $cid) { Write-Host "[X] El contenedor influxdb no esta corriendo. Corre primero .\scripts\iniciar.ps1" -ForegroundColor Red; exit 1 }

# Ventana desde evidencias\inicio_toma.txt (hora anotada -5 min, hasta +N dias +5 min); si no existe, ultimos N dias
$range = "range(start: -" + $Dias + "d)"
if (Test-Path "evidencias\inicio_toma.txt") {
    $m = [regex]::Match((Get-Content "evidencias\inicio_toma.txt" -Raw), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) UTC')
    if ($m.Success) {
        $t0 = [datetime]::ParseExact($m.Groups[1].Value, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
        $range = "range(start: " + $t0.AddMinutes(-5).ToString("yyyy-MM-ddTHH:mm:ss") + "Z, stop: " + $t0.AddDays($Dias).AddMinutes(5).ToString("yyyy-MM-ddTHH:mm:ss") + "Z)"
    }
}
$base = 'from(bucket: "lab5") |> ' + $range + ' |> filter(fn: (r) => r._measurement == "ambiental" and r._field == "temperature")'
$queries = [ordered]@{
    "Primer punto (inicio de la toma)" = $base + ' |> first() |> keep(columns: ["_time", "_value"])'
    "Ultimo punto"                      = $base + ' |> last() |> keep(columns: ["_time", "_value"])'
    "Total de puntos de temperature"    = $base + ' |> count() |> keep(columns: ["_value"])'
    "Horas con menos de 300 mensajes (esperado ~360 a 10 s; la primera y la ultima hora son parciales y es normal que salgan)" = $base + ' |> aggregateWindow(every: 1h, fn: count, createEmpty: true) |> filter(fn: (r) => not exists r._value or r._value < 300) |> keep(columns: ["_time", "_value"])'
}

# Las comillas dobles del Flux se pierden al pasarlas como argumento en PowerShell 5.1,
# asi que la consulta viaja como archivo. Ruta RELATIVA (sin "C:") para que "docker compose cp"
# no la confunda con SERVICIO:RUTA.
$tmpRel = "evidencias\_q_tmp.flux"
$out = New-Object System.Collections.Generic.List[string]
foreach ($title in $queries.Keys) {
    [IO.File]::WriteAllText((Join-Path (Get-Location).Path $tmpRel), $queries[$title], (New-Object System.Text.UTF8Encoding($false)))
    $cpMsg = docker compose cp $tmpRel influxdb:/tmp/q.flux 2>&1 | ForEach-Object { "$_" }
    $cpCode = $LASTEXITCODE
    $out.Add("== $title ==")
    if ($cpCode -ne 0) {
        $out.Add("[ERROR] no se pudo copiar la consulta al contenedor: " + ($cpMsg -join " "))
    } else {
        # 2>&1 en 5.1 convierte stderr en ErrorRecord; "$_" lo vuelve texto plano
        $res = docker compose exec -T influxdb influx query --org $org --token $token --file /tmp/q.flux --raw 2>&1 | ForEach-Object { "$_" }
        $qCode = $LASTEXITCODE
        $out.Add((($res -join "`n")).Trim())
        if ($qCode -ne 0) { $out.Add("[ERROR] influx query termino con codigo $qCode") }
    }
    $out.Add("")
}
Remove-Item (Join-Path (Get-Location).Path $tmpRel) -ErrorAction SilentlyContinue
docker compose exec -T influxdb rm -f /tmp/q.flux 2>$null | Out-Null

$text = $out -join "`n"
Set-Content -Path "evidencias\07_resumen_ventana.txt" -Value $text -Encoding UTF8
Write-Host $text
Write-Host "Guardado en evidencias\07_resumen_ventana.txt" -ForegroundColor Cyan

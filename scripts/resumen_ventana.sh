#!/usr/bin/env bash
# Resumen de la toma para el informe: inicio, fin, total de puntos y horas con huecos.
# Uso (en la VM, dentro de la carpeta del proyecto):  bash scripts/resumen_ventana.sh [dias=4]
# La ventana se calcula desde evidencias/inicio_toma.txt (hora anotada, menos 5 min porque el stack
# arranca un poco antes de anotarla) hasta esa hora + N dias. Sin ese archivo usa "ultimos N dias".
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
DIAS="${1:-4}"

if [ -f evidencias/inicio_toma.txt ] && RAW=$(sed -n 's/.*: \([0-9-]* [0-9:]*\) UTC.*/\1/p' evidencias/inicio_toma.txt | head -1) && [ -n "$RAW" ]; then
  INICIO=$(date -u -d "$RAW UTC - 5 minutes" +%Y-%m-%dT%H:%M:%SZ)
  FIN=$(date -u -d "$RAW UTC + $DIAS days + 5 minutes" +%Y-%m-%dT%H:%M:%SZ)
  RANGE="range(start: ${INICIO}, stop: ${FIN})"
  echo "Ventana analizada: ${INICIO} -> ${FIN} (desde inicio_toma.txt: ${RAW} UTC, ${DIAS} dias)"
else
  RANGE="range(start: -${DIAS}d)"
  echo "Ventana analizada: ultimos ${DIAS} dias (no hay evidencias/inicio_toma.txt)"
fi
BASE="from(bucket:\"lab5\") |> ${RANGE} |> filter(fn:(r)=>r._measurement==\"ambiental\" and r._field==\"temperature\")"

q() {  # q "<flux>"
  docker compose exec -T influxdb influx query --org "$INFLUX_ORG" --token "$INFLUX_TOKEN" --raw "$1" | tr -d '\r'
}

echo; echo "== Primer punto (inicio de la toma) =="
q "${BASE} |> first() |> keep(columns:[\"_time\",\"_value\"])"

echo; echo "== Ultimo punto =="
q "${BASE} |> last() |> keep(columns:[\"_time\",\"_value\"])"

echo; echo "== Total de puntos de temperature (esperado ~360 por hora a 10 s) =="
q "${BASE} |> count() |> keep(columns:[\"_value\"])"

echo; echo "== Horas con menos de 300 mensajes (la primera y la ultima hora son parciales y es normal que salgan) =="
q "${BASE} |> aggregateWindow(every: 1h, fn: count, createEmpty: true) |> filter(fn:(r)=> not exists r._value or r._value < 300) |> keep(columns:[\"_time\",\"_value\"])"

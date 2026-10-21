# Laboratorio 5 — MQTT → InfluxDB → Grafana en una VM

Plataforma propia, primera pieza: un publicador MQTT (simulado) escribe temperatura, humedad e iluminancia;
Telegraf las lleva a InfluxDB con marca de tiempo real; Grafana las lee **aparte** y muestra una toma de 4 días
con una alerta de umbral.

```
publisher ──MQTT QoS1──▶ mosquitto ──▶ telegraf ──▶ influxdb ◀── grafana ──webhook──▶ alert-sink
 (Python)    :1883        (broker)    (suscriptor)    (TSDB)     (lee, alerta)         (log)
```

| Pieza | Imagen | Rol |
|---|---|---|
| `mosquitto` | `eclipse-mosquitto:2.0` | Broker MQTT (protocolo elegido) |
| `telegraf` | `telegraf:1.32` | Suscriptor MQTT → escribe en InfluxDB |
| `influxdb` | `influxdb:2.7` | TSDB, bucket `lab5`, sin expiración |
| `grafana` | `grafana/grafana-oss:11.3.0` | Dashboard + alertas (datasource y reglas provisionados por archivo) |
| `publisher` | build local (`publisher/`) | Publica cada `PUBLISH_INTERVAL` s en `lab5/<device>/telemetry` |
| `alert-sink` | `python:3.12-alpine` | Receptor del webhook de Grafana; la evidencia queda en su log |

Los datos son **simulados** (ciclo diario + ruido); eso se declara en el informe.

## Requisitos de la VM

Linux con Docker Engine y el plugin `docker compose` (2 GB de RAM sobran). En Ubuntu:

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker
sudo systemctl enable docker        # para que la toma sobreviva a un reinicio de la VM
```

### Alternativa: Docker Desktop en Windows 11 (WSL2)

Mismos archivos y mismo `docker-compose.yml`. Es el **plan B** que se preparó cuando la VM del curso no respondió y aún no había
suscripción de Azure; al final **no hizo falta**: la toma real corrió en una VM de Azure (Debian 12, B2as_v2) con los comandos
de las secciones "Sesión 1" y "Sesión 2". Scripts de PowerShell en `scripts\`:

| Script | Qué hace |
|---|---|
| `instalar_docker_desktop.ps1` | Instala Docker Desktop con winget (pide UAC) y limita WSL2 a 4 GB en `.wslconfig` si no existe |
| `iniciar.ps1` | Comprueba Docker, `.env` y espacio (mín. 4 GB); `docker compose up -d --build`; espera a InfluxDB sano y al publicador; escribe `evidencias\inicio_toma.txt` (solo la primera vez) |
| `forzar_alerta.ps1` | Fuerza 45 °C durante 150 s desde el publicador, espera el webhook y guarda `evidencias\06_alert_sink_log.txt` (`-Temperatura`, `-Segundos` opcionales) |
| `resumen_ventana.ps1` | Inicio, fin, total de puntos y horas con huecos; guarda `evidencias\07_resumen_ventana.txt` (`-Dias 4`) |

#### Primeros 30 minutos, desde cero en Windows (orden exacto)

Todo en PowerShell normal (no como administrador), dentro de la carpeta del proyecto.

1. **Min 0-3, requisitos.** Administrador de tareas > Rendimiento > CPU: *Virtualización: Habilitada* (si dice
   Deshabilitada, actívala en la BIOS/UEFI antes de seguir). Mínimo 8 GB libres en C: y conexión a internet.
2. **Min 3-5, permitir los scripts** (Windows 11 los bloquea por defecto; vale solo para esta ventana):
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   Get-ChildItem -Recurse | Unblock-File
   ```
3. **Min 5-20, instalar Docker Desktop:** `.\scripts\instalar_docker_desktop.ps1` (acepta el UAC). Si Windows pide reiniciar,
   reinicia y vuelve a abrir PowerShell en la carpeta (repite el paso 2). Abre Docker Desktop, acepta los términos,
   espera *Engine running* y activa *Start Docker Desktop when you sign in*. Comprueba: `docker compose version`.
4. **Min 20-23, crear `.env`** (sin secretos en el repo; `.env` está en `.gitignore`):
   ```powershell
   Copy-Item .env.example .env
   $b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
   ($b | ForEach-Object { $_.ToString('x2') }) -join ''     # copia este valor a INFLUX_TOKEN
   notepad .env                                              # cambia INFLUX_TOKEN, INFLUX_PASSWORD y GRAFANA_PASSWORD
   ```
5. **Min 23-30, levantar y arrancar la toma:** `.\scripts\iniciar.ps1`. La primera vez descarga las imágenes (varios
   minutos). Al terminar queda `evidencias\inicio_toma.txt`: **esa es la hora de inicio de los 4 días**.
6. **Justo después, verificar y capturar** (ver la tabla de evidencias): `docker compose ps` (01), el smoke test de abajo
   (02, 03) y Grafana en `http://localhost:3000` con el usuario/clave de `.env` (el dashboard ya aparece como inicio).
7. **Antes de apagar la pantalla**, para que la toma no se corte: Configuración > Energía > Suspender = *Nunca* con el
   equipo conectado, cierre de tapa = *No hacer nada*. Si el PC se reinicia: inicia sesión, abre Docker Desktop y la
   toma se reanuda sola (`restart: unless-stopped`); el apagón queda como hueco y se documenta.

Si prefieres hacerlo a mano en lugar de `iniciar.ps1`: `docker compose up -d --build` y anota la hora UTC.
Grafana queda en `http://localhost:3000` (`GRAFANA_BIND=127.0.0.1`). Los scripts `.sh` se ejecutan desde Git Bash.

**Para que un compañero lea el dashboard desde otro equipo:** en `.env` pon `GRAFANA_BIND=0.0.0.0` y
`GRAFANA_ANONYMOUS=true` (solo lectura), vuelve a correr `docker compose up -d` y permite el puerto 3000 en el
firewall de Windows. Devuélvelos a `127.0.0.1` / `false` al terminar.

## Sesión 1 — levantar el stack y arrancar la toma (VM Linux o Git Bash)

En Windows esto lo hace `iniciar.ps1` (pasos 4-5 de arriba).

```bash
cp .env.example .env                # edita contraseñas y token (openssl rand -hex 32)
docker compose up -d --build
docker compose ps                   # los 6 servicios en "running" (influxdb "healthy")
```

La toma de 4 días **ya está corriendo**: el contenedor `publisher` publica solo y todos los servicios
tienen `restart: unless-stopped`. Anota la hora de inicio (`date -u | tee evidencias/inicio_toma.txt`) para el informe.

### Verificación salto por salto (smoke test)

```bash
# 1. el publicador publica
docker compose logs --tail 3 publisher

# 2. el broker recibe (3 mensajes y sale)
docker compose exec mosquitto mosquitto_sub -t 'lab5/#' -C 3 -v

# 3. InfluxDB guardó puntos con su marca de tiempo (bash; en Windows usa resumen_ventana.ps1
#    o el Data Explorer en http://localhost:8086 con INFLUX_USER / INFLUX_PASSWORD de .env)
set -a; . ./.env; set +a
docker compose exec -T influxdb influx query --org "$INFLUX_ORG" --token "$INFLUX_TOKEN" \
  'from(bucket:"lab5") |> range(start:-5m) |> filter(fn:(r)=>r._measurement=="ambiental") |> last()'

# 4. Grafana: http://localhost:3000 (o http://<IP-de-la-VM>:3000)  (usuario/clave de .env) → dashboard "Lab 5 — Monitoreo ambiental"
```

Si Grafana aparece vacío, revisa en este orden: `docker compose logs telegraf` (errores de escritura o de
formato de tiempo), Connections → Data sources → *Test*, y el rango de tiempo del dashboard.

## Sesión 2 — dashboard, alerta y lectura de la muestra

El dashboard (`grafana/dashboards/lab5-ambiental.json`) viene provisionado: serie temporal por variable sobre
`now-4d`, stats con unidad y rango del escenario, título + una línea de qué mira el operador, conteo de mensajes
por hora (los huecos de la toma se ven como barras bajas) y estado de las alertas.

**Alerta:** *Temperatura alta* — máximo de `temperature` en los últimos 2 min **> 35 °C**, evaluada cada 30 s,
`for 30 s`; acción: webhook al contenedor `alert-sink`. El rango normal del escenario es 16–32 °C, así que no
se dispara sola.

**Forzar el disparo desde el publicador** (sostiene 45 °C durante 150 s; en Windows: `.\scripts\forzar_alerta.ps1`).
El pico de 45 °C queda en la serie de 4 días: anótalo en el informe para que no parezca una falla del sensor.

```bash
docker compose exec publisher python publisher.py force --temperature 45 --seconds 150
# Grafana → Alerting → Alert rules: Normal → Pending → Firing (~1 min)
docker compose logs --tail 20 alert-sink        # llega el webhook con status=FIRING
# ~2 min después de terminar el forzado pasa a Resolved (también queda en el log)
```

**Datos de la ventana para el informe** (inicio, fin, total de puntos, horas con huecos):

```bash
bash scripts/resumen_ventana.sh 4        # Linux / Git Bash
.\scripts\resumen_ventana.ps1            # Windows (PowerShell)
```

Fin de la toma = inicio + 96 h. Si la sesión 2 cierra antes, el informe indica esa fecha de corte y las capturas finales se
adjuntan al entregar. Esperado: 34.560 puntos por variable; una hora con menos de ~300 mensajes es un hueco.

### Evidencias (`/evidencias`)

Estado: **todas capturadas** durante la toma real (17 al 21 de octubre de 2026, VM de Azure). Los `.txt` los generan los
scripts o la consola de la VM; los `.png` son capturas de pantalla con la hora visible. Del dashboard hay dos capturas del rango
de 4 días (`04_dashboard_4dias_arriba.png` y `04b_dashboard_4dias_abajo.png`) y tres de la alerta (`05a`, `05b` y `05`).

| Archivo | Qué muestra | Cuándo | Origen |
|---|---|---|---|
| `inicio_toma.txt` | hora UTC de inicio de la toma | sesión 1 | `iniciar.ps1` |
| `01_compose_ps.png` | `docker compose ps` con los 6 servicios arriba | sesión 1 | captura |
| `02_mosquitto_sub.png` | mensajes MQTT reales en el broker | sesión 1 | captura |
| `03_consulta_influx.png` | consulta a InfluxDB con los puntos guardados | sesión 1 | captura |
| `04_dashboard_4dias.png` | dashboard con rango `now-4d` (si no completa 4 días: `04_dashboard_corte.png` el día del corte, y la final al entregar) | sesión 2 y al entregar | captura |
| `05_alerta_firing.png` | regla en *Firing* en Grafana (Normal → Pending → Firing) | sesión 2 | captura |
| `06_alert_sink_log.txt` | log del webhook con `FIRING` (opcional: `06_alert_sink_log.png`) | sesión 2 | `forzar_alerta.ps1` |
| `07_resumen_ventana.txt` | inicio, fin, total de puntos, horas con huecos | al entregar | `resumen_ventana.ps1` / `.sh` |

## Notas

- **Sin secretos en el repo:** todo sale de `.env` (ignorado por git). Mosquitto es anónimo y solo escucha en
  `127.0.0.1` del host; si otros equipos deben publicar, activa `password_file` antes de abrir el puerto.
- InfluxDB solo inicializa usuario/token en el **primer arranque**. Si cambias `.env` después, borra los volúmenes
  (`docker compose down -v`; se pierde la toma).
- Si la VM (o el PC) se apaga, la toma queda con un hueco: se documenta en el informe (el lab lo permite).
- Raspberry Pi (migración posterior): las imágenes tienen variante `arm64`; InfluxDB 2.x no soporta `armv7` (usar OS de 64 bits).
- Regenerar el dashboard tras editar `scripts/build_dashboard.py`: `python scripts/build_dashboard.py`.

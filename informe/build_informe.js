const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, ShadingType, ImageRun,
} = require("docx");

const diagram = fs.readFileSync(path.join(__dirname, "diagrama_lab5.png"));
const GOLD = "B7862A", DARK = "1F2937";

const p = (t, o = {}) => new Paragraph({ spacing: { after: 100 }, children: [new TextRun({ text: t, size: 20, ...o })] });
const h1 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, spacing: { before: 200, after: 90 }, children: [new TextRun({ text: t, bold: true, color: GOLD, size: 26 })] });
const bullet = (t) => new Paragraph({ bullet: { level: 0 }, spacing: { after: 40 }, children: [new TextRun({ text: t, size: 20 })] });
const pending = (t) => new Paragraph({
  spacing: { before: 60, after: 120 },
  shading: { type: ShadingType.CLEAR, fill: "FEF3C7" },
  children: [new TextRun({ text: `PENDIENTE: ${t}`, size: 18, bold: true, color: "92400E" })],
});

const cell = (t, w, o = {}) => new TableCell({
  width: { size: w, type: WidthType.DXA },
  shading: o.shade ? { type: ShadingType.CLEAR, fill: o.shade } : undefined,
  margins: { top: 60, bottom: 60, left: 90, right: 90 },
  children: [new Paragraph({ children: [new TextRun({ text: t, size: 18, bold: !!o.head, color: o.head ? "FFFFFF" : "000000" })] })],
});
function kvTable(rows, w1 = 2600, w2 = 6760) {
  return new Table({
    width: { size: w1 + w2, type: WidthType.DXA }, columnWidths: [w1, w2],
    rows: rows.map(([k, v], i) => new TableRow({ children: [cell(k, w1, { head: true, shade: DARK }), cell(v, w2, i < 0 ? {} : {})] })),
  });
}

const PX = 96;
const dW = 6.5 * PX, dH = dW * (560 / 2000);

const doc = new Document({
  sections: [{
    properties: { page: { size: { width: 12240, height: 15840 }, margin: { top: 900, bottom: 900, left: 1440, right: 1440 } } },
    children: [
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 40 }, children: [new TextRun({ text: "LABORATORIO 5: VISUALIZACIÓN + REGLAS / ALERTAS", bold: true, size: 30 })] }),
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 80 }, children: [new TextRun({ text: "MQTT, InfluxDB y Grafana en una VM", italics: true, size: 22, color: "475569" })] }),
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 140 }, children: [new TextRun({ text: "Dawer Stiven Patiño · Julian Mejia · Santiago Jacome", size: 19 })] }),
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 140 }, children: [new TextRun({ text: "Repositorio: https://github.com/SantiagoJacome14/lab5-plataforma-iot", size: 19, color: "1D4ED8" })] }),

      h1("1. Arquitectura"),
      p("Un publicador Python envía temperature, humidity e illuminance por MQTT (QoS 1) a Mosquitto; Telegraf, suscrito al topic lab5/+/telemetry, escribe cada mensaje en InfluxDB con la marca de tiempo del publicador. Grafana OSS está instalado aparte y solo consulta la TSDB (Flux); la regla de alerta notifica por webhook a un receptor cuyo log sirve de evidencia. Todo corre con Docker Compose en una VM de Azure (Debian 12, tamaño B2as_v2: 2 vCPU y 8 GiB, región North Central US, suscripción Azure for Students)."),
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 100 }, children: [new ImageRun({ data: diagram, type: "png", transformation: { width: Math.round(dW), height: Math.round(dH) } })] }),

      h1("2. Protocolo elegido (MQTT) y TSDB (InfluxDB)"),
      bullet("Coherencia con el Lab 4: la comparación MQTT · AMQP · HTTP recomendó MQTT para la capa de dispositivo (bajo overhead, soporte nativo en ESP32); esta plataforma propia parte de esa capa."),
      bullet("Fiabilidad sin código extra: QoS 1 y sesión persistente en Telegraf evitan perder mensajes si el suscriptor se reinicia."),
      bullet("Telegraf trae consumidor MQTT nativo, así que no hay un puente propio que mantener; Mosquitto es liviano y migra sin cambios a la Raspberry Pi."),
      bullet("Descartados: AMQP (RabbitMQ 0-9-1) añade colas y más memoria sin ventaja para telemetría de un solo sentido; CoAP (UDP, petición/respuesta) exigiría un puente propio hacia la TSDB. Para tres variables cada 10 s MQTT basta."),
      bullet("TSDB: InfluxDB 2.7 (bucket lab5, retención infinita), por su salida nativa en Telegraf, consultas Flux y datasource oficial en Grafana."),
      bullet("DATOS SIMULADOS (no hay sensores): ciclo diario + ruido dentro del rango del escenario, temperature 16–32 °C, humidity 35–90 %, illuminance 0–800 lx, un mensaje cada 10 s."),

      h1("3. Alerta de umbral"),
      kvTable([
        ["Condición", "Máximo de temperature en los últimos 2 min > 35 °C (rango normal del escenario: 16–32 °C)"],
        ["Ventana / evaluación", "Consulta de 2 min, evaluada cada 30 s, estado Pending durante 30 s antes de pasar a Firing"],
        ["Acción", "Webhook a alert-sink (contenedor que imprime la alerta en su log)"],
        ["Cómo se forzó", "publisher.py force --temperature 45 --seconds 150 (el publicador en ejecución sostiene 45 °C)"],
      ]),
      p("Prueba del 18 de octubre de 2026: se forzaron 45 °C desde el publicador. La regla pasó de Normal a Pending y a Firing (inicio 02:11:40 UTC); el webhook llegó a las 02:11:50 UTC con values B=45 y la regla se resolvió a las 02:15:50 UTC con 23,38 °C. Ese pico de 45 °C queda visible en la serie de temperatura de ese día. Evidencias: 05b_alerta_pending.png, 05_alerta_firing.png, 06_alert_sink_log.png y 06_alert_sink_log.txt."),

      h1("4. Dashboard en Grafana (instalado y consultado aparte)"),
      p("Grafana OSS corre en su propio contenedor (http://localhost:3000), con datasource InfluxDB y dashboard provisionados por archivo; solo lee la TSDB, nunca el broker. Título: \"Lab 5 — Monitoreo ambiental (4 días)\", rango now-4d → now. Línea del operador (visible en el panel): verificar que temperatura, humedad e iluminancia estén dentro del rango del escenario, que lleguen ~360 mensajes por hora y que no haya alertas en rojo."),
      bullet("Una serie temporal por variable sobre 4 días (°C, %, lx) y una serie de mensajes por hora, cuyas barras bajas marcan los huecos."),
      bullet("Tres stats con unidad y rango del escenario: temperatura 0–50 °C, humedad 0–100 %, iluminancia 0–1000 lx; además, el estado de las alertas."),
      p("Se verificó que el datasource consulta InfluxDB (03_consulta_influx.png: puntos con device_id y hora real del publicador) y que los 9 paneles cargan (04_preview_dashboard_dia1.png)."),
      p("Capturas con el rango \"Last 4 days\" (04_dashboard_4dias_arriba.png y 04b_dashboard_4dias_abajo.png): se ven cuatro ciclos diarios completos de temperatura, humedad e iluminancia y la serie de mensajes por hora estable en unos 360, sin barras ausentes; las barras de los extremos corresponden a las horas parciales de inicio y de captura."),

      h1("5. Ventana de 4 días"),
      kvTable([
        ["Inicio", "2026-10-17 21:20:35 UTC (primer punto en InfluxDB; evidencias/inicio_toma.txt anotó 21:22:11 UTC, unos minutos después de arrancar el stack)"],
        ["Fin", "2026-10-21 21:27:05 UTC (último punto; 4 días, 0 h, 6 min y 30 s después del primero)"],
        ["Esperado", "34.600 puntos por variable (un mensaje cada 10 s durante 345.990 s); 34.560 si se cuentan exactamente 96 h"],
        ["Obtenido", "34.600 puntos de temperature (evidencias/07_resumen_ventana.txt)"],
        ["Huecos", "Ninguno. Las únicas horas con menos de 300 mensajes son las parciales de los extremos (237 y 163). La VM no se reinició durante la toma y los contenedores se mantuvieron activos."],
      ]),

      h1("6. Qué falló al instalar"),
      bullet("VM del curso (57.156.57.11): el DNS resolvía, pero los puertos 22, 80, 443 y 3000 no respondían desde nuestra red (prueba TCP del 7 de octubre de 2026). No pudimos usarla."),
      bullet("La cuenta institucional no tenía una suscripción de Azure: se activó Azure for Students y se creó una VM propia."),
      bullet("La VM se creó con un tamaño de 1 GiB de memoria (B2ats_v2), insuficiente para InfluxDB, Grafana y Telegraf a la vez; se cambió a B2as_v2 (8 GiB) con la máquina desasignada."),
      bullet("El acceso SSH solo admite clave (Permission denied (publickey)) hasta pasar el archivo .pem con -i; en Windows hubo que ejecutar scp y ssh desde PowerShell, no dentro de la VM."),
      bullet("Grafana arrancó sin datasource, alertas ni dashboards: los logs mostraban permission denied al leer /etc/grafana/provisioning. Causa: scp desde Windows dejó las carpetas privadas para el usuario de la VM y Grafana corre con otro usuario. Solución: chmod -R a+rX sobre grafana/ y reiniciar el contenedor. El mismo error causaba \"Failed to load home dashboard\"."),
      bullet("Plan B preparado y no necesario: scripts de PowerShell para Docker Desktop en Windows (el disco tenía solo 7,6 GB libres)."),

      h1("7. Entregables"),
      p("Repositorio en GitHub (https://github.com/SantiagoJacome14/lab5-plataforma-iot): docker-compose.yml, publisher/, telegraf/, grafana/ (datasource, dashboard y alerta provisionados), README (cómo levantar el stack en una VM Linux o con Docker Desktop, sin secretos; .env.example), scripts/ (resumen_ventana.sh para Linux; iniciar, forzar_alerta y resumen_ventana en PowerShell para Windows) y /evidencias (01 compose ps, 02 mosquitto_sub, 03 consulta a InfluxDB, 04 dashboard, 05 alerta Pending/Firing, 06 log del webhook, 07 resumen de la ventana e inicio_toma.txt). La clave SSH y el .env no se entregan."),
    ],
  }],
});

Packer.toBuffer(doc).then((b) => { fs.writeFileSync(path.join(__dirname, "Laboratorio 5 - Informe.docx"), b); console.log("done"); });

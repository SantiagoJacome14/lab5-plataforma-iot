"""Genera grafana/dashboards/lab5-ambiental.json (el JSON se versiona; este script es la fuente).
Uso:  python scripts/build_dashboard.py
"""
import json
import pathlib

DS = {"type": "influxdb", "uid": "influxdb-lab5"}


def flux(field: str, tail: str) -> str:
    return (
        'from(bucket: "lab5")\n'
        "  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)\n"
        f'  |> filter(fn: (r) => r._measurement == "ambiental" and r._field == "{field}")\n'
        f"  {tail}"
    )


def target(query: str) -> dict:
    return {"refId": "A", "datasource": DS, "query": query}


def thresholds(*steps) -> dict:
    return {"mode": "absolute", "steps": [{"color": c, "value": v} for c, v in steps]}


def stat(pid, title, field, unit, lo, hi, steps, x, y, w=6, h=5):
    return {
        "id": pid, "type": "stat", "title": title, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [target(flux(field, "|> last()"))],
        "options": {
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "colorMode": "value", "graphMode": "area", "textMode": "auto",
        },
        "fieldConfig": {"defaults": {
            "unit": unit, "min": lo, "max": hi, "decimals": 1,
            "thresholds": thresholds(*steps),
        }, "overrides": []},
    }


def series(pid, title, field, unit, x, y, w=12, h=8, color="blue"):
    return {
        "id": pid, "type": "timeseries", "title": title, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [target(flux(field, "|> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: true)"))],
        "options": {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "single"}},
        "fieldConfig": {"defaults": {
            "unit": unit, "color": {"mode": "fixed", "fixedColor": color},
            "custom": {"drawStyle": "line", "lineWidth": 1, "fillOpacity": 12, "spanNulls": False, "showPoints": "never"},
        }, "overrides": []},
    }


panels = [
    {
        "id": 1, "type": "text", "title": "", "transparent": True,
        "gridPos": {"x": 0, "y": 0, "w": 24, "h": 3},
        "options": {"mode": "markdown", "content": (
            "# Lab 5 — Monitoreo ambiental UNAB (toma de 4 días)\n"
            "**Qué mira el operador:** que temperatura, humedad e iluminancia se mantengan dentro del rango del escenario "
            "(16–32 °C, 35–90 %, 0–800 lx), que lleguen ~360 mensajes por hora (barras abajo a la derecha: una barra baja o "
            "ausente = hueco en la toma) y que no haya alertas en rojo."
        )},
    },
    stat(2, "Temperatura (último valor)", "temperature", "celsius", 0, 50,
         [("green", None), ("orange", 32), ("red", 35)], 0, 3),
    stat(3, "Humedad relativa (último valor)", "humidity", "percent", 0, 100,
         [("blue", None), ("green", 35), ("orange", 90)], 6, 3),
    stat(4, "Iluminancia (último valor)", "illuminance", "lux", 0, 1000,
         [("dark-blue", None), ("green", 100), ("orange", 800)], 12, 3),
    {
        "id": 5, "type": "alertlist", "title": "Estado de las alertas",
        "gridPos": {"x": 18, "y": 3, "w": 6, "h": 5},
        "options": {
            "viewMode": "list", "groupMode": "default", "maxItems": 10, "sortOrder": 1,
            "dashboardAlerts": False, "alertName": "", "showInstances": False,
            "alertInstanceLabelFilter": "",
            "stateFilter": {"firing": True, "pending": True, "noData": False, "normal": True, "error": True},
        },
    },
    series(6, "Temperatura (°C) — 4 días", "temperature", "celsius", 0, 8, color="red"),
    series(7, "Humedad relativa (%) — 4 días", "humidity", "percent", 12, 8, color="blue"),
    series(8, "Iluminancia (lx) — 4 días", "illuminance", "lux", 0, 16, color="yellow"),
    {
        "id": 9, "type": "timeseries", "title": "Mensajes recibidos por hora (huecos de la toma)", "datasource": DS,
        "gridPos": {"x": 12, "y": 16, "w": 12, "h": 8},
        "targets": [target(flux("temperature", "|> aggregateWindow(every: 1h, fn: count, createEmpty: true)\n  |> fill(value: 0)"))],
        "options": {"legend": {"displayMode": "hidden"}, "tooltip": {"mode": "single"}},
        "fieldConfig": {"defaults": {
            "unit": "none", "min": 0, "color": {"mode": "fixed", "fixedColor": "green"},
            "custom": {"drawStyle": "bars", "fillOpacity": 70, "lineWidth": 1, "spanNulls": False},
        }, "overrides": []},
    },
]

dashboard = {
    "uid": "lab5-ambiental",
    "title": "Lab 5 — Monitoreo ambiental (4 días)",
    "description": "MQTT -> Telegraf -> InfluxDB -> Grafana. Toma simulada de 4 días.",
    "tags": ["lab5", "unab", "iot"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 1,
    "editable": True,
    "refresh": "1m",
    "time": {"from": "now-4d", "to": "now"},
    "panels": panels,
}

out = pathlib.Path(__file__).resolve().parent.parent / "grafana" / "dashboards" / "lab5-ambiental.json"
out.write_text(json.dumps(dashboard, indent=2, ensure_ascii=False), encoding="utf-8")
print(f"escrito {out} ({len(panels)} paneles)")

"""Publicador MQTT del Lab 5: temperature, humidity, illuminance.

  python publisher.py run                       # publica en bucle (modo servicio)
  python publisher.py force --temperature 45 --seconds 150
                                                # ordena al publicador en ejecucion
                                                # sostener ese valor (para disparar la alerta)

Los datos son SIMULADOS (ciclo diario + ruido). Eso se declara en el informe.
"""
import argparse
import json
import math
import os
import random
import sys
import time

import paho.mqtt.client as mqtt

HOST = os.environ.get("MQTT_HOST", "localhost")
PORT = int(os.environ.get("MQTT_PORT", "1883"))
DEVICE_ID = os.environ.get("DEVICE_ID", "vm-pub-01")
INTERVAL = float(os.environ.get("PUBLISH_INTERVAL", "10"))
TZ_OFFSET_H = -5  # Colombia (UTC-5), solo para el ciclo dia/noche del modelo

TOPIC_TELEMETRY = f"lab5/{DEVICE_ID}/telemetry"
TOPIC_CONTROL = f"lab5/{DEVICE_ID}/control"


def local_hour(now: float) -> float:
    return ((now + TZ_OFFSET_H * 3600) % 86400) / 3600


def clamp(x: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, x))


class Model:
    """Ciclo diario suave + deriva lenta + ruido. Rangos del escenario:
    temperature 16-32 C, humidity 35-90 %, illuminance 0-800 lx."""

    def __init__(self, rng: random.Random | None = None):
        self.rng = rng or random.Random()
        self.drift_t = 0.0
        self.drift_h = 0.0
        self.cloud = 1.0

    def sample(self, now: float) -> dict:
        h = local_hour(now)
        phase = math.sin(2 * math.pi * (h - 9) / 24)  # pico a las 15:00

        self.drift_t = clamp(self.drift_t + self.rng.gauss(0, 0.05), -1.5, 1.5)
        self.drift_h = clamp(self.drift_h + self.rng.gauss(0, 0.15), -4, 4)
        self.cloud = clamp(self.cloud + self.rng.gauss(0, 0.04), 0.5, 1.0)

        temperature = 24 + 5 * phase + self.drift_t + self.rng.gauss(0, 0.15)
        humidity = 62 - 14 * phase + self.drift_h + self.rng.gauss(0, 0.5)
        if 6 <= h <= 18:
            illuminance = 780 * math.sin(math.pi * (h - 6) / 12) * self.cloud
        else:
            illuminance = 8 + abs(self.rng.gauss(0, 3))
        illuminance += self.rng.gauss(0, 5)

        return {
            "temperature": round(clamp(temperature, 16, 32), 2),
            "humidity": round(clamp(humidity, 35, 90), 2),
            "illuminance": round(clamp(illuminance, 0, 800), 1),
        }


def build_payload(values: dict, now: float, override: dict | None = None) -> dict:
    values = dict(values)
    if override and now < override["until"]:
        values["temperature"] = override["temperature"]
    return {"device_id": DEVICE_ID, **values, "ts": int(now * 1000)}


def new_client(client_id: str) -> mqtt.Client:
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=client_id)
    client.reconnect_delay_set(min_delay=1, max_delay=30)
    return client


def run() -> None:
    model = Model()
    state = {"override": None}

    client = new_client(f"publisher-{DEVICE_ID}")

    def on_connect(c, userdata, flags, reason_code, properties):
        print(f"[mqtt] conectado a {HOST}:{PORT} ({reason_code})", flush=True)
        c.subscribe(TOPIC_CONTROL, qos=1)

    def on_disconnect(c, userdata, flags, reason_code, properties):
        print(f"[mqtt] desconectado ({reason_code}); paho reintenta solo", flush=True)

    def on_message(c, userdata, msg):
        try:
            cmd = json.loads(msg.payload)
            seconds = float(cmd["seconds"])
            state["override"] = {"temperature": float(cmd["temperature"]), "until": time.time() + seconds}
            print(f"[control] temperature forzada a {cmd['temperature']} por {seconds:.0f}s", flush=True)
        except (ValueError, KeyError, TypeError) as exc:
            print(f"[control] comando ignorado ({exc}): {msg.payload!r}", flush=True)

    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message

    # El broker puede tardar en arrancar: reintenta hasta conectar.
    while True:
        try:
            client.connect(HOST, PORT, keepalive=30)
            break
        except OSError as exc:
            print(f"[mqtt] broker no disponible ({exc}); reintento en 3 s", flush=True)
            time.sleep(3)
    client.loop_start()

    next_tick = time.time()
    while True:
        now = time.time()
        payload = build_payload(model.sample(now), now, state["override"])
        info = client.publish(TOPIC_TELEMETRY, json.dumps(payload), qos=1)
        print(f"[pub] {TOPIC_TELEMETRY} {payload} rc={info.rc}", flush=True)
        next_tick += INTERVAL
        time.sleep(max(0.0, next_tick - time.time()))


def force(temperature: float, seconds: float) -> None:
    client = new_client(f"force-{DEVICE_ID}-{int(time.time())}")
    client.connect(HOST, PORT, keepalive=10)
    client.loop_start()
    msg = json.dumps({"temperature": temperature, "seconds": seconds})
    info = client.publish(TOPIC_CONTROL, msg, qos=1)
    info.wait_for_publish(timeout=10)
    client.loop_stop()
    client.disconnect()
    print(f"[force] enviado a {TOPIC_CONTROL}: {msg}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd")
    sub.add_parser("run")
    f = sub.add_parser("force")
    f.add_argument("--temperature", type=float, default=45.0)
    f.add_argument("--seconds", type=float, default=150.0)
    args = parser.parse_args()

    if args.cmd in (None, "run"):
        run()
    elif args.cmd == "force":
        force(args.temperature, args.seconds)
    return 0


if __name__ == "__main__":
    sys.exit(main())

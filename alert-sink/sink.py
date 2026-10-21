"""Receptor de webhooks de Grafana: imprime cada alerta en el log del contenedor.
La evidencia del disparo es:  docker compose logs alert-sink
"""
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        stamp = time.strftime("%Y-%m-%d %H:%M:%S")
        try:
            data = json.loads(body)
            print(f"\n=== [{stamp}] webhook de Grafana: status={data.get('status')} "
                  f"receiver={data.get('receiver')}", flush=True)
            for alert in data.get("alerts", []):
                labels = alert.get("labels", {})
                values = alert.get("values")
                print(f"  - {alert.get('status', '?').upper():9} {labels.get('alertname')} "
                      f"| severity={labels.get('severity')} | values={values} "
                      f"| desde={alert.get('startsAt')}", flush=True)
        except ValueError:
            print(f"[{stamp}] cuerpo no-JSON: {body[:300]!r}", flush=True)
        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print("alert-sink escuchando en :8080", flush=True)
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()

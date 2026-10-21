from PIL import Image, ImageDraw, ImageFont

W, H = 2000, 560
BG, BOX, TEXT, SUB = (13, 17, 23), (30, 41, 59), (241, 245, 249), (148, 163, 184)
GOLD, CYAN, GREEN, PURPLE, RED = (250, 204, 21), (56, 189, 248), (34, 197, 94), (168, 85, 247), (239, 68, 68)

img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)


def font(size, bold=False):
    try:
        return ImageFont.truetype("segoeuib.ttf" if bold else "segoeui.ttf", size)
    except Exception:
        return ImageFont.load_default()


f_title, f_name, f_sub, f_lbl = font(34, True), font(24, True), font(16), font(15, True)
d.text((W / 2, 40), "Lab 5 — MQTT → InfluxDB → Grafana (Docker Compose)", font=f_title, fill=TEXT, anchor="mm")

boxes = [
    ("Publicador", "Python + paho-mqtt\n3 variables simuladas", CYAN),
    ("Mosquitto", "Broker MQTT :1883\ntopic lab5/<id>/telemetry", GOLD),
    ("Telegraf", "Suscriptor QoS 1\nJSON → line protocol", GOLD),
    ("InfluxDB 2.7", "TSDB · bucket lab5\nhistorial de 4 días", GREEN),
    ("Grafana OSS", "Dashboard 4 días\n+ regla de alerta", PURPLE),
    ("alert-sink", "Receptor del webhook\n(log = evidencia)", RED),
]
bw, bh, y0 = 270, 190, 190
gap = (W - 2 * 50 - len(boxes) * bw) / (len(boxes) - 1)
xs = []
for i, (name, sub, color) in enumerate(boxes):
    x0 = 50 + i * (bw + gap)
    xs.append(x0)
    d.rounded_rectangle([x0, y0, x0 + bw, y0 + bh], radius=14, fill=BOX, outline=color, width=4)
    d.text((x0 + bw / 2, y0 + 45), name, font=f_name, fill=TEXT, anchor="mm")
    for k, line in enumerate(sub.split("\n")):
        d.text((x0 + bw / 2, y0 + 100 + k * 26), line, font=f_sub, fill=SUB, anchor="mm")


def arrow(x_from, x_to, y, label, color=GOLD, reverse=False):
    d.line([x_from, y, x_to, y], fill=color, width=4)
    tip, tail = (x_from, x_to) if reverse else (x_to, x_from)
    sgn = 1 if tip > tail else -1
    d.polygon([(tip, y), (tip - sgn * 18, y - 9), (tip - sgn * 18, y + 9)], fill=color)
    d.text(((x_from + x_to) / 2, y0 - 22), label, font=f_lbl, fill=color, anchor="mm")


mid = y0 + bh / 2
arrow(xs[0] + bw, xs[1], mid, "MQTT QoS 1")
arrow(xs[1] + bw, xs[2], mid, "suscribe")
arrow(xs[2] + bw, xs[3], mid, "escribe (ts real)")
arrow(xs[3] + bw, xs[4], mid, "Flux · solo lectura", color=PURPLE, reverse=True)
arrow(xs[4] + bw, xs[5], mid, "webhook", color=RED)

d.rounded_rectangle([xs[4], 430, xs[4] + bw, 500], radius=10, outline=PURPLE, width=2)
d.text((xs[4] + bw / 2, 455), "Grafana no es ingesta:", font=f_sub, fill=TEXT, anchor="mm")
d.text((xs[4] + bw / 2, 480), "solo consulta la TSDB", font=f_sub, fill=SUB, anchor="mm")
d.text((50, 520), "Control: el publicador escucha lab5/<id>/control para sostener un valor (disparo de la alerta).", font=f_sub, fill=SUB, anchor="lm")

img.save(r"C:\Users\santi\Downloads\Laboratorio 5\informe\diagrama_lab5.png")
print("ok")

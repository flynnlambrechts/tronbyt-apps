"""
Applet: Air Quality Sensor
Summary: Home air quality readings and warnings
Description: Displays PM2.5, CO2, temperature and humidity from a Sensirion SEN66 sensor on an ESPHome device, with warning frames and suggested actions when a reading crosses an alert threshold.
Author: flynnlambrechts
"""

load("http.star", "http")
load("math.star", "math")
load("render.star", "canvas", "render")
load("schema.star", "schema")

DEFAULT_DEVICE_URL = "http://192.168.0.142"

GREEN = "#0c0"
YELLOW = "#fe0"
ORANGE = "#f80"
RED = "#f00"
DIM = "#999"

# VOC index has a baseline of 100: below it means recent conditions are
# improving, above it means they're worsening.
VOC_BASELINE = 100

def main(config):
    scale = 2 if canvas.is2x() else 1
    device_url = config.str("device_url", DEFAULT_DEVICE_URL)

    fahrenheit = config.bool("fahrenheit", False)
    pm25_threshold = float(config.get("pm25_threshold") or "25")
    co2_threshold = float(config.get("co2_threshold") or "1200")
    co2_urgent_threshold = float(config.get("co2_urgent_threshold") or "2000")
    humidity_high = float(config.get("humidity_high") or "70")
    voc_threshold = float(config.get("voc_threshold") or "150")

    pm25 = fetch_value(device_url, "PM2.5")
    co2 = fetch_value(device_url, "CO2")
    temp_c = fetch_value(device_url, "Temperature")
    humidity = fetch_value(device_url, "Humidity")
    voc = fetch_value(device_url, "VOC Index")

    if pm25 == None and co2 == None and temp_c == None and humidity == None and voc == None:
        return []

    dashboard = dashboard_frame(
        pm25,
        co2,
        temp_c,
        humidity,
        voc,
        fahrenheit,
        pm25_threshold,
        co2_threshold,
        co2_urgent_threshold,
        humidity_high,
        scale,
    )
    warnings = build_warnings(
        pm25,
        co2,
        humidity,
        voc,
        pm25_threshold,
        co2_threshold,
        co2_urgent_threshold,
        humidity_high,
        voc_threshold,
    )
    frames = [dashboard] + [warning_frame(w, scale) for w in warnings]

    return render.Root(
        delay = 3000,
        show_full_animation = True,
        child = render.Animation(children = frames),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "device_url",
                name = "Device URL",
                desc = "Base URL of the ESPHome sensor's web server (enable the web_server component), e.g. http://air-quality.local",
                icon = "link",
                default = DEFAULT_DEVICE_URL,
            ),
            schema.Toggle(
                id = "fahrenheit",
                name = "Fahrenheit",
                desc = "Display temperature in Fahrenheit instead of Celsius.",
                icon = "temperatureHalf",
                default = False,
            ),
            schema.Text(
                id = "pm25_threshold",
                name = "PM2.5 Warning Threshold (µg/m³)",
                desc = "Show a warning when PM2.5 rises above this level.",
                icon = "triangleExclamation",
                default = "25",
            ),
            schema.Text(
                id = "co2_threshold",
                name = "CO2 Warning Threshold (ppm)",
                desc = "Show a warning when CO2 rises above this level.",
                icon = "triangleExclamation",
                default = "1200",
            ),
            schema.Text(
                id = "co2_urgent_threshold",
                name = "CO2 Urgent Threshold (ppm)",
                desc = "Show an urgent warning when CO2 rises above this level.",
                icon = "triangleExclamation",
                default = "2000",
            ),
            schema.Text(
                id = "humidity_high",
                name = "Humidity Warning Threshold (%)",
                desc = "Show a warning when humidity rises above this level.",
                icon = "triangleExclamation",
                default = "70",
            ),
            schema.Text(
                id = "voc_threshold",
                name = "VOC Index Warning Threshold",
                desc = "Show a warning when the VOC index rises above this level.",
                icon = "triangleExclamation",
                default = "150",
            ),
        ],
    )

def fetch_value(base_url, sensor_name):
    url = base_url + "/sensor/" + sensor_name.replace(" ", "%20")
    resp = http.get(url, ttl_seconds = 55)
    if resp.status_code != 200:
        return None
    return resp.json().get("value")

def dashboard_frame(pm25, co2, temp_c, humidity, voc, fahrenheit, pm25_threshold, co2_threshold, co2_urgent_threshold, humidity_high, scale):
    width = canvas.width()
    small_font = "CG-pixel-3x5-mono" if scale == 1 else "terminus-12"
    big_font = "tb-8" if scale == 1 else "terminus-16"

    quality_label, quality_color = quality_for_pm25(pm25, pm25_threshold)
    pm25_label = "PM " + fmt0(pm25) if pm25 != None else "PM --"
    trend_arrow = voc_trend(voc)
    co2_label = "CO2 " + fmt0(co2) if co2 != None else "CO2 --"
    co2_color = co2_color_for(co2, co2_threshold, co2_urgent_threshold)
    temp_label = format_temp(temp_c, fahrenheit)
    humidity_label = fmt0(humidity) + "%" if humidity != None else "--%"
    humidity_color = RED if (humidity != None and humidity > humidity_high) else GREEN

    quality_children = [render.Text(content = quality_label, font = big_font, color = text_color_for(quality_color))]
    if trend_arrow != None:
        quality_children.append(render.Padding(pad = (2, 0, 0, 0), child = render.Text(content = trend_arrow, font = big_font, color = text_color_for(quality_color))))

    quality_row = render.Box(
        width = width,
        height = 11 * scale,
        color = quality_color,
        child = render.Row(
            expanded = True,
            main_align = "space_between",
            cross_align = "center",
            children = [
                render.Padding(pad = (2, 0, 0, 0), child = render.Row(children = quality_children)),
                render.Padding(pad = (0, 0, 2, 0), child = render.Text(content = pm25_label, font = small_font, color = text_color_for(quality_color))),
            ],
        ),
    )

    co2_row = render.Row(
        expanded = True,
        main_align = "center",
        children = [render.Text(content = co2_label, font = big_font, color = co2_color)],
    )

    bottom_row = render.Row(
        expanded = True,
        main_align = "space_around",
        children = [
            render.Text(content = temp_label, font = big_font, color = DIM),
            render.Text(content = humidity_label, font = big_font, color = humidity_color),
        ],
    )

    return render.Column(
        expanded = True,
        main_align = "space_between",
        children = [quality_row, co2_row, bottom_row],
    )

def voc_trend(voc):
    if voc == None:
        return None
    if voc < VOC_BASELINE:
        return "↑"
    if voc > VOC_BASELINE:
        return "↓"
    return "→"

def build_warnings(pm25, co2, humidity, voc, pm25_threshold, co2_threshold, co2_urgent_threshold, humidity_high, voc_threshold):
    warnings = []

    if pm25 != None and pm25 > pm25_threshold:
        warnings.append(dict(
            title = "PM2.5 HIGH",
            action = fmt0(pm25) + " - EXTRACTION FAN, OR SHUT WINDOWS IF OUTDOOR SOURCE",
            color = RED,
        ))

    if co2 != None and co2 > co2_urgent_threshold:
        warnings.append(dict(
            title = "CO2 URGENT",
            action = fmt0(co2) + " PPM - VENTILATE FULLY, NOT JUST THE LATCH",
            color = RED,
        ))
    elif co2 != None and co2 > co2_threshold:
        warnings.append(dict(
            title = "CO2 HIGH",
            action = fmt0(co2) + " PPM - OPEN A WINDOW ~10 MIN",
            color = ORANGE,
        ))

    if humidity != None and humidity > humidity_high:
        warnings.append(dict(
            title = "HUMIDITY HIGH",
            action = fmt0(humidity) + "% - DRY MODE OR DEHUMIDIFIER",
            color = RED,
        ))

    if voc != None and voc > voc_threshold:
        warnings.append(dict(
            title = "VOC HIGH",
            action = fmt0(voc) + " - VENTILATE, HUNT THE SOURCE",
            color = RED,
        ))

    return warnings

def warning_frame(warning, scale):
    width = canvas.width()
    height = 32 * scale
    small_font = "CG-pixel-3x5-mono" if scale == 1 else "terminus-12"
    big_font = "tb-8" if scale == 1 else "terminus-16"
    text_color = text_color_for(warning["color"])

    return render.Box(
        width = width,
        height = height,
        color = warning["color"],
        child = render.Column(
            expanded = True,
            main_align = "center",
            cross_align = "center",
            children = [
                render.Text(content = warning["title"], font = big_font, color = text_color),
                render.WrappedText(
                    content = warning["action"],
                    font = small_font,
                    color = text_color,
                    align = "center",
                    width = width - 4 * scale,
                    linespacing = 1,
                    wordbreak = True,
                ),
            ],
        ),
    )

def quality_for_pm25(pm25, pm25_threshold):
    if pm25 == None:
        return "N/A", DIM
    if pm25 > pm25_threshold:
        return "POOR", RED
    return "GOOD", GREEN

def co2_color_for(co2, co2_threshold, co2_urgent_threshold):
    if co2 == None:
        return DIM
    if co2 > co2_urgent_threshold:
        return RED
    if co2 > co2_threshold:
        return ORANGE
    return GREEN

def text_color_for(color):
    return "#000" if color == YELLOW else "#fff"

def format_temp(temp_c, fahrenheit):
    if temp_c == None:
        return "--"
    if fahrenheit:
        return fmt0(temp_c * 9.0 / 5.0 + 32.0) + "F"
    return fmt0(temp_c) + "C"

def fmt0(value):
    return "%d" % int(math.round(value))

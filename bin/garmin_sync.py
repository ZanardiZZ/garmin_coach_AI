#!/usr/bin/env python3
import os
import sys
import logging
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from influxdb import InfluxDBClient
from garminconnect import (
    Garmin,
    GarminConnectAuthenticationError,
    GarminConnectConnectionError,
    GarminConnectTooManyRequestsError,
)
from garth.exc import GarthHTTPError
from fitparse import FitFile, FitParseError
import io
import zipfile


LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="%(asctime)s - %(levelname)s - %(message)s",
)

INFLUX_HOST = os.getenv("INFLUX_HOST", "")
INFLUX_URL = os.getenv("INFLUX_URL", "")
INFLUX_DB = os.getenv("INFLUX_DB", "GarminStats")
INFLUX_USER = os.getenv("INFLUX_USER", "")
INFLUX_PASS = os.getenv("INFLUX_PASS", "")

GARMIN_EMAIL = os.getenv("GARMINCONNECT_EMAIL", "")
GARMIN_PASS = os.getenv("GARMINCONNECT_PASSWORD", "")
GARMIN_IS_CN = os.getenv("GARMINCONNECT_IS_CN", "false").lower() in ("1", "true", "yes", "y")
TOKEN_DIR = os.path.expanduser(os.getenv("GARMIN_TOKEN_DIR", "~/.ultra-coach/garminconnect"))
SYNC_DAYS = int(os.getenv("GARMIN_SYNC_DAYS", "7"))
if SYNC_DAYS < 1:
    SYNC_DAYS = 1
if SYNC_DAYS > 180:
    SYNC_DAYS = 180
USER_TZ = os.getenv("USER_TZ", "UTC")
FETCH_ACTIVITY_DETAILS = os.getenv("GARMIN_FETCH_ACTIVITY_DETAILS", "true").lower() in (
    "1",
    "true",
    "yes",
    "y",
)
WRITE_CHUNK = int(os.getenv("GARMIN_WRITE_CHUNK", "10000"))


def parse_influx_host(url: str) -> str:
    if not url:
        return ""
    return url.replace("http://", "").replace("https://", "").split("/")[0].split(":")[0]


def influx_client():
    host = INFLUX_HOST or parse_influx_host(INFLUX_URL)
    if not host:
        raise RuntimeError("INFLUX_URL ou INFLUX_HOST nao configurado.")
    return InfluxDBClient(host=host, port=8086, username=INFLUX_USER, password=INFLUX_PASS, database=INFLUX_DB)


def garmin_login():
    try:
        garmin = Garmin()
        garmin.login(TOKEN_DIR)
        logging.info("Login Garmin via token OK.")
        return garmin
    except (FileNotFoundError, GarthHTTPError, GarminConnectAuthenticationError):
        if not GARMIN_EMAIL or not GARMIN_PASS:
            raise RuntimeError("Credenciais Garmin ausentes (GARMINCONNECT_EMAIL/PASSWORD).")
        logging.info("Login Garmin com usuario/senha.")
        garmin = Garmin(email=GARMIN_EMAIL, password=GARMIN_PASS, is_cn=GARMIN_IS_CN, return_on_mfa=True)
        result1, result2 = garmin.login()
        if result1 == "needs_mfa":
            raise RuntimeError("MFA requerido. Execute login manual e gere tokens.")
        garmin.garth.dump(TOKEN_DIR)
        garmin.login(TOKEN_DIR)
        logging.info("Token salvo em %s", TOKEN_DIR)
        return garmin


def date_range(days: int):
    try:
        tz = ZoneInfo(USER_TZ)
    except Exception:
        tz = timezone.utc
    today = datetime.now(tz).date()
    start = today - timedelta(days=days)
    for n in range(days + 1):
        yield (start + timedelta(days=n)).strftime("%Y-%m-%d")


def build_body_points(garmin, date_str: str):
    points = []
    daily = garmin.get_weigh_ins(date_str, date_str).get("dailyWeightSummaries", [])
    if not daily:
        return points
    all_metrics = daily[0].get("allWeightMetrics", [])
    for w in all_metrics:
        fields = {
            "weight": w.get("weight"),
            "bmi": w.get("bmi"),
            "bodyFat": w.get("bodyFat"),
            "bodyWater": w.get("bodyWater"),
            "boneMass": w.get("boneMass"),
            "muscleMass": w.get("muscleMass"),
        }
        if all(v is None for v in fields.values()):
            continue
        ts = w.get("timestampGMT")
        if ts:
            dt = datetime.fromtimestamp(ts / 1000, tz=timezone.utc)
        else:
            dt = datetime.strptime(date_str, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        points.append(
            {
                "measurement": "BodyComposition",
                "time": dt.isoformat(),
                "tags": {
                    "SourceType": w.get("sourceType", "Unknown"),
                },
                "fields": fields,
            }
        )
    return points


def build_activity_points(activities):
    points = []
    for a in activities:
        if "startTimeGMT" not in a:
            continue
        dt = datetime.strptime(a["startTimeGMT"], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        points.append(
            {
                "measurement": "ActivitySummary",
                "time": dt.isoformat(),
                "tags": {
                    "ActivityID": a.get("activityId"),
                },
                "fields": {
                    "Activity_ID": a.get("activityId"),
                    "activityName": a.get("activityName"),
                    "activityType": (a.get("activityType") or {}).get("typeKey"),
                    "distance": a.get("distance"),
                    "elapsedDuration": a.get("elapsedDuration"),
                    "movingDuration": a.get("movingDuration"),
                    "averageSpeed": a.get("averageSpeed"),
                    "maxSpeed": a.get("maxSpeed"),
                    "calories": a.get("calories"),
                    "bmrCalories": a.get("bmrCalories"),
                    "averageHR": a.get("averageHR"),
                    "maxHR": a.get("maxHR"),
                    "hrTimeInZone_1": a.get("hrTimeInZone_1"),
                    "hrTimeInZone_2": a.get("hrTimeInZone_2"),
                    "hrTimeInZone_3": a.get("hrTimeInZone_3"),
                    "hrTimeInZone_4": a.get("hrTimeInZone_4"),
                    "hrTimeInZone_5": a.get("hrTimeInZone_5"),
                },
            }
        )
    return points


def build_activity_detail_points(garmin, activity):
    points = []
    activity_id = activity.get("activityId")
    activity_type = (activity.get("activityType") or {}).get("typeKey", "Unknown")
    if not activity_id:
        return points
    try:
        zip_data = garmin.download_activity(activity_id, dl_fmt=garmin.ActivityDownloadFormat.ORIGINAL)
    except Exception as exc:
        logging.warning("Falha ao baixar FIT activity_id=%s: %s", activity_id, str(exc))
        return points

    try:
        zip_buffer = io.BytesIO(zip_data)
        with zipfile.ZipFile(zip_buffer) as zip_ref:
            fit_name = next((f for f in zip_ref.namelist() if f.endswith(".fit")), None)
            if not fit_name:
                logging.warning("FIT nao encontrado activity_id=%s", activity_id)
                return points
            fit_data = zip_ref.read(fit_name)
    except Exception as exc:
        logging.warning("Falha ao ler ZIP FIT activity_id=%s: %s", activity_id, str(exc))
        return points

    try:
        fit_file = FitFile(io.BytesIO(fit_data))
        fit_file.parse()
    except FitParseError as exc:
        logging.warning("Falha ao parsear FIT activity_id=%s: %s", activity_id, str(exc))
        return points

    for record in fit_file.get_messages("record"):
        vals = record.get_values()
        ts = vals.get("timestamp")
        if not ts:
            continue
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        else:
            ts = ts.astimezone(timezone.utc)

        lat_raw = vals.get("position_lat")
        lon_raw = vals.get("position_long")
        lat = (int(lat_raw) * (180 / 2**31)) if lat_raw is not None else None
        lon = (int(lon_raw) * (180 / 2**31)) if lon_raw is not None else None
        hr = vals.get("heart_rate")
        speed = vals.get("enhanced_speed") or vals.get("speed")
        dist = vals.get("distance")
        alt = vals.get("enhanced_altitude") or vals.get("altitude")
        cadence = vals.get("cadence")
        stride_length = vals.get("stride_length") or vals.get("step_length")
        vertical_oscillation = vals.get("vertical_oscillation")
        vertical_ratio = vals.get("vertical_ratio")
        stance_time = vals.get("stance_time")
        ground_contact_time = vals.get("ground_contact_time")
        ground_contact_balance = vals.get("ground_contact_balance")
        temperature = vals.get("temperature")
        power = vals.get("power") or vals.get("enhanced_power")
        stamina = vals.get("stamina")
        potential_stamina = vals.get("potential_stamina")

        points.append(
            {
                "measurement": "ActivityGPS",
                "time": ts.isoformat(),
                "tags": {
                    "ActivityID": activity_id,
                    "ActivityType": activity_type,
                },
                "fields": {
                    "Latitude": lat,
                    "Longitude": lon,
                    "HeartRate": hr,
                    "Speed": speed,
                    "Distance": dist,
                    "Altitude": alt,
                    "Cadence": cadence,
                    "StrideLength": stride_length,
                    "VerticalOscillation": vertical_oscillation,
                    "VerticalRatio": vertical_ratio,
                    "StanceTime": stance_time,
                    "GroundContactTime": ground_contact_time,
                    "GroundContactBalance": ground_contact_balance,
                    "Temperature": temperature,
                    "Power": power,
                    "Stamina": stamina,
                    "PotentialStamina": potential_stamina,
                },
            }
        )

    logging.info("Detalhes coletados activity_id=%s points=%d", activity_id, len(points))
    return points


def main():
    try:
        client = influx_client()
    except Exception as exc:
        logging.error(str(exc))
        sys.exit(1)

    try:
        garmin = garmin_login()
    except (GarminConnectAuthenticationError, GarminConnectConnectionError, GarminConnectTooManyRequestsError, RuntimeError) as exc:
        logging.error(str(exc))
        sys.exit(2)

    total_points = 0
    dates = list(date_range(SYNC_DAYS))
    start_date = dates[0]
    end_date = dates[-1]

    try:
        activities = garmin.get_activities_by_date(start_date, end_date)
    except Exception as exc:
        logging.error("Falha ao buscar atividades (%s a %s): %s", start_date, end_date, str(exc))
        activities = []

    activity_points = build_activity_points(activities)

    for date_str in dates:
        body_points = build_body_points(garmin, date_str)
        points = body_points
        if not points:
            continue
        for i in range(0, len(points), WRITE_CHUNK):
            client.write_points(points[i : i + WRITE_CHUNK])
        total_points += len(points)
        logging.info("Sincronizado body %s: points=%d", date_str, len(points))

    if activity_points:
        for i in range(0, len(activity_points), WRITE_CHUNK):
            client.write_points(activity_points[i : i + WRITE_CHUNK])
        total_points += len(activity_points)
        logging.info("Sincronizado atividades: points=%d", len(activity_points))

    if FETCH_ACTIVITY_DETAILS and activities:
        detail_total = 0
        for activity in activities:
            detail_points = build_activity_detail_points(garmin, activity)
            if not detail_points:
                continue
            for i in range(0, len(detail_points), WRITE_CHUNK):
                client.write_points(detail_points[i : i + WRITE_CHUNK])
            detail_total += len(detail_points)
        if detail_total:
            total_points += detail_total
            logging.info("Sincronizado ActivityGPS: points=%d", detail_total)

    logging.info("Finalizado. Total points=%d", total_points)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
import os
import sys
import logging
from datetime import datetime, timedelta, timezone

from influxdb import InfluxDBClient
from garminconnect import (
    Garmin,
    GarminConnectAuthenticationError,
    GarminConnectConnectionError,
    GarminConnectTooManyRequestsError,
)
from garth.exc import GarthHTTPError


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
    today = datetime.now(timezone.utc).date()
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


def build_activity_points(garmin, date_str: str):
    points = []
    activities = garmin.get_activities_by_date(date_str, date_str)
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
    for date_str in date_range(SYNC_DAYS):
        body_points = build_body_points(garmin, date_str)
        activity_points = build_activity_points(garmin, date_str)
        points = body_points + activity_points
        if not points:
            continue
        client.write_points(points)
        total_points += len(points)
        logging.info("Sincronizado %s: points=%d", date_str, len(points))

    logging.info("Finalizado. Total points=%d", total_points)


if __name__ == "__main__":
    main()

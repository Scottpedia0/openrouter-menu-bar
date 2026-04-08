#!/usr/bin/env python3
"""Quick posture smoke test helper for OpenRouter Menu Bar.

Writes controlled activity feed snapshots so the menu-bar app transitions through
normal -> warning -> danger states on a short timer.
"""

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
import shutil
import time
from typing import Optional


APP_SUPPORT = Path.home() / "Library" / "Application Support" / "OpenRouterMenuBar"
SETTINGS_PATH = APP_SUPPORT / "settings.json"
FEED_PATH = APP_SUPPORT / "activity-feed.json"
BACKUP_SETTINGS_PATH = APP_SUPPORT / "settings.pre-qa-backup.json"
BACKUP_FEED_PATH = APP_SUPPORT / "activity-feed.pre-qa-backup.json"

DEFAULT_SETTINGS = {
    "openRouterActivityURL": "https://openrouter.ai/activity",
    "hourlyWarningThreshold": 15.0,
    "hourlyHardStopThreshold": 30.0,
    "hourlyBaselineThreshold": 0.01,
    "hourlyWarningPercentOverBaseline": 50.0,
    "hourlyDangerPercentOverBaseline": 300.0,
    "dailyWarningThreshold": 100.0,
    "dailyHardStopThreshold": 180.0,
    "unattendedWarningThreshold": 25.0,
    "unattendedHardStopThreshold": 40.0,
    "unattendedIdleMinutes": 20.0,
    "escalationPercentageAfterWarning": 25.0,
    "hardStopCommand": "",
    "hardStopLockFilePath": "~/Library/Application Support/OpenRouterMenuBar/hard-stop.lock",
    "pollingIntervalSeconds": 300.0,
}


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path, fallback):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return fallback


def write_json(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def snapshot_file(source: Path, backup: Path) -> None:
    backup.parent.mkdir(parents=True, exist_ok=True)
    if source.exists():
        shutil.copy2(source, backup)
    elif backup.exists():
        backup.unlink()


def restore_file(backup: Path, target: Path) -> None:
    if backup.exists():
        shutil.copy2(backup, target)
        backup.unlink()
    elif target.exists():
        target.unlink()


def write_settings(
    baseline: float,
    warning_percent: float,
    danger_percent: float,
    poll_interval: int,
    activity_url: Optional[str] = None,
    activity_url_fallback: Optional[str] = None,
) -> None:
    settings = load_json(SETTINGS_PATH, DEFAULT_SETTINGS.copy())
    if not isinstance(settings, dict):
        settings = DEFAULT_SETTINGS.copy()

    warning_value = baseline * (1 + warning_percent / 100.0)
    danger_value = baseline * (1 + danger_percent / 100.0)

    settings.update(
        {
            "openRouterActivityURL": activity_url or settings.get("openRouterActivityURL", activity_url_fallback or DEFAULT_SETTINGS["openRouterActivityURL"]),
            "hourlyBaselineThreshold": baseline,
            "hourlyWarningPercentOverBaseline": warning_percent,
            "hourlyDangerPercentOverBaseline": danger_percent,
            "hourlyWarningThreshold": warning_value,
            "hourlyHardStopThreshold": danger_value,
            "pollingIntervalSeconds": poll_interval,
        }
    )

    for key, value in DEFAULT_SETTINGS.items():
        if key not in settings:
            settings[key] = value

    write_json(SETTINGS_PATH, settings)


def write_feed(hour: float, day: float, week: float, month: float) -> None:
    ts = now_iso()
    payload = {
        "sourceDescription": "QA canary - synthetic feed",
        "fetchedAt": ts,
        "samples": [
            {"timestamp": ts, "amount": hour},
            {"timestamp": ts, "amount": max(day - hour, 0)},
            {"timestamp": ts, "amount": max(week - day, 0)},
            {"timestamp": ts, "amount": max(month - week, 0)},
        ],
        "directSnapshots": {
            "hour": hour,
            "day": day,
            "week": week,
            "month": month,
        },
    }
    write_json(FEED_PATH, payload)
    print(f"wrote synthetic feed: hour={hour:.4f} day={day:.4f} week={week:.4f} month={month:.4f}")


def wait_seconds(seconds: int, label: str) -> None:
    print(f"waiting {seconds}s for app refresh ({label})")
    time.sleep(seconds)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--baseline",
        type=float,
        default=0.01,
        help="Hourly baseline threshold in USD",
    )
    parser.add_argument(
        "--warning",
        "--warning-percent",
        dest="warning_percent",
        type=float,
        default=50.0,
        help="Hourly warning percent over baseline (alias: --warning). Example: 50 = 1.5x",
    )
    parser.add_argument(
        "--danger",
        "--danger-percent",
        dest="danger_percent",
        type=float,
        default=300.0,
        help="Hourly danger percent over baseline (alias: --danger). Example: 300 = 4x",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=5,
        help="Polling interval seconds used by app",
    )
    parser.add_argument(
        "--step-wait",
        type=int,
        default=8,
        help="Seconds to wait after each posture write",
    )
    parser.add_argument(
        "--danger-hold",
        type=int,
        default=20,
        help="Keep danger state asserted this many seconds before exiting",
    )
    parser.add_argument(
        "--url",
        type=str,
        default=None,
        help="Optional OpenRouter activity URL used in local settings",
    )
    parser.add_argument(
        "--keep-state",
        action="store_true",
        help="Keep QA-written settings and feed instead of restoring the pre-QA state",
    )
    args = parser.parse_args()

    if args.baseline <= 0:
        raise SystemExit("--baseline must be > 0")
    if args.warning_percent <= 0:
        raise SystemExit("--warning must be > 0")
    if args.danger_percent <= args.warning_percent:
        raise SystemExit("--danger must be greater than --warning")
    if args.interval < 5:
        raise SystemExit("--interval must be at least 5")
    if args.step_wait < 3:
        raise SystemExit("--step-wait must be at least 3")
    if args.danger_hold < 10:
        raise SystemExit("--danger-hold must be at least 10")

    warning_amount = args.baseline * (1 + args.warning_percent / 100.0)
    danger_amount = args.baseline * (1 + args.danger_percent / 100.0)

    snapshot_file(SETTINGS_PATH, BACKUP_SETTINGS_PATH)
    snapshot_file(FEED_PATH, BACKUP_FEED_PATH)

    try:
        write_settings(args.baseline, args.warning_percent, args.danger_percent, args.interval, activity_url=args.url)
        print(f"settings updated on {SETTINGS_PATH}")
        print(
            "thresholds: "
            f"baseline={args.baseline:.4f}, "
            f"warning={args.warning_percent:.0f}% (={warning_amount:.4f}), "
            f"danger={args.danger_percent:.0f}% (={danger_amount:.4f}), "
            f"poll={args.interval}s"
        )
        print("sequence: normal -> warning -> danger")

        write_feed(0.001, 0.001, 0.001, 0.001)
        print("state: normal")
        wait_seconds(args.step_wait, "normal")

        write_feed(warning_amount * 1.05, 0.020, 0.020, 0.020)
        print("state: warning expected")
        wait_seconds(args.step_wait, "warning")

        write_feed(danger_amount * 1.05, 0.030, 0.030, 0.030)
        print("state: danger expected (beep+notification cadence until acknowledge)")
        wait_seconds(args.danger_hold, "danger")

        print("smoke sequence complete; keep app open to continue manual verification")
    finally:
        if args.keep_state:
            print("keeping QA state in place because --keep-state was passed")
        else:
            restore_file(BACKUP_SETTINGS_PATH, SETTINGS_PATH)
            restore_file(BACKUP_FEED_PATH, FEED_PATH)
            print("restored pre-QA settings and activity feed")


if __name__ == "__main__":
    main()

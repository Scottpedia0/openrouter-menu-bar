#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Optional


APP_SUPPORT_DIR = Path.home() / "Library" / "Application Support" / "OpenRouterMenuBar"
DEFAULT_OUTPUT_PATH = APP_SUPPORT_DIR / "activity-feed.json"
DEFAULT_STATE_PATH = APP_SUPPORT_DIR / "collector-state.json"
DEFAULT_LOG_PATH = APP_SUPPORT_DIR / "collector.log"
DEFAULT_ALIAS_PATH = APP_SUPPORT_DIR / "key-aliases.json"
DEFAULT_API_BASE = "https://openrouter.ai/api/v1"
HISTORY_RETENTION_HOURS = 24 * 35
BROWSER_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"


class CollectorError(Exception):
    pass


@dataclass
class Config:
    api_key: str
    management_api_key: str
    output_path: Path
    state_path: Path
    log_path: Path
    api_base: str
    poll_interval_seconds: int
    once: bool
    verbose: bool


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def isoformat_z(value: datetime) -> str:
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_iso8601(value: str) -> datetime:
    normalized = value.replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def decimal_from_value(value: Any, field_name: str) -> Decimal:
    if value is None:
        raise CollectorError(f"Missing required field {field_name!r} in OpenRouter activity payload")
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError) as error:
        raise CollectorError(f"Invalid decimal value for {field_name!r}: {value!r}") from error


def read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json_atomic(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(path.suffix + ".tmp")
    with temp_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=False)
        handle.write("\n")
    os.replace(temp_path, path)


def append_log(path: Path, message: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(f"[{isoformat_z(utc_now())}] {message}\n")


def build_key_url(api_base: str) -> str:
    return api_base.rstrip("/") + "/key"


def build_keys_url(api_base: str, offset: int = 0) -> str:
    query = urllib.parse.urlencode({"include_disabled": "true", "offset": str(offset)})
    return api_base.rstrip("/") + f"/keys?{query}"


def build_activity_url(api_base: str) -> str:
    return api_base.rstrip("/") + "/activity"


def fetch_key_usage(api_key: str, api_base: str) -> dict[str, Any]:
    request = urllib.request.Request(build_key_url(api_base))
    request.add_header("Authorization", f"Bearer {api_key}")
    request.add_header("Accept", "application/json")
    request.add_header("User-Agent", BROWSER_USER_AGENT)

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise CollectorError(f"OpenRouter /key request failed with HTTP {error.code}: {detail}") from error
    except urllib.error.URLError as error:
        raise CollectorError(f"OpenRouter /key request failed: {error}") from error

    if not isinstance(payload, dict) or not isinstance(payload.get("data"), dict):
        raise CollectorError("OpenRouter /key response did not contain a data object")
    return payload["data"]


def fetch_account_keys(management_api_key: str, api_base: str) -> list[dict[str, Any]]:
    if not management_api_key:
        return []

    offset = 0
    keys: list[dict[str, Any]] = []
    while True:
        request = urllib.request.Request(build_keys_url(api_base, offset))
        request.add_header("Authorization", f"Bearer {management_api_key}")
        request.add_header("Accept", "application/json")
        request.add_header("User-Agent", BROWSER_USER_AGENT)

        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise CollectorError(f"OpenRouter /keys request failed with HTTP {error.code}: {detail}") from error
        except urllib.error.URLError as error:
            raise CollectorError(f"OpenRouter /keys request failed: {error}") from error

        data = payload.get("data")
        if not isinstance(data, list):
            raise CollectorError("OpenRouter /keys response did not contain a data list")

        if not data:
            break

        keys.extend(item for item in data if isinstance(item, dict))
        offset += len(data)

    return keys


def fetch_activity_rows(management_api_key: str, api_base: str) -> list[dict[str, Any]]:
    if not management_api_key:
        return []

    request = urllib.request.Request(build_activity_url(api_base))
    request.add_header("Authorization", f"Bearer {management_api_key}")
    request.add_header("Accept", "application/json")
    request.add_header("User-Agent", BROWSER_USER_AGENT)

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise CollectorError(f"OpenRouter /activity request failed with HTTP {error.code}: {detail}") from error
    except urllib.error.URLError as error:
        raise CollectorError(f"OpenRouter /activity request failed: {error}") from error

    data = payload.get("data")
    if not isinstance(data, list):
        raise CollectorError("OpenRouter /activity response did not contain a data list")

    return [item for item in data if isinstance(item, dict)]


def history_points_from_state(state_payload: Any) -> list[dict[str, Any]]:
    if not isinstance(state_payload, dict):
        return []
    history = state_payload.get("history")
    if not isinstance(history, list):
        return []
    points: list[dict[str, Any]] = []
    for item in history:
        if not isinstance(item, dict):
            continue
        timestamp = item.get("timestamp")
        usage = item.get("usage")
        if not isinstance(timestamp, str):
            continue
        try:
            usage_decimal = decimal_from_value(usage, "usage")
        except CollectorError:
            continue
        points.append({"timestamp": timestamp, "usage": float(usage_decimal)})
    return points


def key_histories_from_state(state_payload: Any) -> dict[str, list[dict[str, Any]]]:
    if not isinstance(state_payload, dict):
        return {}

    keys_payload = state_payload.get("keys")
    if not isinstance(keys_payload, dict):
        return {}

    histories: dict[str, list[dict[str, Any]]] = {}
    for key_hash, key_state in keys_payload.items():
        if not isinstance(key_hash, str) or not isinstance(key_state, dict):
            continue
        histories[key_hash] = history_points_from_state(key_state)
    return histories


def append_history_point(history: list[dict[str, Any]], fetched_at: datetime, usage_total: Decimal) -> list[dict[str, Any]]:
    retained_after = fetched_at - timedelta(hours=HISTORY_RETENTION_HOURS)
    normalized = []
    for item in history:
        try:
            ts = parse_iso8601(item["timestamp"])
        except Exception:
            continue
        if ts >= retained_after:
            normalized.append({"timestamp": isoformat_z(ts), "usage": float(item["usage"])})
    normalized.append({"timestamp": isoformat_z(fetched_at), "usage": float(usage_total)})
    normalized.sort(key=lambda item: item["timestamp"])
    return normalized


def rolling_delta(history: list[dict[str, Any]], now: datetime, current_usage: Decimal, window_hours: float) -> tuple[Decimal, float]:
    if not history:
        return Decimal("0"), 0.0

    cutoff = now - timedelta(hours=window_hours)
    parsed_history = []
    for item in history:
        try:
            parsed_history.append((parse_iso8601(item["timestamp"]), Decimal(str(item["usage"]))))
        except Exception:
            continue

    if not parsed_history:
        return Decimal("0"), 0.0

    parsed_history.sort(key=lambda item: item[0])
    baseline: Decimal | None = None
    for timestamp, usage in parsed_history:
        if timestamp <= cutoff:
            baseline = usage
        else:
            break

    oldest_timestamp = parsed_history[0][0]
    history_span_minutes = max(0.0, (now - oldest_timestamp).total_seconds() / 60)
    if baseline is None:
        baseline = parsed_history[0][1]

    delta = current_usage - baseline
    if delta < 0:
        delta = Decimal("0")
    return delta, history_span_minutes


def activity_totals_by_date(rows: list[dict[str, Any]]) -> dict[str, Decimal]:
    totals: dict[str, Decimal] = {}
    for row in rows:
        date_value = row.get("date")
        if not isinstance(date_value, str) or not date_value:
            continue
        bucket = date_value.split(" ", 1)[0]
        usage_value = row.get("usage")
        try:
            usage = decimal_from_value(usage_value, f"activity usage for {bucket}")
        except CollectorError:
            continue
        totals[bucket] = totals.get(bucket, Decimal("0")) + usage
    return totals


def activity_window_total(activity_by_date: dict[str, Decimal], current_day_usage: Decimal, completed_days: int) -> Decimal:
    if completed_days <= 0:
        return max(current_day_usage, Decimal("0"))

    total = max(current_day_usage, Decimal("0"))
    for bucket in sorted(activity_by_date.keys(), reverse=True)[:completed_days]:
        total += activity_by_date[bucket]
    return total


def window_samples(now: datetime, hour: Decimal, day: Decimal, week: Decimal, month: Decimal) -> list[dict[str, Any]]:
    return [
        {"timestamp": isoformat_z(now), "amount": float(max(hour, Decimal("0")))},
        {"timestamp": isoformat_z(now.astimezone().replace(hour=0, minute=0, second=0, microsecond=0)), "amount": float(max(day - hour, Decimal("0")))},
        {"timestamp": isoformat_z(start_of_week(now)), "amount": float(max(week - day, Decimal("0")))},
        {"timestamp": isoformat_z(start_of_month(now)), "amount": float(max(month - week, Decimal("0")))},
    ]


def start_of_week(now: datetime) -> datetime:
    local_now = now.astimezone()
    start = local_now - timedelta(days=local_now.weekday())
    return start.replace(hour=0, minute=0, second=0, microsecond=0)


def start_of_month(now: datetime) -> datetime:
    local_now = now.astimezone()
    return local_now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def label_for_key(key_data: dict[str, Any]) -> str:
    for field in ("label", "name", "hash"):
        value = key_data.get(field)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return "Unlabeled key"


def sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def normalize_alias_key(raw_value: str) -> Optional[str]:
    value = raw_value.strip()
    if not value:
        return None
    if value.startswith("sk-or-"):
        return sha256_hex(value)
    if re.fullmatch(r"[0-9a-fA-F]{64}", value):
        return value.lower()
    return None


def alias_entries(payload: Any) -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    if isinstance(payload, dict):
        for label, value in payload.items():
            if isinstance(label, str) and isinstance(value, str):
                entries.append((label, value))
    elif isinstance(payload, list):
        for item in payload:
            if not isinstance(item, dict):
                continue
            label = item.get("label")
            value = item.get("hash") or item.get("key")
            if isinstance(label, str) and isinstance(value, str):
                entries.append((label, value))
    return entries


def configured_key_aliases() -> dict[str, str]:
    alias_paths: list[Path] = []
    env_path = os.environ.get("OPENROUTER_KEY_ALIASES_PATH", "").strip()
    if env_path:
        alias_paths.append(Path(env_path).expanduser())
    alias_paths.append(DEFAULT_ALIAS_PATH)

    aliases: dict[str, str] = {}
    seen_paths: set[Path] = set()
    for alias_path in alias_paths:
        resolved_path = alias_path.expanduser()
        if resolved_path in seen_paths or not resolved_path.exists():
            continue
        seen_paths.add(resolved_path)
        try:
            payload = json.loads(resolved_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        for label, raw_value in alias_entries(payload):
            normalized_key = normalize_alias_key(raw_value)
            normalized_label = label.strip()
            if normalized_key and normalized_label:
                aliases[normalized_key] = normalized_label

    return aliases


def build_app_scopes_from_keys(
    keys: list[dict[str, Any]],
    histories_by_key: dict[str, list[dict[str, Any]]],
    fetched_at_dt: datetime,
    local_aliases_by_hash: dict[str, str],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    scopes: list[dict[str, Any]] = []
    next_key_state: dict[str, Any] = {}

    for key_data in keys:
        key_hash = key_data.get("hash")
        if not isinstance(key_hash, str) or not key_hash:
            continue

        label = local_aliases_by_hash.get(key_hash, label_for_key(key_data))
        usage_total = decimal_from_value(key_data.get("usage"), f"usage for key {label}")
        usage_daily = decimal_from_value(key_data.get("usage_daily"), f"usage_daily for key {label}")
        usage_weekly = decimal_from_value(key_data.get("usage_weekly"), f"usage_weekly for key {label}")
        usage_monthly = decimal_from_value(key_data.get("usage_monthly"), f"usage_monthly for key {label}")

        history = append_history_point(histories_by_key.get(key_hash, []), fetched_at_dt, usage_total)
        usage_hourly, history_span_minutes = rolling_delta(history, fetched_at_dt, usage_total, 1)
        usage_daily, _ = rolling_delta(history, fetched_at_dt, usage_total, 24)
        usage_weekly, _ = rolling_delta(history, fetched_at_dt, usage_total, 24 * 7)
        usage_monthly, _ = rolling_delta(history, fetched_at_dt, usage_total, 24 * 30)
        scope_description = (
            "OpenRouter management /keys usage for this labeled app key, with rolling 1h/1d/1w/1m windows derived from the collector's per-key history."
            if history_span_minutes >= 60
            else f"OpenRouter management /keys usage for this labeled app key, with rolling windows warming up from local history ({history_span_minutes:.0f}m of history so far)."
        )

        scopes.append(
            {
                "kind": "app",
                "key": key_hash,
                "label": label,
                "sourceDescription": scope_description,
                "fetchedAt": isoformat_z(fetched_at_dt),
                "samples": window_samples(fetched_at_dt, usage_hourly, usage_daily, usage_weekly, usage_monthly),
                "directSnapshots": {
                    "hour": float(usage_hourly),
                    "day": float(max(usage_daily, usage_hourly)),
                    "week": float(max(usage_weekly, usage_daily, usage_hourly)),
                    "month": float(max(usage_monthly, usage_weekly, usage_daily, usage_hourly)),
                },
            }
        )
        next_key_state[key_hash] = {
            "label": label,
            "disabled": bool(key_data.get("disabled", False)),
            "history": history,
        }

    return scopes, next_key_state


def write_feed(config: Config) -> dict[str, Any]:
    fetched_at_dt = utc_now()
    previous_state = read_json(config.state_path, {})
    fetched_at = isoformat_z(fetched_at_dt)

    if config.management_api_key:
        account_keys = fetch_account_keys(config.management_api_key, config.api_base)
        activity_rows = fetch_activity_rows(config.management_api_key, config.api_base)
        activity_by_date = activity_totals_by_date(activity_rows)
        key_histories = key_histories_from_state(previous_state)
        scopes, next_key_state = build_app_scopes_from_keys(account_keys, key_histories, fetched_at_dt, configured_key_aliases())

        usage_hourly = Decimal("0")
        current_day_usage = Decimal("0")
        for scope in scopes:
            direct = scope["directSnapshots"]
            usage_hourly += Decimal(str(direct["hour"]))
            current_day_usage += decimal_from_value(next((key.get("usage_daily") for key in account_keys if isinstance(key, dict) and key.get("hash") == scope["key"]), 0), "usage_daily")

        usage_daily = activity_window_total(activity_by_date, current_day_usage, 0)
        usage_weekly = activity_window_total(activity_by_date, current_day_usage, 6)
        usage_monthly = activity_window_total(activity_by_date, current_day_usage, 29)

        source_description = (
            "Truthful OpenRouter account-wide spend using a management key: Last hour is the rolling 60-minute total from local collector history, and 1 day / 1 week / 1 month are trailing windows built from /activity daily buckets plus the current partial day from /keys. App scopes come from per-key labels or your optional key-aliases.json."
        )
        payload = {
            "sourceDescription": source_description,
            "fetchedAt": fetched_at,
            "samples": window_samples(fetched_at_dt, usage_hourly, usage_daily, usage_weekly, usage_monthly),
            "directSnapshots": {
                "hour": float(usage_hourly),
                "day": float(max(usage_daily, usage_hourly)),
                "week": float(max(usage_weekly, usage_daily, usage_hourly)),
                "month": float(max(usage_monthly, usage_weekly, usage_daily, usage_hourly)),
            },
            "scopes": scopes,
        }
        write_json_atomic(config.output_path, payload)

        state_payload = {
            "source": "GET /keys",
            "fetchedAt": fetched_at,
            "currentUsage": {
                "usage_hourly": float(usage_hourly),
                "usage_daily": float(usage_daily),
                "usage_weekly": float(usage_weekly),
                "usage_monthly": float(usage_monthly),
            },
            "keys": next_key_state,
            "sourceDescription": source_description,
        }
        write_json_atomic(config.state_path, state_payload)

        return {
            "fetchedAt": fetched_at,
            "hourlyAmount": float(usage_hourly),
            "dayAmount": float(usage_daily),
            "weekAmount": float(usage_weekly),
            "monthAmount": float(usage_monthly),
            "scopeCount": len(scopes),
            "outputPath": str(config.output_path),
            "source": "GET /keys",
        }
    else:
        key_data = fetch_key_usage(config.api_key, config.api_base)
        usage_total = decimal_from_value(key_data.get("usage"), "usage")
        usage_daily = decimal_from_value(key_data.get("usage_daily"), "usage_daily")
        usage_weekly = decimal_from_value(key_data.get("usage_weekly"), "usage_weekly")
        usage_monthly = decimal_from_value(key_data.get("usage_monthly"), "usage_monthly")

        history = append_history_point(history_points_from_state(previous_state), fetched_at_dt, usage_total)
        usage_hourly, history_span_minutes = rolling_delta(history, fetched_at_dt, usage_total, 1)

        if history_span_minutes >= 60:
            source_description = (
            "Truthful OpenRouter GET /key current UTC day/week/month counters for this key, plus exact last-60m spend "
            "derived from the collector's persisted total-usage history for that same key."
        )
        else:
            source_description = (
                f"OpenRouter GET /key current UTC day/week/month counters for this key, plus observed spend since collector warm-up "
                f"began ({history_span_minutes:.0f}m of history so far). The last-60m value becomes exact after one full hour of polling history."
            )

        payload = {
            "sourceDescription": source_description,
            "fetchedAt": fetched_at,
            "samples": window_samples(fetched_at_dt, usage_hourly, usage_daily, usage_weekly, usage_monthly),
            "directSnapshots": {
                "hour": float(usage_hourly),
                "day": float(max(usage_daily, usage_hourly)),
                "week": float(max(usage_weekly, usage_daily, usage_hourly)),
                "month": float(max(usage_monthly, usage_weekly, usage_daily, usage_hourly)),
            },
        }
        write_json_atomic(config.output_path, payload)

        state_payload = {
            "source": "GET /key",
            "fetchedAt": fetched_at,
            "currentUsage": {
                "usage": float(usage_total),
                "usage_daily": float(usage_daily),
                "usage_weekly": float(usage_weekly),
                "usage_monthly": float(usage_monthly),
            },
            "history": history,
            "historySpanMinutes": history_span_minutes,
            "sourceDescription": source_description,
        }
        write_json_atomic(config.state_path, state_payload)

        return {
            "fetchedAt": fetched_at,
            "hourlyAmount": float(usage_hourly),
            "dayAmount": float(usage_daily),
            "weekAmount": float(usage_weekly),
            "monthAmount": float(usage_monthly),
            "scopeCount": 0,
            "outputPath": str(config.output_path),
            "source": "GET /key",
        }


def parse_args(argv: list[str]) -> Config:
    parser = argparse.ArgumentParser(description="Poll OpenRouter usage data and write activity-feed.json")
    parser.add_argument(
        "--api-key",
        default=os.environ.get("OPENROUTER_API_KEY", ""),
        help="OpenRouter runtime key for current-key /key mode; defaults to OPENROUTER_API_KEY",
    )
    parser.add_argument(
        "--management-api-key",
        default=(
            os.environ.get("OPENROUTER_MANAGEMENT_API_KEY", "")
            or os.environ.get("OPENROUTER_PROVISIONING_API_KEY", "")
            or os.environ.get("OPENROUTER_PROVISIONING_KEY", "")
        ),
        help="OpenRouter management/provisioning key for account-wide /keys mode; defaults to OPENROUTER_MANAGEMENT_API_KEY",
    )
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH), help="Path to write activity-feed.json")
    parser.add_argument("--state", default=str(DEFAULT_STATE_PATH), help="Path to write collector state")
    parser.add_argument("--log", default=str(DEFAULT_LOG_PATH), help="Path to append collector logs")
    parser.add_argument("--api-base", default=os.environ.get("OPENROUTER_API_BASE", DEFAULT_API_BASE), help="OpenRouter API base URL")
    parser.add_argument("--poll-interval", type=int, default=int(os.environ.get("OPENROUTER_COLLECTOR_POLL_INTERVAL", "300")), help="Polling interval in seconds for daemon mode")
    parser.add_argument("--once", action="store_true", help="Run one collection cycle and exit")
    parser.add_argument("--verbose", action="store_true", help="Print collector progress to stdout")
    args = parser.parse_args(argv)

    if not args.api_key and not args.management_api_key:
        raise CollectorError(
            "Missing OpenRouter key. Set OPENROUTER_API_KEY for whole-key mode, or OPENROUTER_MANAGEMENT_API_KEY for account-wide per-app-key mode."
        )

    return Config(
        api_key=args.api_key,
        management_api_key=args.management_api_key,
        output_path=Path(args.output).expanduser(),
        state_path=Path(args.state).expanduser(),
        log_path=Path(args.log).expanduser(),
        api_base=args.api_base,
        poll_interval_seconds=max(args.poll_interval, 30),
        once=args.once,
        verbose=args.verbose,
    )


def log(config: Config, message: str) -> None:
    append_log(config.log_path, message)
    if config.verbose:
        print(message)


def main(argv: list[str]) -> int:
    try:
        config = parse_args(argv)
    except CollectorError as error:
        print(str(error), file=sys.stderr)
        return 2

    while True:
        try:
            result = write_feed(config)
            log(
                config,
                f"Collector sync ok: source={result['source']} scopes={result['scopeCount']} hour={result['hourlyAmount']:.2f} day={result['dayAmount']:.2f} week={result['weekAmount']:.2f} month={result['monthAmount']:.2f} output={result['outputPath']}",
            )
        except CollectorError as error:
            log(config, f"Collector sync failed: {error}")
            if config.once:
                print(str(error), file=sys.stderr)
                return 1

        if config.once:
            return 0

        time.sleep(config.poll_interval_seconds)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

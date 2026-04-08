#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launch_agents_dir="$HOME/Library/LaunchAgents"
app_support_dir="$HOME/Library/Application Support/OpenRouterMenuBar"
binary_path="$repo_root/.build/release/OpenRouterMenuBar"
app_plist_target="$launch_agents_dir/com.openrouter.menubar.app.plist"
collector_plist_target="$launch_agents_dir/com.openrouter.menubar.collector.plist"

runtime_key="${OPENROUTER_API_KEY:-}"
management_key="${OPENROUTER_MANAGEMENT_API_KEY:-}"

if [[ -z "$runtime_key" && -z "$management_key" ]]; then
  echo "Set OPENROUTER_API_KEY or OPENROUTER_MANAGEMENT_API_KEY before running this installer." >&2
  exit 1
fi

mkdir -p "$launch_agents_dir" "$app_support_dir"

echo "Building release binary..."
swift build -c release --package-path "$repo_root"

python3 <<PY
from pathlib import Path

repo_root = Path(${repo_root@Q})
launch_agents_dir = Path(${launch_agents_dir@Q})
app_support_dir = Path(${app_support_dir@Q})
binary_path = Path(${binary_path@Q})
runtime_key = ${runtime_key@Q}
management_key = ${management_key@Q}

replacements = {
    "__BINARY_PATH__": str(binary_path),
    "__WORKING_DIR__": str(repo_root),
    "__REPO_PATH__": str(repo_root),
    "__LOG_DIR__": str(app_support_dir),
    "__OPENROUTER_API_KEY__": runtime_key,
    "__OPENROUTER_MANAGEMENT_API_KEY__": management_key,
}

for name in ("com.openrouter.menu-bar.app.plist", "com.openrouter.menu-bar.collector.plist"):
    source = repo_root / "launchd" / name
    target = launch_agents_dir / name
    text = source.read_text(encoding="utf-8")
    for needle, replacement in replacements.items():
        text = text.replace(needle, replacement)
    target.write_text(text, encoding="utf-8")
PY

launchctl bootout "gui/$UID" com.openrouter.menubar.app >/dev/null 2>&1 || true
launchctl bootout "gui/$UID" com.openrouter.menubar.collector >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$app_plist_target"
launchctl bootstrap "gui/$UID" "$collector_plist_target"
launchctl kickstart -k "gui/$UID/com.openrouter.menubar.app"
launchctl kickstart -k "gui/$UID/com.openrouter.menubar.collector"

echo
echo "Installed launch agents:"
echo "  $app_plist_target"
echo "  $collector_plist_target"
echo
echo "Logs and local state live in:"
echo "  $app_support_dir"

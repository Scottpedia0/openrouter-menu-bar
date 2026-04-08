#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

runtime_key="$(security find-generic-password -a "$USER" -s OpenRouterMenuBarRuntimeKey -w 2>/dev/null || true)"
management_key="$(security find-generic-password -a "$USER" -s OpenRouterMenuBarManagementKey -w 2>/dev/null || true)"

if [[ -z "$runtime_key" && -z "$management_key" ]]; then
  echo "OpenRouter Menu Bar collector could not find a runtime or management key in Keychain." >&2
  exit 1
fi

exec /usr/bin/env \
  OPENROUTER_API_KEY="$runtime_key" \
  OPENROUTER_MANAGEMENT_API_KEY="$management_key" \
  python3 "$repo_root/collector/openrouter_collector.py" "$@"

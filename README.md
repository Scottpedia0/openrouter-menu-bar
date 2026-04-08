# OpenRouter Menu Bar

OpenRouter Menu Bar is a lightweight macOS menu bar utility for monitoring OpenRouter spend, surfacing alerts, and providing a local fallback hard-kill hook.

It is intentionally narrow. The point is to keep OpenRouter spend visible in the top menu bar so runaway usage is obvious fast, while still letting you drill down to app-level spend when you have one key per app.

There is no telemetry or analytics layer in this repo. The app talks to OpenRouter, writes local state under your Application Support folder, and otherwise stays on your machine.

## What It Does

- shows OpenRouter spend in the macOS menu bar
- colors the badge by posture: normal, idle, warning, danger
- opens the OpenRouter Activity page on left click
- shows spend and alert controls on right click
- persists settings locally in Application Support
- supports a local collector for whole-account totals and per-app scopes
- supports a local fallback hard-kill hook

## Important Safety Note

Do not depend on the local hard kill as your only protection.

Set critical limits directly in OpenRouter. The local hard-kill path is a fallback for presence and interruption, not the primary safety boundary.

## Quick Start

1. Export `OPENROUTER_API_KEY` for single-key mode, or `OPENROUTER_MANAGEMENT_API_KEY` for account-wide mode.
2. Run `scripts/install_launch_agents.sh`.
3. Log out and back in, or kick the launch agents with `launchctl`.
4. Look for the `OpenRouter Menu Bar` badge in the macOS menu bar.

The installer stores your key in the macOS login Keychain and keeps launchd plists free of plaintext credentials. That is better than embedding keys in launchd, but it is still user-session security, not hardware-backed isolation.

## Spend Windows

- `Last hour` is the rolling 60-minute total
- `1 day`, `1 week`, and `1 month` are collector windows that can need time to warm up after a fresh install
- in management-key mode, the longer windows are seeded from OpenRouter account activity plus the current partial day
- in runtime-key mode, the longer windows are limited by the local collector history you have accumulated so far

## App Scoping

Default view is `All OpenRouter`.

`One app` becomes real when:

- each app has its own OpenRouter API key
- those keys are labeled clearly
- the collector runs with an OpenRouter management key

Without that setup, the utility still works for whole-account monitoring.

Optional relabeling lives in:

- `~/Library/Application Support/OpenRouterMenuBar/key-aliases.json`

That file can map labels to full keys or pre-hashed key IDs, for example:

```json
{
  "Local OpenCode": "sk-or-v1-...",
  "AWS OpenWork": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}
```

## Local State

The app uses:

- `~/Library/Application Support/OpenRouterMenuBar/settings.json`
- `~/Library/Application Support/OpenRouterMenuBar/activity-feed.json`
- `~/Library/Application Support/OpenRouterMenuBar/collector-state.json`
- `~/Library/Application Support/OpenRouterMenuBar/runtime.log`

## Build The App

Requirements:

- macOS 13+
- Xcode 15+ or Swift 5.9+

```bash
swift build
swift run
```

## Run The Collector

Runtime-key mode for a single key:

```bash
OPENROUTER_API_KEY=your_runtime_key python3 collector/openrouter_collector.py --verbose
```

Management-key mode for whole-account totals plus per-app scopes:

```bash
OPENROUTER_MANAGEMENT_API_KEY=your_management_key python3 collector/openrouter_collector.py --verbose
```

The management key is an account-level admin key, not the key your apps should share for model calls. Use normal per-app runtime keys for each real app, then let the collector read them with the management key.

## Start At Login

The repo includes:

- `launchd/com.openrouter.menu-bar.app.plist`
- `launchd/com.openrouter.menu-bar.collector.plist`
- `scripts/install_launch_agents.sh`

The install script builds the release binary, fills the plist placeholders, installs them into `~/Library/LaunchAgents/`, and bootstraps both agents.

## Distribution Notes

- Public repo source is ready to build locally.
- The current install path is unsigned source-build territory, not a notarized drag-and-drop Mac app yet.
- If you plan to hand this to less technical users, the next step is a signed `.app` release flow.
- If you are upgrading from an older local setup that embedded keys in launchd plists, rotate those keys and remove the old plist files instead of trusting stale credentials.

## Quick QA

There is a smoke-test helper at `scripts/qa-posture-smoke.py` for forcing normal, warning, and danger states without spending real money.

It snapshots and restores your existing settings/feed by default. Pass `--keep-state` only if you intentionally want the QA state to stay live afterward.

## Troubleshooting

- If the badge is gray or says `Never`, the collector probably has not written `activity-feed.json` yet.
- If the badge looks stale, open the popover and check the `Updated ...` timestamp and freshness note.
- If `One app` has no options, your feed does not have truthful app scopes yet. The usual fix is one key per app plus a management key for the collector.
- If hard kill does nothing, make sure it is armed and that the optional command is a direct executable plus arguments, not a shell pipeline.
- If the launch agents fail, check `~/Library/Application Support/OpenRouterMenuBar/app-launchd.log` and `collector-launchd.log`.

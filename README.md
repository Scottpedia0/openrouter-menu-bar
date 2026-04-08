# OpenRouter Menu Bar

OpenRouter Menu Bar is a lightweight macOS menu bar utility for monitoring OpenRouter spend, surfacing alerts, and providing a local fallback hard-kill hook.

It is intentionally narrow. The point is to keep OpenRouter spend visible in the top menu bar so runaway usage is obvious fast, while still letting you drill down to app-level spend when you have one key per app.

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

## Spend Windows

- `Last hour` is the rolling 60-minute total
- `1 day`, `1 week`, and `1 month` are meant to track the same filter-style windows you see in OpenRouter Activity

## App Scoping

Default view is `All OpenRouter`.

`One app` becomes real when:

- each app has its own OpenRouter API key
- those keys are labeled clearly
- the collector runs with an OpenRouter management key

Without that setup, the utility still works for whole-account monitoring.

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

## Start At Login

Template launchd plists are included in `launchd/`.

- `launchd/com.openrouter.menu-bar.app.plist`
- `launchd/com.openrouter.menu-bar.collector.plist`

Fill in the placeholders, copy them into `~/Library/LaunchAgents/`, then load them with `launchctl`.

## Quick QA

There is a smoke-test helper at `scripts/qa-posture-smoke.py` for forcing normal, warning, and danger states without spending real money.

# Claude Bar 🍸

A lightweight macOS menu bar app that monitors your Claude API usage in real-time.

![screenshot](screenshot.png)

## Features

- **Two ring gauges** in the status bar: 5-hour and 7-day usage windows
- **Drift visualization**: green (under pace), orange (>+10%), red (>+30%)
- **Tick marks** showing elapsed time position in each window
- **Popover** with large gauges, drift details, and reset timers
- **Extra usage** cost displayed when a window reaches 100%
- Reads OAuth token from macOS Keychain (Claude Code credentials)
- **Auto-refresh** of OAuth tokens when expired
- Auto-refreshes every 5 minutes

## Install

```
brew tap xcid/tap
brew install --cask claude-bar
```

## Build from source

```
make
open build/ClaudeUsageBar.app
```

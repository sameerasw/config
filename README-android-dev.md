# android-build

A clean, terminal-based tool to build, deploy, debug, and stream filtered logs for physical Android devices.

## Setup Alias

Add an alias to your `~/.zshrc` so you can call `android-build` from anywhere in your terminal:

```bash
alias android-build="/Users/sameerasandakelum/GIT/config/android-build.sh"
```

---

## Menu Layout

```text
android-build
──────────────────────────────────────────────────
  Project:   Essentials v17.1 (60)
  Package:   com.sameerasw.essentials
  Branch:    develop  SDK 37
  Device:    46121FDAP004D9
  Task:      assembleDebug [debug]
──────────────────────────────────────────────────
  [R] Run & Debug
  [I] Install only
  [O] Optimized debug
  [L] Logcat

  [F] Force stop
  [S] Start

  [M] Mirror
  [G] Gradle Sync
  [T] Format code
  [C] Clean build
  [B] Release build
  [Y] Import icons

  [W] Wireless ADB
  [D] Switch Device
  [P] Switch Project

  [E] Open in editor
  [Q] Quit
──────────────────────────────────────────────────
> 
```

---

## Shortcuts & CLI Commands

| Shortcut / Command | Description | Example |
| :--- | :--- | :--- |
| `R` / `run` | Build $\to$ Install $\to$ Launch $\to$ Stream Logs | `android-build run essentials.android.config` |
| `I` / `install` | Build and install APK $\to$ Launch | `android-build install` |
| `O` / `opt` | Build & install with optimized dev settings | `android-build opt essentials.android.config` |
| `L` / `logs` | Stream colored logcat filtered by package PID | `android-build logs essentials.android.config` |
| `F` / `stop` | Force-stop application | `android-build stop` |
| `S` / `start` | Start/Launch main activity | `android-build start` |
| `M` / `mirror` | Open `scrcpy` window for active device | `android-build mirror` |
| `G` / `sync` | Run Gradle sync & daemon check | `android-build sync` |
| `T` / `format` | Format Kotlin code & optimize imports | `android-build format` |
| `C` / `clean` | Run `./gradlew clean` + stop daemons | `android-build clean` |
| `B` / `release` | Build production release artifacts based on `release_type` | `android-build release` |
| `Y` / `icons` | Download & add Material Symbols vector drawables | `android-build icons` |
| `W` / `wifi` | Pair and connect via Wireless ADB | `android-build wifi` |
| `D` / `devices`| Switch/list connected ADB devices | `android-build devices` |
| `P` / `project`| Switch active project | `android-build project` |
| `E` / `editor` | Open workspace file or project in Antigravity IDE | `android-build editor` |

---

## Kotlin Code Formatting (`[T]` / `format`)

Runs `ktlint` (auto-installed on first run to `~/.cache/android-build/ktlint`):
1. **`[1] Modified files only`** *(Fastest - only formats files in your current `git status`)*
2. **`[2] Entire project`** *(Formats all `*.kt` and `*.kts` files)*
3. **`[3] Specific directory / file`** *(Target specific paths)*

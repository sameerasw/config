# android-build

A clean, terminal-based tool to build, deploy, debug, and stream filtered logs for physical Android devices.

## Setup Alias

Add an alias to your `~/.zshrc` so you can call `android-build` from anywhere in your terminal:

```bash
alias android-build="/Users/sameerasandakelum/GIT/config/android-build.sh"
```

---

## Usage

### Interactive Menu
- **If run anywhere (e.g. `android-build` or `./android-build.sh`) without arguments**:
  - If inside an Android repository directory $\to$ auto-detects that project.
  - If in an arbitrary directory $\to$ automatically scans for available projects (`*.android.config`) and renders a clean picker:
    ```text
    android-build
    ──────────────────────────────────────────────────
    Available Projects:
      [1] Essentials      (com.sameerasw.essentials)
      [2] AirSync         (com.sameerasw.airsync)
    ──────────────────────────────────────────────────
    Select project [1-2] (default 1): 
    ```

---

## Menu Layout

```text
android-build
──────────────────────────────────────────────────
  Project:   Essentials
  Package:   com.sameerasw.essentials
  Device:    46121FDAP004D9
  Task:      assembleDebug
──────────────────────────────────────────────────
  [R] Run & Debug
  [I] Install only
  [O] Optimized debug
  [L] Logcat

  [F] Force stop
  [S] Start
  [C] Clear data

  [M] Mirror
  [G] Gradle Sync

  [W] Wireless ADB
  [D] Switch Device

  [E] Open in editor
  [Q] Quit
──────────────────────────────────────────────────
> 
```

> **Hidden combo**: Typing `FC` will force-stop the app, clear data/cache (with confirmation prompt), and immediately auto re-launch it.

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
| `C` / `clear` | Reset app cache and storage (with confirmation) | `android-build clear` |
| `M` / `mirror` | Open `scrcpy` window for active device | `android-build mirror` |
| `G` / `sync` | Run Gradle sync & daemon check | `android-build sync` |
| `W` / `wifi` | Pair and connect via Wireless ADB | `android-build wifi` |
| `D` / `devices`| Switch/list connected ADB devices | `android-build devices` |
| `E` / `editor` | Open workspace file or project in Antigravity IDE | `android-build editor` |
| `FC` *(menu only)*| Force-stop, clear data, and auto re-launch | |

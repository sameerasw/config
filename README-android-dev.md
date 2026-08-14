# android-build

A clean, terminal-based tool to build, deploy, debug, and stream filtered logs for physical Android devices.

## Usage

### Interactive Menu
```bash
./android-build.sh [config_file]
```

Example menu:
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

  [Q] Quit
──────────────────────────────────────────────────
> 
```

> **Hidden combo**: Typing `FC` will force-stop the app, clear data/cache (with confirmation prompt), and immediately auto re-launch it.

---

## Shortcuts & CLI Commands

| Shortcut / Command | Description | Example |
| :--- | :--- | :--- |
| `R` / `run` | Build $\to$ Install $\to$ Launch $\to$ Stream Logs | `./android-build.sh run essentials.android.config` |
| `I` / `install` | Build and install APK | `./android-build.sh install` |
| `O` / `opt` | Build & install with optimized dev settings | `./android-build.sh opt essentials.android.config` |
| `L` / `logs` | Stream colored logcat filtered by package PID | `./android-build.sh logs essentials.android.config` |
| `F` / `stop` | Force-stop application | `./android-build.sh stop` |
| `S` / `start` | Start/Launch main activity | `./android-build.sh start` |
| `C` / `clear` | Reset app cache and storage (with confirmation) | `./android-build.sh clear` |
| `M` / `mirror` | Open `scrcpy` window for active device | `./android-build.sh mirror` |
| `G` / `sync` | Run Gradle sync & daemon check | `./android-build.sh sync` |
| `W` / `wifi` | Pair and connect via Wireless ADB | `./android-build.sh wifi` |
| `D` / `devices`| Switch/list connected ADB devices | `./android-build.sh devices` |
| `FC` *(menu only)*| Force-stop, clear data, and auto re-launch | |

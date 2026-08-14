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
  [1] Run & Debug
  [2] Install only
  [3] Logcat
  [4] Re-launch
  [5] Force stop
  [6] Clear data
  [7] Mirror
  [8] Wireless ADB
  [d] Switch Device
  [q] Quit
──────────────────────────────────────────────────
> 
```

---

## CLI Commands

| Command | Description | Example |
| :--- | :--- | :--- |
| `run` | Build $\to$ Install $\to$ Launch $\to$ Stream Logs | `./android-build.sh run essentials.android.config` |
| `build` | Execute Gradle build task | `./android-build.sh build` |
| `install` | Install built APK to selected device | `./android-build.sh install` |
| `launch` | Start app main activity | `./android-build.sh launch` |
| `restart` | Force-stop and restart app | `./android-build.sh restart` |
| `stop` | Force-stop application | `./android-build.sh stop` |
| `clear` | Reset app cache and storage (with confirmation) | `./android-build.sh clear` |
| `logs` | Stream colored logcat filtered by package PID | `./android-build.sh logs essentials.android.config` |
| `mirror` | Open `scrcpy` window for active device | `./android-build.sh mirror` |
| `devices`| List all connected ADB devices | `./android-build.sh devices` |
| `wifi` | Pair and connect via Wireless ADB | `./android-build.sh wifi` |

---

## Configuration Files

Create `.android.config` files (e.g. `essentials.android.config` or `airsync.android.config`) in the `config` directory:

```ini
# Project Name
project_name=Essentials

# Path to local repository root
project_dir=/Users/sameerasandakelum/GIT/essentials

# Android Application Package Name
package_name=com.sameerasw.essentials

# Main Activity (relative or full)
main_activity=.MainActivity

# Gradle task to run
gradle_task=assembleDebug

# Build variant
build_variant=debug

# Optional: Specific target device serial
# target_device=46121FDAP004D9
```

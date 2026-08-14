#!/usr/bin/env bash
# ==============================================================================
# Android Developer CLI & TUI System (dev-android.sh)
# Fast, lightweight Android Studio replacement for building, deploying,
# launching, debugging, and live logcat filtering on physical devices.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG="essentials.android.config"

# --- Styling & Colors ---
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
ITALIC="\033[3m"
UNDERLINE="\033[4m"

# Palette (Material Dark inspired)
C_PRIMARY="\033[38;5;75m"     # Light Blue / Cyan
C_ACCENT="\033[38;5;213m"     # Pink / Magenta
C_SUCCESS="\033[38;5;77m"     # Soft Green
C_WARN="\033[38;5;220m"       # Amber / Yellow
C_ERROR="\033[38;5;203m"      # Soft Red
C_MUTED="\033[38;5;244m"      # Grey
C_BG_CARD="\033[48;5;236m"    # Dark surface

# Log level colors
LOG_V="\033[38;5;245m"
LOG_D="\033[38;5;81m"
LOG_I="\033[38;5;120m"
LOG_W="\033[38;5;221m"
LOG_E="\033[38;5;196m\033[1m"
LOG_F="\033[48;5;196m\033[38;5;15m\033[1m"

# --- Utilities ---
log_info()    { echo -e "${C_PRIMARY}[INFO]${RESET} $*"; }
log_success() { echo -e "${C_SUCCESS}[SUCCESS]${RESET} $*"; }
log_warn()    { echo -e "${C_WARN}[WARN]${RESET} $*"; }
log_error()   { echo -e "${C_ERROR}[ERROR]${RESET} $*" >&2; }

# --- Config Parsing ---
CONFIG_FILE=""
SUBCOMMAND=""
ARGS=()

get_config_val() {
  local key="$1"
  local default="${2:-}"
  local val
  if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    val=$(grep -E "^[[:space:]]*$key[[:space:]]*=" "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
    if [[ "$val" =~ ^\"(.*)\"$ ]] || [[ "$val" =~ ^\'(.*)\'$ ]]; then
      val="${BASH_REMATCH[1]}"
    fi
  fi
  echo "${val:-$default}"
}

# Auto-detect project if inside one
detect_project() {
  if [[ -f "./build.gradle.kts" || -f "./build.gradle" || -f "./gradlew" ]]; then
    local cur_dir="$(pwd)"
    local name="$(basename "$cur_dir")"
    CONFIG_project_name="${CONFIG_project_name:-$name}"
    CONFIG_project_dir="${CONFIG_project_dir:-$cur_dir}"
    
    # Try reading package name from AndroidManifest.xml or build.gradle.kts
    if [[ -z "${CONFIG_package_name:-}" ]]; then
      if [[ -f "./app/build.gradle.kts" ]]; then
        local pkg=$(grep -E "namespace[[:space:]]*=[[:space:]]*\"" ./app/build.gradle.kts | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
        [[ -n "$pkg" ]] && CONFIG_package_name="$pkg"
      fi
    fi
  fi
}

select_project_interactive() {
  local config_files=()
  while IFS= read -r f; do
    [[ -n "$f" && "$(basename "$f")" != "template.android.config" ]] && config_files+=("$f")
  done < <(find "$SCRIPT_DIR" -maxdepth 2 -name "*.android.config" 2>/dev/null | sort || true)

  local count=${#config_files[@]}
  if [[ "$count" -eq 0 ]]; then
    return 0
  fi

  if [[ "$count" -eq 1 ]]; then
    CONFIG_FILE="${config_files[0]}"
    return 0
  fi

  clear
  echo -e "${BOLD}${C_PRIMARY}android-build${RESET}"
  echo -e "${C_MUTED}──────────────────────────────────────────────────${RESET}"
  echo -e "Available Projects:"
  local i=1
  for cfg in "${config_files[@]}"; do
    local p_name=$(grep -E "^[[:space:]]*project_name[[:space:]]*=" "$cfg" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || basename "$cfg" .android.config)
    local p_pkg=$(grep -E "^[[:space:]]*package_name[[:space:]]*=" "$cfg" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")
    printf "  ${BOLD}[%d]${RESET} %-15s ${C_MUTED}(%s)${RESET}\n" "$i" "$p_name" "$p_pkg"
    ((i++))
  done
  echo -e "${C_MUTED}──────────────────────────────────────────────────${RESET}"
  while true; do
    read -rp "Select project [1-$count] (default 1): " choice
    choice="${choice:-1}"
    case "$choice" in
      [1-9]|[1-9][0-9])
        if [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
          CONFIG_FILE="${config_files[$((choice-1))]}"
          break
        else
          log_warn "Invalid input."
        fi
        ;;
      *)
        log_warn "Invalid input."
        ;;
    esac
  done
}

load_config() {
  local file="${1:-}"

  # If no file provided and we are not in an android project directory, prompt project picker
  if [[ -z "$file" ]]; then
    if [[ ! -f "./build.gradle.kts" && ! -f "./build.gradle" && ! -f "./gradlew" ]]; then
      select_project_interactive
      file="${CONFIG_FILE:-}"
    fi
  fi

  if [[ -n "$file" && "$file" != /* ]]; then
    if [[ -f "$SCRIPT_DIR/$file" ]]; then
      file="$SCRIPT_DIR/$file"
    elif [[ -f "$(pwd)/$file" ]]; then
      file="$(pwd)/$file"
    fi
  fi

  if [[ -n "$file" && -f "$file" ]]; then
    CONFIG_FILE="$file"
    CONFIG_project_name=$(get_config_val "project_name" "AndroidApp")
    CONFIG_project_dir=$(get_config_val "project_dir" "$SCRIPT_DIR")
    CONFIG_workspace_file=$(get_config_val "workspace_file")
    CONFIG_package_name=$(get_config_val "package_name")
    CONFIG_main_activity=$(get_config_val "main_activity" ".MainActivity")
    CONFIG_gradle_task=$(get_config_val "gradle_task" "assembleDebug")
    CONFIG_build_variant=$(get_config_val "build_variant" "debug")
    CONFIG_release_type=$(get_config_val "release_type" "apk")
    CONFIG_keystore_file=$(get_config_val "keystore_file")
    CONFIG_keystore_alias=$(get_config_val "keystore_alias")
    CONFIG_keystore_pass=$(get_config_val "keystore_pass")
    CONFIG_key_pass=$(get_config_val "key_pass")
    CONFIG_apk_path=$(get_config_val "apk_path")
    CONFIG_target_device=$(get_config_val "target_device")
    CONFIG_log_tags=$(get_config_val "log_tags")
  else
    detect_project
    CONFIG_project_name="${CONFIG_project_name:-Essentials}"
    CONFIG_project_dir="${CONFIG_project_dir:-$HOME/GIT/essentials}"
    CONFIG_workspace_file="${CONFIG_workspace_file:-}"
    CONFIG_package_name="${CONFIG_package_name:-com.sameerasw.essentials}"
    CONFIG_main_activity="${CONFIG_main_activity:-.MainActivity}"
    CONFIG_gradle_task="${CONFIG_gradle_task:-assembleDebug}"
    CONFIG_build_variant="${CONFIG_build_variant:-debug}"
    CONFIG_release_type="${CONFIG_release_type:-apk}"
    CONFIG_keystore_file="${CONFIG_keystore_file:-}"
    CONFIG_keystore_alias="${CONFIG_keystore_alias:-}"
    CONFIG_keystore_pass="${CONFIG_keystore_pass:-}"
    CONFIG_key_pass="${CONFIG_key_pass:-}"
    CONFIG_apk_path="${CONFIG_apk_path:-}"
    CONFIG_target_device="${CONFIG_target_device:-}"
    CONFIG_log_tags="${CONFIG_log_tags:-}"
  fi
}

# --- Device Management ---
check_adb() {
  if ! command -v adb >/dev/null 2>&1; then
    log_error "'adb' command not found in PATH. Please make sure Android platform-tools are in your PATH."
    exit 1
  fi
}

get_connected_devices() {
  adb devices -l | grep -v "List of devices attached" | grep -v "^$" | grep "device " || true
}

save_target_device_to_config() {
  local new_device="$1"
  if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    if grep -q "^[[:space:]]*target_device[[:space:]]*=" "$CONFIG_FILE"; then
      # Update existing key
      sed -i '' "s|^[[:space:]]*target_device[[:space:]]*=.*|target_device=$new_device|" "$CONFIG_FILE" 2>/dev/null || \
      sed -i "s|^[[:space:]]*target_device[[:space:]]*=.*|target_device=$new_device|" "$CONFIG_FILE" 2>/dev/null || true
    else
      echo "target_device=$new_device" >> "$CONFIG_FILE"
    fi
    CONFIG_target_device="$new_device"
    log_success "Saved '$new_device' as default target in $(basename "$CONFIG_FILE")."
  fi
}

select_device() {
  local force="${1:-false}"
  check_adb
  local devices_output
  devices_output=$(get_connected_devices)
  
  if [[ -z "$devices_output" ]]; then
    log_error "No connected Android devices found via ADB."
    echo -e "${C_MUTED}Tip: Connect your device via USB with USB Debugging enabled, or connect via Wi-Fi ADB.${RESET}"
    exit 1
  fi

  # If not forcing a re-select and we already have a valid selected/configured device that is still online
  if [[ "$force" != "true" ]]; then
    local active_target="${SELECTED_DEVICE:-$CONFIG_target_device}"
    if [[ -n "$active_target" ]]; then
      if echo "$devices_output" | grep -q "$active_target"; then
        SELECTED_DEVICE="$active_target"
        return 0
      else
        log_warn "Previously selected device '$active_target' is unavailable. Re-selecting..."
      fi
    fi
  fi

  local count=$(echo "$devices_output" | wc -l | tr -d ' ')
  local picked_dev=""

  if [[ "$count" -eq 1 ]]; then
    picked_dev=$(echo "$devices_output" | awk '{print $1}')
  else
    echo -e "\n${BOLD}${C_PRIMARY}Multiple Android Devices Detected:${RESET}"
    local i=1
    declare -a dev_arr=()
    while IFS= read -r line; do
      local serial=$(echo "$line" | awk '{print $1}')
      local model=$(echo "$line" | grep -o 'model:[^ ]*' | cut -d':' -f2 || echo "")
      local prod=$(echo "$line" | grep -o 'product:[^ ]*' | cut -d':' -f2 || echo "")
      dev_arr+=("$serial")
      printf "  ${BOLD}[%d]${RESET} %-25s ${C_MUTED}(%s %s)${RESET}\n" "$i" "$serial" "$model" "$prod"
      ((i++))
    done <<< "$devices_output"

    while true; do
      read -rp "Select device [1-$count] (default 1): " choice
      choice="${choice:-1}"
      case "$choice" in
        [1-9]|[1-9][0-9])
          if [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
            picked_dev="${dev_arr[$((choice-1))]}"
            break
          else
            log_warn "Invalid input."
          fi
          ;;
        *)
          log_warn "Invalid input."
          ;;
      esac
    done
  fi

  SELECTED_DEVICE="$picked_dev"

  # Ask if user wants to persist this device to the config file
  if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    echo -en "${C_MUTED}Save '$picked_dev' as default target device in config? [y/N]: ${RESET}"
    read -r save_choice
    if [[ "$save_choice" =~ ^[Yy]$ ]]; then
      save_target_device_to_config "$picked_dev"
    fi
  fi
}

adb_cmd() {
  if [[ -n "${SELECTED_DEVICE:-}" ]]; then
    adb -s "$SELECTED_DEVICE" "$@"
  else
    adb "$@"
  fi
}

# --- Actions ---

find_built_apk() {
  local project_path="$1"
  if [[ -n "$CONFIG_apk_path" && -f "$project_path/$CONFIG_apk_path" ]]; then
    echo "$project_path/$CONFIG_apk_path"
    return 0
  fi

  # Auto find newest APK matching variant inside outputs/apk
  local found
  found=$(find "$project_path" -maxdepth 6 -name "*-${CONFIG_build_variant}.apk" 2>/dev/null | grep "/build/outputs/apk/" | xargs ls -t 2>/dev/null | head -1 || true)
  if [[ -z "$found" ]]; then
    found=$(find "$project_path" -maxdepth 6 -name "*.apk" 2>/dev/null | grep "/build/outputs/apk/" | xargs ls -t 2>/dev/null | head -1 || true)
  fi
  if [[ -z "$found" ]]; then
    found=$(find "$project_path" -maxdepth 7 -name "*.apk" 2>/dev/null | xargs ls -t 2>/dev/null | head -1 || true)
  fi
  echo "$found"
}

action_build() {
  log_info "Starting Gradle build: ${BOLD}$CONFIG_gradle_task${RESET} in ${C_MUTED}$CONFIG_project_dir${RESET}..."
  cd "$CONFIG_project_dir"

  local gradlew_bin="./gradlew"
  if [[ ! -f "$gradlew_bin" ]]; then
    log_error "No './gradlew' wrapper found in $CONFIG_project_dir!"
    exit 1
  fi

  chmod +x "$gradlew_bin"
  local start_time=$(date +%s)

  if "$gradlew_bin" "$CONFIG_gradle_task" --daemon; then
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_success "Build completed successfully in ${BOLD}${duration}s${RESET}!"
  else
    log_error "Build failed."
    exit 1
  fi
}

action_install() {
  select_device
  log_info "Searching for APK in $CONFIG_project_dir..."
  local apk_file=$(find_built_apk "$CONFIG_project_dir")

  if [[ -z "$apk_file" || ! -f "$apk_file" ]]; then
    log_warn "No APK found. Triggering build first..."
    action_build
    apk_file=$(find_built_apk "$CONFIG_project_dir")
  fi

  if [[ -z "$apk_file" || ! -f "$apk_file" ]]; then
    log_error "Could not find built APK file to install."
    exit 1
  fi

  local apk_size=$(ls -lh "$apk_file" | awk '{print $5}')
  log_info "Installing ${BOLD}$(basename "$apk_file")${RESET} (${C_MUTED}$apk_size${RESET}) to ${C_PRIMARY}$SELECTED_DEVICE${RESET}..."

  if adb_cmd install -r -d "$apk_file"; then
    log_success "App installed successfully!"
    action_launch
  else
    log_error "Installation failed."
    exit 1
  fi
}

action_launch() {
  select_device
  if [[ -z "$CONFIG_package_name" ]]; then
    log_error "package_name is not configured."
    exit 1
  fi

  local component="$CONFIG_package_name"
  if [[ -n "$CONFIG_main_activity" ]]; then
    if [[ "$CONFIG_main_activity" == .* ]]; then
      component="$CONFIG_package_name/$CONFIG_package_name$CONFIG_main_activity"
    else
      component="$CONFIG_package_name/$CONFIG_main_activity"
    fi
  fi

  log_info "Launching ${BOLD}$component${RESET} on ${C_PRIMARY}$SELECTED_DEVICE${RESET}..."
  if [[ "$CONFIG_main_activity" != "" ]]; then
    adb_cmd shell am start -n "$component" -a android.intent.action.MAIN -c android.intent.category.LAUNCHER || \
    adb_cmd shell monkey -p "$CONFIG_package_name" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  else
    adb_cmd shell monkey -p "$CONFIG_package_name" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  fi
  log_success "App launched!"
}

action_restart() {
  select_device
  log_info "Force stopping $CONFIG_package_name..."
  adb_cmd shell am force-stop "$CONFIG_package_name"
  sleep 0.5
  action_launch
}

action_clean() {
  log_info "Running Gradle clean & stopping daemons in ${C_MUTED}$CONFIG_project_dir${RESET}..."
  cd "$CONFIG_project_dir"
  local gradlew_bin="./gradlew"
  if [[ ! -f "$gradlew_bin" ]]; then
    log_error "No './gradlew' wrapper found in $CONFIG_project_dir!"
    exit 1
  fi
  chmod +x "$gradlew_bin"

  "$gradlew_bin" clean || true
  "$gradlew_bin" --stop || true
  log_success "Clean completed & daemons stopped."
}

action_build_release() {
  cd "$CONFIG_project_dir"
  local gradlew_bin="./gradlew"
  if [[ ! -f "$gradlew_bin" ]]; then
    log_error "No './gradlew' wrapper found in $CONFIG_project_dir!"
    return 1
  fi
  chmod +x "$gradlew_bin"

  local r_type="${CONFIG_release_type:-apk}"
  local tasks=()
  case "$r_type" in
    aab|bundle)
      tasks=("bundleRelease")
      ;;
    both|all)
      tasks=("assembleRelease" "bundleRelease")
      ;;
    apk|*)
      tasks=("assembleRelease")
      ;;
  esac

  local cached_pass="$CONFIG_keystore_pass"
  local alias_name="${CONFIG_keystore_alias:-}"

  # If keystore is configured, ensure we have a valid password BEFORE starting Gradle build
  if [[ -n "$CONFIG_keystore_file" && -f "$CONFIG_keystore_file" ]]; then
    local keytool_bin=$(which keytool 2>/dev/null || echo "/usr/bin/keytool")
    while true; do
      if [[ -z "$cached_pass" ]]; then
        echo -en "${C_PRIMARY}Enter Keystore Password for $(basename "$CONFIG_keystore_file"): ${RESET}"
        read -rs cached_pass
        echo ""
      fi

      if [[ -z "$cached_pass" ]]; then
        log_warn "Password cannot be empty."
        continue
      fi

      # Validate password and find alias without triggering set -e
      if [[ -x "$keytool_bin" ]]; then
        local keytool_out=""
        if keytool_out=$("$keytool_bin" -list -keystore "$CONFIG_keystore_file" -storepass "$cached_pass" 2>/dev/null); then
          if [[ -z "$alias_name" ]]; then
            alias_name=$(echo "$keytool_out" | grep "PrivateKeyEntry" | head -1 | cut -d',' -f1 | tr -d ' ' || echo "upload")
            [[ -z "$alias_name" ]] && alias_name="upload"
          fi
          break
        else
          log_error "Incorrect keystore password for $(basename "$CONFIG_keystore_file"). Try again."
          cached_pass=""
        fi
      else
        break
      fi
    done
  fi

  log_info "Starting Release build in ${C_MUTED}$CONFIG_project_dir${RESET}..."
  local start_time=$(date +%s)
  log_info "Running Gradle task(s): ${BOLD}${tasks[*]}${RESET}..."
  if "$gradlew_bin" "${tasks[@]}" --daemon; then
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_success "Release build completed in ${BOLD}${duration}s${RESET}!"
    
    local out_dir=""

    if [[ "$r_type" == "aab" || "$r_type" == "bundle" || "$r_type" == "both" || "$r_type" == "all" ]]; then
      local out_aab=$(find "$CONFIG_project_dir" -maxdepth 6 -name "*.aab" 2>/dev/null | grep "/build/outputs/bundle/release" | xargs ls -t 2>/dev/null | head -1 || true)
      if [[ -n "$out_aab" ]]; then
        # Sign AAB if jarsigner available and keystore provided
        if [[ -n "$CONFIG_keystore_file" && -f "$CONFIG_keystore_file" ]]; then
          log_info "Signing release bundle with ${C_ACCENT}$(basename "$CONFIG_keystore_file")${RESET}..."
          local jarsigner_bin=$(which jarsigner 2>/dev/null || echo "/usr/bin/jarsigner")
          if [[ -x "$jarsigner_bin" ]]; then
            "$jarsigner_bin" -keystore "$CONFIG_keystore_file" \
              -storepass "$cached_pass" \
              ${CONFIG_key_pass:+-keypass "$CONFIG_key_pass"} \
              "$out_aab" "$alias_name" >/dev/null 2>&1 || true
            log_success "Release Bundle signed."
          fi
        fi
        log_info "Release Bundle: ${C_ACCENT}$out_aab${RESET}"
        out_dir="$(dirname "$out_aab")"
      fi
    fi

    if [[ "$r_type" == "apk" || "$r_type" == "both" || "$r_type" == "all" ]]; then
      local raw_apk=$(find "$CONFIG_project_dir" -maxdepth 6 -name "*release*.apk" ! -name "*.tmp.apk" ! -name "*-aligned.apk" 2>/dev/null | grep "/build/outputs/apk/release" | xargs ls -t 2>/dev/null | head -1 || true)
      local final_apk="$raw_apk"

      if [[ -n "$raw_apk" && -n "$CONFIG_keystore_file" && -f "$CONFIG_keystore_file" ]]; then
        # Locate apksigner in SDK
        local apksigner_bin=$(find "$HOME/Library/Android/sdk/build-tools" -name "apksigner" 2>/dev/null | sort -V | tail -1 || true)
        local zipalign_bin=$(find "$HOME/Library/Android/sdk/build-tools" -name "zipalign" 2>/dev/null | sort -V | tail -1 || true)
        
        local apk_dir=$(dirname "$raw_apk")
        local final_target_apk="$apk_dir/app-release.apk"
        local temp_signed_apk="$apk_dir/app-release-signed.tmp.apk"

        log_info "Signing release APK with ${C_ACCENT}$(basename "$CONFIG_keystore_file")${RESET}..."

        local to_sign="$raw_apk"
        if [[ -n "$zipalign_bin" && -x "$zipalign_bin" && "$raw_apk" == *"-unsigned.apk" ]]; then
          local aligned_apk="$apk_dir/app-release-aligned.tmp.apk"
          rm -f "$aligned_apk"
          if "$zipalign_bin" -p -f -v 4 "$raw_apk" "$aligned_apk" >/dev/null 2>&1 && [[ -s "$aligned_apk" ]]; then
            to_sign="$aligned_apk"
          fi
        fi

        if [[ -n "$apksigner_bin" && -x "$apksigner_bin" ]]; then
          rm -f "$temp_signed_apk"
          local sign_success=0

          while [[ $sign_success -eq 0 ]]; do
            local apksign_err=""
            if apksign_err=$("$apksigner_bin" sign --ks "$CONFIG_keystore_file" \
                --ks-pass "pass:$cached_pass" \
                --ks-key-alias "$alias_name" \
                ${CONFIG_key_pass:+--key-pass "pass:$CONFIG_key_pass"} \
                --out "$temp_signed_apk" "$to_sign" 2>&1); then
              sign_success=1
              break
            else
              log_error "APK signing failed."
              echo -en "${C_PRIMARY}Enter Keystore / Key Password for $(basename "$CONFIG_keystore_file"): ${RESET}"
              read -rs cached_pass
              echo ""
            fi
          done

          if [[ $sign_success -eq 1 && -f "$temp_signed_apk" ]]; then
            rm -f "$apk_dir/app-release-aligned.tmp.apk"
            rm -f "$apk_dir/app-release-unsigned.apk"
            rm -f "$final_target_apk"
            mv "$temp_signed_apk" "$final_target_apk"
            final_apk="$final_target_apk"
            log_success "Release APK signed successfully."
          fi
        else
          log_warn "'apksigner' not found in Android SDK. APK left as $raw_apk."
        fi
      fi

      [[ -n "$final_apk" ]] && log_info "Release APK:    ${C_ACCENT}$final_apk${RESET}"
      [[ -n "$final_apk" && -z "$out_dir" ]] && out_dir="$(dirname "$final_apk")"
    fi

    if [[ -n "$out_dir" && -d "$out_dir" ]]; then
      echo ""
      echo -en "${C_PRIMARY}Open release directory in Finder? [Y/n]: ${RESET}"
      read -r open_choice
      open_choice="${open_choice:-Y}"
      if [[ "$open_choice" =~ ^[Yy]$ ]]; then
        open "$out_dir"
      fi
    fi
  else
    log_error "Release build failed."
    return 1
  fi
}

action_import_icons() {
  local p_dir="$CONFIG_project_dir"
  local drawable_dir=""
  for candidate in "$p_dir/app/src/main/res/drawable" "$p_dir/src/main/res/drawable" "$p_dir/res/drawable"; do
    if [[ -d "$candidate" ]]; then
      drawable_dir="$candidate"
      break
    fi
  done

  if [[ -z "$drawable_dir" ]]; then
    log_error "Could not locate 'res/drawable' directory in $p_dir!"
    return 1
  fi

  echo -e "\n${BOLD}${C_PRIMARY}=== Add Material Drawable Icons ===${RESET}"
  echo -e "${C_MUTED}Enter icon name(s) (comma or space separated, e.g. 'device_thermostat, speed, search' or 'e1ff'):${RESET}"
  read -rp "> " icon_input

  if [[ -z "$icon_input" ]]; then
    log_warn "No icon names provided."
    return 0
  fi

  python3 -c "
import sys, os, re, urllib.request, json

project_name = sys.argv[1]
drawable_dir = sys.argv[2]
raw_input = sys.argv[3]

# Split input by comma or whitespace
tokens = [t.strip() for t in re.split(r'[,\\s]+', raw_input) if t.strip()]

if not tokens:
    sys.exit(0)

total = len(tokens)
print(f'\033[90m[INFO] Processing {total} icon(s)...\033[0m')

codepoint_map = {}
def load_codepoints():
    global codepoint_map
    try:
        req = urllib.request.Request('https://fonts.google.com/metadata/icons', headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=5) as resp:
            content = resp.read().decode('utf-8')
            if content.startswith(\")]}'\"):
                content = content[4:].strip()
            data = json.loads(content)
            for item in data.get('icons', []):
                cp_hex = format(item.get('codepoint', 0), 'x').lower()
                codepoint_map[cp_hex] = item.get('name')
                codepoint_map[item.get('name')] = item.get('name')
    except Exception:
        pass

for idx, token in enumerate(tokens, 1):
    # Clean token
    clean_name = token.lower()
    clean_name = re.sub(r'^rounded_', '', clean_name)
    clean_name = re.sub(r'(_24px|_24|\.xml|\.svg)$', '', clean_name)

    # Check if token is hex codepoint (e.g. e1ff)
    if re.match(r'^[0-9a-f]{4,5}$', clean_name):
        if not codepoint_map:
            load_codepoints()
        clean_name = codepoint_map.get(clean_name, clean_name)

    print(f'\033[36m[{idx}/{total}]\033[0m Fetching \033[1m{clean_name}\033[0m...', end=' ', flush=True)

    target_filename = f'rounded_{clean_name}_24.xml'
    target_path = os.path.join(drawable_dir, target_filename)

    urls_to_try = [
        f'https://raw.githubusercontent.com/google/material-design-icons/master/symbols/android/{clean_name}/materialsymbolsrounded/{clean_name}_24px.xml',
        f'https://raw.githubusercontent.com/google/material-design-icons/master/symbols/android/{clean_name}/materialsymbolsrounded/{clean_name}_wght400_24px.xml',
        f'https://raw.githubusercontent.com/google/material-design-icons/master/src/{clean_name}/materialiconsround/24px.xml',
    ]

    xml_content = None
    for url in urls_to_try:
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=5) as resp:
                if resp.status == 200:
                    xml_content = resp.read().decode('utf-8')
                    break
        except Exception:
            continue

    if xml_content:
        if 'android:tint=' not in xml_content:
            xml_content = xml_content.replace('<vector ', '<vector\n    android:tint=\"#000000\" ', 1)
        with open(target_path, 'w') as f:
            f.write(xml_content.strip() + '\n')
        print(f'\033[32m[DONE]\033[0m -> \033[90m{target_filename}\033[0m')
    else:
        print(f'\033[31m[NOT FOUND]\033[0m')
" "$CONFIG_project_name" "$drawable_dir" "$icon_input"
}

ensure_ktlint() {
  local cache_dir="$HOME/.cache/android-build"
  local ktlint_bin="$cache_dir/ktlint"

  if command -v ktlint >/dev/null 2>&1; then
    echo "$(command -v ktlint)"
    return 0
  fi

  if [[ -x "$ktlint_bin" ]]; then
    echo "$ktlint_bin"
    return 0
  fi

  mkdir -p "$cache_dir"
  log_info "Downloading standalone 'ktlint' binary for Kotlin formatting..."
  local ktlint_url="https://github.com/pinterest/ktlint/releases/download/1.5.0/ktlint"
  if curl -sSL "$ktlint_url" -o "$ktlint_bin" && chmod +x "$ktlint_bin"; then
    log_success "ktlint installed to $ktlint_bin"
    echo "$ktlint_bin"
    return 0
  else
    log_error "Failed to download ktlint. You can install it via 'brew install ktlint'."
    return 1
  fi
}

action_format_code() {
  local ktlint_exe
  ktlint_exe=$(ensure_ktlint) || return 1

  echo -e "\n${BOLD}${C_PRIMARY}=== Format & Optimize Kotlin Code ===${RESET}"
  echo -e "  ${BOLD}[1]${RESET} Modified files only (Git diff - fast)"
  echo -e "  ${BOLD}[2]${RESET} Entire project"
  echo -e "  ${BOLD}[3]${RESET} Specific directory or file"
  echo -e "${C_MUTED}──────────────────────────────────────────────────${RESET}"
  read -rp "Select scope [1-3] (default 1): " f_choice
  f_choice="${f_choice:-1}"

  cd "$CONFIG_project_dir"

  case "$f_choice" in
    1)
      local mod_files=()
      while IFS= read -r f; do
        [[ "$f" =~ \.(kt|kts)$ ]] && [[ -f "$CONFIG_project_dir/$f" ]] && mod_files+=("$CONFIG_project_dir/$f")
      done < <(git -C "$CONFIG_project_dir" status --porcelain 2>/dev/null | awk '{print $2}' || true)

      if [[ ${#mod_files[@]} -eq 0 ]]; then
        log_info "No modified Kotlin files to format."
        return 0
      fi

      log_info "Formatting ${#mod_files[@]} modified Kotlin file(s)..."
      "$ktlint_exe" --format "${mod_files[@]}" || true
      log_success "Format complete."
      ;;
    2)
      log_info "Formatting all Kotlin files in $CONFIG_project_name..."
      "$ktlint_exe" --format "**/src/**/*.kt" "**/*.kts" "!**/build/**" "!**/.gradle/**" || true
      log_success "Entire project formatted."
      ;;
    3)
      read -rp "Enter relative directory or file path: " target_input
      if [[ -n "$target_input" && -e "$CONFIG_project_dir/$target_input" ]]; then
        log_info "Formatting '$target_input'..."
        "$ktlint_exe" --format "$CONFIG_project_dir/$target_input" || true
        log_success "Format complete."
      else
        log_warn "Path '$target_input' not found in project."
      fi
      ;;
    *)
      log_warn "Invalid input."
      ;;
  esac
}

action_uninstall() {
  select_device
  log_warn "Uninstalling ${BOLD}$CONFIG_package_name${RESET} from $SELECTED_DEVICE..."
  adb_cmd uninstall "$CONFIG_package_name"
  log_success "Uninstalled."
}

action_mirror() {
  select_device
  if ! command -v scrcpy >/dev/null 2>&1; then
    log_error "'scrcpy' is not installed. Install it via 'brew install scrcpy'."
    exit 1
  fi
  log_info "Starting screen mirror for ${C_PRIMARY}$SELECTED_DEVICE${RESET}..."
  scrcpy -s "$SELECTED_DEVICE" --window-title "$CONFIG_project_name ($SELECTED_DEVICE)" --always-on-top >/dev/null 2>&1 &
  log_success "Mirroring started in background."
}

action_logs() {
  select_device
  if [[ -z "$CONFIG_package_name" ]]; then
    log_error "package_name is not configured for logcat streaming."
    exit 1
  fi

  echo -e "${BOLD}${C_PRIMARY}=== Live Logcat: ${C_ACCENT}$CONFIG_package_name${C_PRIMARY} on ${SELECTED_DEVICE} ===${RESET}"
  echo -e "${C_MUTED}Press Ctrl+C to stop.${RESET}\n"

  # Trap Ctrl+C cleanly
  trap 'echo -e "\n${C_MUTED}Logcat stopped.${RESET}"; exit 0' INT

  # Stream logs and highlight PID/tags/levels
  while true; do
    # Get current PID
    local pid
    pid=$(adb_cmd shell pidof -s "$CONFIG_package_name" 2>/dev/null | tr -d '\r' || true)
    
    if [[ -z "$pid" ]]; then
      # Fallback to ps
      pid=$(adb_cmd shell "ps -A -o PID,NAME 2>/dev/null | grep '$CONFIG_package_name' | awk '{print \$1}'" 2>/dev/null | head -1 | tr -d '\r' || true)
    fi

    if [[ -n "$pid" ]]; then
      echo -e "${C_SUCCESS}Attached to process PID: ${BOLD}$pid${RESET}"
      # Format logcat with PID filter
      adb_cmd logcat -v time --pid="$pid" | while IFS= read -r line; do
        if [[ "$line" =~ ^([0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+)[[:space:]]+([VDIWEF])/([^:]+):[[:space:]]*(.*)$ ]]; then
          local timestamp="${BASH_REMATCH[1]}"
          local level="${BASH_REMATCH[2]}"
          local tag="${BASH_REMATCH[3]}"
          local msg="${BASH_REMATCH[4]}"
          
          local lvl_color="$LOG_I"
          case "$level" in
            V) lvl_color="$LOG_V" ;;
            D) lvl_color="$LOG_D" ;;
            I) lvl_color="$LOG_I" ;;
            W) lvl_color="$LOG_W" ;;
            E) lvl_color="$LOG_E" ;;
            F) lvl_color="$LOG_F" ;;
          esac
          
          printf "${C_MUTED}%s${RESET} ${lvl_color}[%s]${RESET} ${BOLD}%-20s${RESET} : %s\n" "$timestamp" "$level" "$tag" "$msg"
        elif [[ "$line" =~ "FATAL EXCEPTION" || "$line" =~ "AndroidRuntime" || "$line" =~ "Exception" || "$line" =~ "Error" ]]; then
          echo -e "${LOG_E}${line}${RESET}"
        else
          echo -e "${C_MUTED}${line}${RESET}"
        fi
      done || true
      echo -e "${C_WARN}App process ended or crashed. Waiting for restart...${RESET}"
    fi
    sleep 1
  done
}

action_run_all() {
  action_build
  action_install
  action_launch
  echo ""
  action_logs
}

action_sync() {
  log_info "Running Gradle sync & dependency check in ${C_MUTED}$CONFIG_project_dir${RESET}..."
  cd "$CONFIG_project_dir"
  local gradlew_bin="./gradlew"
  if [[ ! -f "$gradlew_bin" ]]; then
    log_error "No './gradlew' wrapper found in $CONFIG_project_dir!"
    exit 1
  fi
  chmod +x "$gradlew_bin"
  if "$gradlew_bin" help --daemon >/dev/null && "$gradlew_bin" tasks --daemon >/dev/null; then
    log_success "Gradle sync & daemon check complete!"
  else
    log_error "Gradle sync failed."
    exit 1
  fi
}

find_app_gradle_file() {
  local p="$CONFIG_project_dir"
  if [[ -f "$p/app/build.gradle.kts" ]]; then
    echo "$p/app/build.gradle.kts"
  elif [[ -f "$p/app/build.gradle" ]]; then
    echo "$p/app/build.gradle"
  elif [[ -f "$p/build.gradle.kts" ]]; then
    echo "$p/build.gradle.kts"
  elif [[ -f "$p/build.gradle" ]]; then
    echo "$p/build.gradle"
  fi
}

has_optimized_build_config() {
  local gradle_file
  gradle_file=$(find_app_gradle_file)
  if [[ -n "$gradle_file" && -f "$gradle_file" ]]; then
    if grep -q "optimized dev build" "$gradle_file"; then
      return 0
    fi
  fi
  return 1
}

action_optimized_debug() {
  local gradle_file
  gradle_file=$(find_app_gradle_file)

  if [[ -z "$gradle_file" || ! -f "$gradle_file" ]]; then
    log_error "Could not locate app build.gradle(.kts) file."
    exit 1
  fi

  if ! grep -q "optimized dev build" "$gradle_file"; then
    log_error "Optimized dev build pattern not found in $gradle_file."
    exit 1
  fi

  log_info "Enabling optimized dev build configuration in $(basename "$gradle_file")..."

  # Create backup
  cp "$gradle_file" "$gradle_file.bak"

  # Trap any exit/interrupt/error to always restore the original file
  cleanup_optimized_block() {
    if [[ -f "$gradle_file.bak" ]]; then
      log_info "Restoring $(basename "$gradle_file") comments..."
      mv -f "$gradle_file.bak" "$gradle_file" 2>/dev/null || true
    fi
  }
  trap cleanup_optimized_block EXIT INT TERM HUP

  # Uncomment the block between "optimized dev build" and "end"
  python3 -c "
import sys, re

filepath = sys.argv[1]
with open(filepath, 'r') as f:
    content = f.read()

# Pattern matching commented block
pattern = r'(//\s*optimized dev build\n)(.*?)(//\s*end)'
def uncomment_block(match):
    header = match.group(1)
    body = match.group(2)
    footer = match.group(3)
    uncommented_body = '\n'.join([re.sub(r'^\s*//\s?', '          ', line) if line.strip().startswith('//') else line for line in body.splitlines()])
    return f'{header}{uncommented_body}\n{footer}'

new_content = re.sub(pattern, uncomment_block, content, flags=re.DOTALL)
with open(filepath, 'w') as f:
    f.write(new_content)
" "$gradle_file"

  log_info "Building & installing optimized debug..."
  local build_failed=0
  action_build || build_failed=1

  if [[ $build_failed -eq 0 ]]; then
    action_install || build_failed=1
  fi

  # Explicitly restore and remove trap
  cleanup_optimized_block
  trap - EXIT INT TERM HUP

  if [[ $build_failed -ne 0 ]]; then
    log_error "Optimized debug build/install encountered errors."
    exit 1
  else
    log_success "Optimized debug build & install complete!"
  fi
}

action_open_editor() {
  local target_path="${CONFIG_workspace_file:-$CONFIG_project_dir}"
  if [[ -n "$CONFIG_workspace_file" && -f "$CONFIG_workspace_file" ]]; then
    target_path="$CONFIG_workspace_file"
  elif [[ -n "$CONFIG_project_dir" && -d "$CONFIG_project_dir" ]]; then
    target_path="$CONFIG_project_dir"
  fi

  local agy_bin="/Applications/Antigravity IDE.app/Contents/Resources/app/bin/antigravity-ide"
  log_info "Opening ${C_ACCENT}$target_path${RESET} in Antigravity IDE..."

  if [[ -f "$agy_bin" ]]; then
    "$agy_bin" "$target_path" >/dev/null 2>&1 &
    log_success "Opened in Antigravity IDE."
  else
    open -a "Antigravity IDE" "$target_path" 2>/dev/null || open "$target_path"
    log_success "Opened."
  fi
}

action_wireless_connect() {
  echo -e "\n${BOLD}${C_PRIMARY}=== Wireless ADB Pair & Connect ===${RESET}"
  echo -e "1. On phone: Settings -> Developer Options -> Wireless Debugging."
  echo ""
  read -rp "Do you need to pair first? (y/N): " need_pair
  if [[ "$need_pair" =~ ^[Yy]$ ]]; then
    read -rp "Enter Phone IP:PORT for pairing: " pair_addr
    read -rp "Enter 6-digit Pairing Code: " pair_code
    adb pair "$pair_addr" "$pair_code"
  fi

  echo ""
  read -rp "Enter Phone IP:PORT to connect: " conn_addr
  if [[ -n "$conn_addr" ]]; then
    adb connect "$conn_addr"
    log_success "Connected. Checking active devices..."
    adb devices -l
  fi
}

# Helper to extract live project info for dashboard
get_project_details() {
  local p_dir="$CONFIG_project_dir"
  PROJECT_GIT_BRANCH=""
  PROJECT_SDK=""
  PROJECT_VERSION=""

  if [[ -d "$p_dir/.git" ]]; then
    PROJECT_GIT_BRANCH=$(git -C "$p_dir" branch --show-current 2>/dev/null || echo "")
  fi

  local gradle_file=$(find_app_gradle_file)
  if [[ -n "$gradle_file" && -f "$gradle_file" ]]; then
    local compile_sdk=$(grep -E "compileSdk[[:space:]]*=[[:space:]]*[0-9]+" "$gradle_file" | head -1 | grep -oE "[0-9]+" || echo "")
    local v_name=$(grep -E "versionName[[:space:]]*=[[:space:]]*\"" "$gradle_file" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "")
    local v_code=$(grep -E "versionCode[[:space:]]*=[[:space:]]*[0-9]+" "$gradle_file" | head -1 | grep -oE "[0-9]+" || echo "")
    
    [[ -n "$compile_sdk" ]] && PROJECT_SDK="SDK $compile_sdk"
    if [[ -n "$v_name" ]]; then
      PROJECT_VERSION="v$v_name"
      [[ -n "$v_code" ]] && PROJECT_VERSION="$PROJECT_VERSION ($v_code)"
    fi
  fi
}

# --- Interactive TUI Dashboard ---
show_dashboard() {
  select_device
  while true; do
    get_project_details
    clear
    echo -e "${BOLD}${C_PRIMARY}android-build${RESET}"
    echo -e "${C_MUTED}──────────────────────────────────────────────────${RESET}"
    echo -e "  ${BOLD}Project:${RESET}   ${C_ACCENT}${CONFIG_project_name}${RESET} ${C_MUTED}${PROJECT_VERSION}${RESET}"
    echo -e "  ${BOLD}Package:${RESET}   ${C_PRIMARY}${CONFIG_package_name}${RESET}"
    if [[ -n "$PROJECT_GIT_BRANCH" || -n "$PROJECT_SDK" ]]; then
      echo -e "  ${BOLD}Branch:${RESET}    ${C_SUCCESS}${PROJECT_GIT_BRANCH:-main}${RESET}  ${C_MUTED}${PROJECT_SDK}${RESET}"
    fi
    echo -e "  ${BOLD}Device:${RESET}    ${C_SUCCESS}${SELECTED_DEVICE}${RESET}"
    echo -e "  ${BOLD}Task:${RESET}      ${C_WARN}${CONFIG_gradle_task}${RESET} [${CONFIG_build_variant}]"
    echo -e "${C_MUTED}──────────────────────────────────────────────────${RESET}"
    
    # Section 1: Build & Run
    echo -e "  ${BOLD}[R]${RESET} Run & Debug"
    echo -e "  ${BOLD}[I]${RESET} Install only"
    if has_optimized_build_config; then
      echo -e "  ${BOLD}[O]${RESET} Optimized debug"
    fi
    echo -e "  ${BOLD}[L]${RESET} Logcat"
    echo ""

    # Section 2: App Control
    echo -e "  ${BOLD}[F]${RESET} Force stop"
    echo -e "  ${BOLD}[S]${RESET} Start"
    echo ""

    # Section 3: Tools & Builds
    echo -e "  ${BOLD}[M]${RESET} Mirror"
    echo -e "  ${BOLD}[G]${RESET} Gradle Sync"
    echo -e "  ${BOLD}[T]${RESET} Format code"
    echo -e "  ${BOLD}[C]${RESET} Clean build"
    echo -e "  ${BOLD}[B]${RESET} Release build"
    echo -e "  ${BOLD}[Y]${RESET} Import icons"
    echo ""

    # Section 4: Device & Project
    echo -e "  ${BOLD}[W]${RESET} Wireless ADB"
    echo -e "  ${BOLD}[D]${RESET} Switch Device"
    echo -e "  ${BOLD}[P]${RESET} Switch Project"
    echo ""

    # Section 5: Editor & Quit
    echo -e "  ${BOLD}[E]${RESET} Open in editor"
    echo -e "  ${BOLD}[Q]${RESET} Quit"
    echo -e "${C_MUTED}──────────────────────────────────────────────────${RESET}"
    
    read -rp "> " opt
    case "$opt" in
      r|R|1) echo ""; action_run_all; read -rp "Press Enter to return..." ;;
      i|I|2) echo ""; action_build && action_install; read -rp "Press Enter to return..." ;;
      o|O)
        if has_optimized_build_config; then
          echo ""; action_optimized_debug; read -rp "Press Enter to return..."
        else
          log_warn "Optimized dev build is not configured in this project." ; sleep 1
        fi
        ;;
      l|L|3) echo ""; action_logs; read -rp "Press Enter to return..." ;;
      f|F|5) echo ""; action_stop; sleep 1 ;;
      s|S|4) echo ""; action_launch; sleep 1 ;;
      m|M|7) echo ""; action_mirror; sleep 1 ;;
      g|G) echo ""; action_sync; read -rp "Press Enter to return..." ;;
      t|T) echo ""; action_format_code; read -rp "Press Enter to return..." ;;
      c|C|6) echo ""; action_clean; read -rp "Press Enter to return..." ;;
      b|B) echo ""; action_build_release; read -rp "Press Enter to return..." ;;
      y|Y) echo ""; action_import_icons; read -rp "Press Enter to return..." ;;
      w|W|8) echo ""; action_wireless_connect; read -rp "Press Enter to return..." ;;
      d|D) select_device "true" ;;
      p|P)
        select_project_interactive
        load_config "${CONFIG_FILE:-}"
        select_device
        ;;
      e|E) action_open_editor; sleep 1 ;;
      q|Q) exit 0 ;;
      *) log_warn "Invalid input." ; sleep 1 ;;
    esac
  done
}

# --- Help & Parsing ---
show_help() {
  echo -e "${BOLD}android-build${RESET}"
  echo -e "Usage: $0 [command] [config_file] [options]\n"
  echo -e "${BOLD}Commands:${RESET}"
  echo -e "  (none)              Launch interactive menu"
  echo -e "  run (R)             Build, install, launch, and stream logs"
  echo -e "  install (I)         Build and install APK"
  echo -e "  opt (O)             Build and install with optimized dev settings"
  echo -e "  logs (L)            Stream colored logcat filtered by package PID"
  echo -e "  stop (F)            Force stop the application"
  echo -e "  start (S)           Launch main activity"
  echo -e "  format (T)          Format Kotlin code & optimize imports"
  echo -e "  clean (C)           Run Gradle clean & stop daemons"
  echo -e "  release (B)         Build release bundle / APK"
  echo -e "  icons (Y)           Import Material Symbols drawables"
  echo -e "  mirror (M)          Launch scrcpy screen mirroring"
  echo -e "  sync (G)            Run Gradle sync & daemon check"
  echo -e "  wifi (W)            Wireless ADB connection helper"
  echo -e "  devices (D)         List connected devices"
  echo -e "  project (P)         Switch active project"
  echo -e "  editor (E)          Open workspace / project in Antigravity IDE"
  echo -e "  help                Show this help message\n"
  echo -e "${BOLD}Examples:${RESET}"
  echo -e "  $0                                   # Interactive menu"
  echo -e "  $0 run essentials.android.config     # Complete run for Essentials"
  echo -e "  $0 opt essentials.android.config     # Optimized debug build & install"
  echo -e "  $0 format                            # Format & optimize Kotlin code"
  echo -e "  $0 icons                             # Download & add drawables"
  echo -e "  $0 clean                             # Gradle clean & daemon restart"
  echo -e "  $0 release essentials.android.config # Build release bundle"
  echo -e "  $0 logs airsync.android.config       # Live logs for AirSync"
  echo -e "  $0 editor                            # Open project in Antigravity IDE"
  echo -e "  $0 mirror                            # Mirror screen of active device"
}

# --- CLI Entry Point ---
if [[ $# -eq 0 ]]; then
  load_config ""
  show_dashboard
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help|help)
      show_help
      exit 0
      ;;
    run|build|install|opt|optimized|sync|format|fmt|clean|release|bundle|icons|icon|launch|restart|stop|uninstall|logs|mirror|devices|wifi|editor|open)
      SUBCOMMAND="$1"
      shift
      ;;
    *.config)
      CONFIG_FILE="$1"
      shift
      ;;
    *)
      if [[ -z "$CONFIG_FILE" && -f "$1" ]]; then
        CONFIG_FILE="$1"
      elif [[ -z "$CONFIG_FILE" && -f "$SCRIPT_DIR/$1" ]]; then
        CONFIG_FILE="$SCRIPT_DIR/$1"
      else
        ARGS+=("$1")
      fi
      shift
      ;;
  esac
done

load_config "${CONFIG_FILE:-}"

case "${SUBCOMMAND:-}" in
  run)
    action_run_all
    ;;
  build)
    action_build
    ;;
  install)
    action_install
    ;;
  opt|optimized)
    action_optimized_debug
    ;;
  sync)
    action_sync
    ;;
  format|fmt)
    action_format_code
    ;;
  clean)
    action_clean
    ;;
  release|bundle)
    action_build_release
    ;;
  icons|icon)
    action_import_icons
    ;;
  launch|start)
    action_launch
    ;;
  restart)
    action_restart
    ;;
  stop)
    action_stop
    ;;
  uninstall)
    action_uninstall
    ;;
  logs)
    action_logs
    ;;
  mirror)
    action_mirror
    ;;
  devices)
    check_adb
    get_connected_devices
    ;;
  wifi)
    action_wireless_connect
    ;;
  editor|open)
    action_open_editor
    ;;
  "")
    show_dashboard
    ;;
  *)
    log_error "Unknown command '$SUBCOMMAND'. Use '$0 help' for available commands."
    exit 1
    ;;
esac

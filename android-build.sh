#!/usr/bin/env bash
# ==============================================================================
# Android Developer CLI & TUI System (dev-android.sh)
# Fast, lightweight Android Studio replacement for building, deploying,
# launching, debugging, and live logcat filtering on physical devices.
# ==============================================================================

set -euo pipefail
shopt -s extglob
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *UTF-8*|*utf8*|*UTF8*) ;;
  *) export LC_CTYPE=UTF-8 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG="essentials.android.config"
DEFAULT_TELEGRAM_CHAT_ID="-1001653455300"
DEFAULT_TELEGRAM_TOPIC_ID="71368"

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

# --- Shared TUI helpers ---
UI_W=60
UI_LINE_W=""
UI_LINE=""
UI_ANSI_RE='\\033\[+([0-9;])m'

ui_refresh_width() {
  local cols
  cols=$(tput cols 2>/dev/null || echo 80)
  UI_W=$((cols - 2))
  (( UI_W > 74 )) && UI_W=74
  (( UI_W < 46 )) && UI_W=46
  if [[ "$UI_LINE_W" != "$UI_W" ]]; then
    printf -v UI_LINE '%*s' "$UI_W" ''
    UI_LINE="${UI_LINE// /─}"
    UI_LINE_W="$UI_W"
  fi
  return 0
}

plain_text() { printf '%s' "${1//$UI_ANSI_RE/}"; }

print_divider() { echo -e "  ${C_MUTED}${UI_LINE:0:$((UI_W - 2))}${RESET}"; }

box_top() {
  local fill=$((UI_W - 5 - ${#1}))
  printf '%b\n' "${C_MUTED}╭─${RESET} ${BOLD}${C_PRIMARY}$1${RESET} ${C_MUTED}${UI_LINE:0:$fill}╮${RESET}"
}

box_bottom() { printf '%b\n' "${C_MUTED}╰${UI_LINE:0:$((UI_W - 2))}╯${RESET}"; }

box_row() {
  local left="$1" right="${2:-}"
  local pl="${left//$UI_ANSI_RE/}" pr="${right//$UI_ANSI_RE/}"
  local pad=$((UI_W - 4 - ${#pl} - ${#pr}))
  (( pad < 1 )) && pad=1
  printf '%b%*s%b\n' "${C_MUTED}│${RESET} $left" "$pad" '' "$right ${C_MUTED}│${RESET}"
}

print_header() {
  ui_refresh_width
  echo ""
  box_top "$1"
  box_row "${2:-}" "${3:-}"
  box_bottom
}

print_section() {
  local fill=$((UI_W - 5 - ${#1}))
  printf '%b\n' "  ${C_MUTED}${BOLD}$1${RESET} ${C_MUTED}${UI_LINE:0:$fill}${RESET}"
}

print_menu_item() {
  local label="$2" plain label_pad key chevron=""
  [[ -n "${4:-}" ]] && chevron=1
  plain="${label//$UI_ANSI_RE/}${chevron:+ ›}"
  printf -v label_pad '%*s' "$((28 - ${#plain}))" ''
  (( ${#plain} >= 28 )) && label_pad=" "
  printf -v key '%-2s' "$1"
  printf '%b\n' "  \033[48;5;238m${C_PRIMARY}${BOLD} ${key} ${RESET}  ${label}${chevron:+ ${C_ACCENT}›${RESET}}${label_pad}${C_MUTED}${3:-}${RESET}"
}

print_back_hint() { echo -e "  ${C_MUTED}Esc${RESET} ${C_MUTED}go back${RESET}"; }

trim() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Reads the rest of an escape sequence into REST; empty after ~0.1s means a bare Esc (bash 3.2 has no fractional read timeout).
read_esc_tail() {
  local saved
  saved="$(stty -g 2>/dev/null)" || { REST=""; return 0; }
  stty -icanon min 0 time 1 2>/dev/null
  REST="$(dd bs=1 count=2 2>/dev/null)" || true
  stty "$saved" 2>/dev/null
}

# Reads one key into KEY_KIND (enter|esc|back|char|ignored) and KEY.
read_key() {
  KEY=""
  KEY_KIND="char"
  IFS= read -rsn1 KEY || { KEY_KIND="esc"; return 0; }
  case "$KEY" in
    "") KEY_KIND="enter" ;;
    $'\e')
      read_esc_tail
      if [[ -z "$REST" ]]; then KEY_KIND="esc"; else KEY_KIND="ignored"; fi
      ;;
    $'\x7f'|$'\b') KEY_KIND="back" ;;
  esac
}

# Reads a line into INPUT_LINE; returns 1 when cancelled with Esc.
read_line_esc() {
  INPUT_LINE=""
  echo -en "$1"
  while true; do
    read_key
    case "$KEY_KIND" in
      enter) echo ""; return 0 ;;
      esc) echo ""; return 1 ;;
      ignored) ;;
      back)
        if [[ -n "$INPUT_LINE" ]]; then
          INPUT_LINE="${INPUT_LINE%?}"
          echo -en "\b \b"
        fi
        ;;
      *) INPUT_LINE+="$KEY"; printf '%s' "$KEY" ;;
    esac
  done
}

# Prompts for a non-empty value into ASK_RESULT; returns 1 when empty or cancelled.
ask_value() {
  ASK_RESULT=""
  read_line_esc "$1 (Esc to cancel): " || return 1
  ASK_RESULT="$(trim "$INPUT_LINE")"
  [[ -n "$ASK_RESULT" ]]
}

pause_return() { read -rp "Press Enter to return..." || true; }

run_and_pause() {
  echo ""
  "$@" || true
  pause_return
}

require_gradlew() {
  cd "$CONFIG_project_dir" || return 1
  GRADLEW="./gradlew"
  if [[ ! -f "$GRADLEW" ]]; then
    log_error "No './gradlew' wrapper found in $CONFIG_project_dir!"
    return 1
  fi
  chmod +x "$GRADLEW"
}

# Prints why a keystore file can't be used. Returns 1 when missing, 2 when it exists but can't be read.
keystore_access_error() {
  local f="$1" err=""
  if ! err=$(stat "$f" 2>&1 >/dev/null); then
    if [[ "$err" == *"Operation not permitted"* || "$err" == *"Permission denied"* ]]; then
      echo "can't be accessed (macOS may be blocking this terminal from that folder: allow it under System Settings > Privacy & Security > Files and Folders, or Full Disk Access)"
      return 2
    fi
    echo "was not found"
    return 1
  fi
  if [[ ! -r "$f" ]] || ! head -c 1 "$f" >/dev/null 2>&1; then
    echo "can't be read (check the file permissions, or macOS blocking this terminal from that folder)"
    return 2
  fi
  return 0
}

# Tells a wrong password apart from every other keytool/apksigner/jarsigner failure.
classify_keystore_error() {
  case "$1" in
    *"password was incorrect"*|*"ampered with"*|*"Cannot recover key"*|*"Wrong password"*|*"wrong password"*) echo password ;;
    *"Permission denied"*|*"Operation not permitted"*|*"No such file"*|*"AccessDenied"*|*"NoSuchFile"*|*"FileNotFound"*) echo access ;;
    *"Unable to locate a Java Runtime"*|*"JAVA_HOME"*) echo java ;;
    *) echo other ;;
  esac
}

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

check_is_wear_project() {
  local p_name="${1:-}"
  local cfg_file="${2:-}"
  local p_dir="${3:-}"

  if [[ "$p_name" =~ [Ww]ear || "$cfg_file" =~ [Ww]ear || "$cfg_file" =~ schedule ]]; then
    return 0
  fi

  if [[ -n "$p_dir" && -d "$p_dir" ]]; then
    if grep -rq --include="*Manifest*.xml" --exclude-dir=build --exclude-dir=.git --exclude-dir=.gradle --exclude-dir=node_modules "android.hardware.type.watch" "$p_dir" 2>/dev/null; then
      return 0
    fi
  fi

  return 1
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
  print_divider
  echo -e "Available Projects:"
  local i=1
  for cfg in "${config_files[@]}"; do
    local p_name=$(grep -E "^[[:space:]]*project_name[[:space:]]*=" "$cfg" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
    [[ -z "$p_name" ]] && p_name=$(basename "$cfg" .android.config)
    local p_pkg=$(grep -E "^[[:space:]]*package_name[[:space:]]*=" "$cfg" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
    local p_dir=$(grep -E "^[[:space:]]*project_dir[[:space:]]*=" "$cfg" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
    
    local type_badge=""
    if check_is_wear_project "$p_name" "$cfg" "$p_dir"; then
      type_badge=" ${C_ACCENT}[WearOS]${RESET}"
    else
      type_badge=" ${C_PRIMARY}[Phone]${RESET}"
    fi

    printf "  ${BOLD}[%d]${RESET} %-24s%b ${C_MUTED}(%s)${RESET}\n" "$i" "$p_name" "$type_badge" "$p_pkg"
    ((i++))
  done
  print_divider
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
    CONFIG_release_flavors=$(get_config_val "release_flavors")
    CONFIG_keystore_file=$(get_config_val "keystore_file")
    CONFIG_keystore_alias=$(get_config_val "keystore_alias")
    CONFIG_keystore_pass=$(get_config_val "keystore_pass")
    CONFIG_key_pass=$(get_config_val "key_pass")
    CONFIG_apk_path=$(get_config_val "apk_path")
    CONFIG_target_device=$(get_config_val "target_device")
    CONFIG_log_tags=$(get_config_val "log_tags")
    CONFIG_show_run_debug=$(get_config_val "show_run_debug" "false")
    CONFIG_java_home=$(get_config_val "java_home")
    CONFIG_telegram_chat_id=$(get_config_val "telegram_chat_id" "$DEFAULT_TELEGRAM_CHAT_ID")
    CONFIG_telegram_topic_id=$(get_config_val "telegram_topic_id" "$DEFAULT_TELEGRAM_TOPIC_ID")
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
    CONFIG_release_flavors="${CONFIG_release_flavors:-}"
    CONFIG_keystore_file="${CONFIG_keystore_file:-}"
    CONFIG_keystore_alias="${CONFIG_keystore_alias:-}"
    CONFIG_keystore_pass="${CONFIG_keystore_pass:-}"
    CONFIG_key_pass="${CONFIG_key_pass:-}"
    CONFIG_apk_path="${CONFIG_apk_path:-}"
    CONFIG_target_device="${CONFIG_target_device:-}"
    CONFIG_log_tags="${CONFIG_log_tags:-}"
    CONFIG_show_run_debug="${CONFIG_show_run_debug:-false}"
    CONFIG_java_home="${CONFIG_java_home:-}"
    CONFIG_telegram_chat_id="${CONFIG_telegram_chat_id:-$DEFAULT_TELEGRAM_CHAT_ID}"
    CONFIG_telegram_topic_id="${CONFIG_telegram_topic_id:-$DEFAULT_TELEGRAM_TOPIC_ID}"
  fi

  if [[ -n "$CONFIG_java_home" && -d "$CONFIG_java_home" ]]; then
    export JAVA_HOME="$CONFIG_java_home"
    export PATH="$JAVA_HOME/bin:$PATH"
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

discover_and_connect_mdns() {
  local mdns_output
  mdns_output=$(adb mdns services 2>/dev/null | grep -E "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+" || true)
  if [[ -n "$mdns_output" ]]; then
    log_info "Discovered wireless ADB device(s) via mDNS:"
    local auto_connected=0
    while IFS= read -r s_line; do
      local s_name=$(echo "$s_line" | awk '{print $1}')
      local s_addr=$(echo "$s_line" | awk '{print $NF}')
      if [[ -n "$s_addr" ]]; then
        log_info "Connecting to ${BOLD}$s_name${RESET} ($s_addr)..."
        if adb connect "$s_addr" 2>/dev/null | grep -qi "connected"; then
          log_success "Connected to $s_addr."
          auto_connected=1
        fi
      fi
    done <<< "$mdns_output"

    if [[ $auto_connected -eq 1 ]]; then
      sleep 0.5
      return 0
    fi
  fi
  return 1
}

select_device() {
  local force="${1:-false}"
  check_adb
  local devices_output
  devices_output=$(get_connected_devices)
  
  if [[ -z "$devices_output" ]]; then
    # Try mDNS auto-discovery first
    if discover_and_connect_mdns; then
      devices_output=$(get_connected_devices)
    fi

    # If still no device connected, prompt for Wi-Fi ADB IP:PORT
    if [[ -z "$devices_output" ]]; then
      echo -e "\n${BOLD}${C_PRIMARY}No connected Android devices found.${RESET}"
      echo -en "${C_PRIMARY}Connect via Wi-Fi ADB? (Enter IP:PORT or press Enter to skip): ${RESET}"
      read -r wifi_addr
      if [[ -n "$wifi_addr" ]]; then
        adb connect "$wifi_addr"
        sleep 0.5
        devices_output=$(get_connected_devices)
      fi

      if [[ -z "$devices_output" ]]; then
        log_error "No Android device connected."
        echo -e "${C_MUTED}Tip: Turn on Wireless Debugging on your phone or plug in via USB.${RESET}"
        exit 1
      fi
    fi
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
  found=$(find "$project_path" -maxdepth 8 -name "*-${CONFIG_build_variant}.apk" 2>/dev/null | grep "/build/outputs/apk/" | xargs ls -t 2>/dev/null | head -1 || true)
  if [[ -z "$found" ]]; then
    found=$(find "$project_path" -maxdepth 8 -name "*.apk" 2>/dev/null | grep "/build/outputs/apk/" | xargs ls -t 2>/dev/null | head -1 || true)
  fi
  if [[ -z "$found" ]]; then
    found=$(find "$project_path" -maxdepth 7 -name "*.apk" 2>/dev/null | xargs ls -t 2>/dev/null | head -1 || true)
  fi
  echo "$found"
}

# --- Mac stats during Gradle builds ---
mac_thermal_state() {
  local therm limit
  therm=$(pmset -g therm 2>/dev/null || true)
  limit=$(echo "$therm" | grep -oE "CPU_Speed_Limit[[:space:]]*=[[:space:]]*[0-9]+" | grep -oE "[0-9]+$" || true)
  if [[ -n "$limit" && "$limit" -lt 100 ]]; then
    echo "Throttled ${limit}%"
  elif echo "$therm" | grep -qiE "thermal warning level[^0-9]*[1-9]"; then
    echo "Warm"
  else
    echo "Nominal"
  fi
}

# Prints: thermal|load|cpus|mem_free_pct|java_cpu|java_rss_mb
mac_stats_snapshot() {
  local thermal load cpus mem java
  thermal=$(mac_thermal_state)
  load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
  cpus=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
  mem=$(memory_pressure -Q 2>/dev/null | grep -oE "[0-9]+%" | tr -d '%' || true)
  java=$(ps -axo pcpu=,rss=,comm= 2>/dev/null | awk '$3 ~ /java$/ { c += $1; r += $2 } END { printf "%.0f|%.0f", c, r / 1024 }')
  echo "${thermal}|${load}|${cpus}|${mem}|${java}"
}

run_gradle_with_stats() {
  if [[ ! -t 1 ]]; then
    "$@"
    return $?
  fi

  local work fifo status_file
  work=$(mktemp -d)
  fifo="$work/out"
  status_file="$work/status"
  mkfifo "$fifo"

  (
    "$@" 2>&1 | while IFS= read -r line || [[ -n "$line" ]]; do printf '%s\n' "$line"; done
    echo "${PIPESTATUS[0]}" > "$status_file"
    printf '\001DONE\n'
  ) > "$fifo" &
  local gradle_pid=$!
  ( while true; do printf '\001TICK\n'; sleep 2; done ) > "$fifo" 2>/dev/null &
  local tick_pid=$!
  disown "$tick_pid" 2>/dev/null || true

  local start snap="" status_text="" line
  local worst="Nominal" peak_load=0 peak_rss=0
  start=$(date +%s)

  cleanup_stats() {
    kill "$tick_pid" "$gradle_pid" 2>/dev/null || true
    printf '\r\033[2K'
    rm -rf "$work"
  }
  trap 'cleanup_stats; trap - INT; kill -INT $$' INT

  draw_status() {
    local cols thermal load cpus mem jcpu jrss text
    cols=$(tput cols 2>/dev/null || echo 80)
    IFS='|' read -r thermal load cpus mem jcpu jrss <<< "$snap"
    text=" ⏱ $(( $(date +%s) - start ))s  Thermal ${thermal:-?}  Load ${load:-?}/${cpus:-?}  Mem free ${mem:-?}%  Java ${jcpu:-0}% CPU · ${jrss:-0} MB "
    (( ${#text} > cols - 4 )) && text="${text:0:$(( cols - 4 ))}"
    local color="$C_SUCCESS"
    [[ "${thermal:-Nominal}" != "Nominal" ]] && color="$C_WARN"
    [[ "${thermal:-}" == Throttled* ]] && color="$C_ERROR"
    printf '\r\033[2K%b%s%b' "${C_BG_CARD}${color}" "$text" "$RESET"
  }

  exec 3< "$fifo"
  while IFS= read -r line <&3; do
    case "$line" in
      $'\001DONE') break ;;
      $'\001TICK')
        snap=$(mac_stats_snapshot)
        local t l r
        IFS='|' read -r t l _ _ _ r <<< "$snap"
        awk -v a="$l" -v b="$peak_load" 'BEGIN { exit !(a > b) }' && peak_load="$l"
        (( ${r:-0} > peak_rss )) && peak_rss="${r:-0}"
        [[ "$t" != "Nominal" ]] && worst="$t"
        ;;
      *) printf '\r\033[2K%s\n' "$line" ;;
    esac
    draw_status
  done
  exec 3<&-

  kill "$tick_pid" 2>/dev/null || true
  wait "$gradle_pid" 2>/dev/null || true
  local status=1
  [[ -s "$status_file" ]] && status=$(cat "$status_file")
  trap - INT
  printf '\r\033[2K'
  rm -rf "$work"
  echo -e "${C_MUTED}Mac during build: thermal ${worst}, peak load ${peak_load}, peak Java memory ${peak_rss} MB${RESET}"
  return "$status"
}

action_build() {
  log_info "Starting Gradle build: ${BOLD}$CONFIG_gradle_task${RESET} in ${C_MUTED}$CONFIG_project_dir${RESET}..."
  cd "$CONFIG_project_dir"

  require_gradlew || return 1
  local gradlew_bin="$GRADLEW"
  local start_time=$(date +%s)

  if run_gradle_with_stats "$gradlew_bin" "$CONFIG_gradle_task" --daemon; then
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_success "Build completed successfully in ${BOLD}${duration}s${RESET}!"
    return 0
  else
    log_error "Build failed."
    return 1
  fi
}

action_install() {
  select_device
  log_info "Searching for APK in $CONFIG_project_dir..."
  local apk_file=$(find_built_apk "$CONFIG_project_dir")

  if [[ -z "$apk_file" || ! -f "$apk_file" ]]; then
    log_warn "No APK found. Triggering build first..."
    if ! action_build; then
      return 1
    fi
    apk_file=$(find_built_apk "$CONFIG_project_dir")
  fi

  if [[ -z "$apk_file" || ! -f "$apk_file" ]]; then
    log_error "Could not find built APK file to install."
    return 1
  fi

  local apk_size=$(ls -lh "$apk_file" | awk '{print $5}')
  log_info "Installing ${BOLD}$(basename "$apk_file")${RESET} (${C_MUTED}$apk_size${RESET}) to ${C_PRIMARY}$SELECTED_DEVICE${RESET}..."

  if adb_cmd install -r -d "$apk_file"; then
    log_success "App installed successfully!"
    action_launch
    return 0
  else
    log_error "Installation failed."
    return 1
  fi
}

action_launch() {
  select_device
  if [[ -z "$CONFIG_package_name" ]]; then
    log_error "package_name is not configured."
    return 1
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

action_stop() {
  select_device
  log_info "Force stopping $CONFIG_package_name..."
  adb_cmd shell am force-stop "$CONFIG_package_name"
  log_success "App stopped."
}

action_restart() {
  action_stop
  sleep 0.5
  action_launch
}

action_clean() {
  log_info "Running Gradle clean & stopping daemons in ${C_MUTED}$CONFIG_project_dir${RESET}..."
  cd "$CONFIG_project_dir"
  require_gradlew || return 1
  local gradlew_bin="$GRADLEW"

  "$gradlew_bin" clean || true
  "$gradlew_bin" --stop || true
  log_success "Clean completed & daemons stopped."
}

# Builds release artifacts. With `release_flavors` set in the config, asks which flavor(s) to build.
action_build_release() {
  local flavors=()
  if [[ -z "${CONFIG_release_flavors:-}" ]]; then
    flavors=("")
  else
    local all_flavors=()
    IFS=',' read -r -a all_flavors <<< "$CONFIG_release_flavors"
    if (( ${#all_flavors[@]} == 1 )); then
      flavors=("${all_flavors[0]}")
    else
      echo -e "\n${BOLD}${C_PRIMARY}=== Release flavor ===${RESET}"
      local i=1
      for f in "${all_flavors[@]}"; do
        echo -e "  ${BOLD}[$i]${RESET} $f"
        i=$((i + 1))
      done
      echo -e "  ${BOLD}[A]${RESET} all"
      echo -en "${C_PRIMARY}Choose [A]: ${RESET}"
      local choice
      read -r choice
      choice="${choice:-A}"
      if [[ "$choice" =~ ^[Aa]$ ]]; then
        flavors=("${all_flavors[@]}")
      elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#all_flavors[@]} )); then
        flavors=("${all_flavors[$((choice - 1))]}")
      else
        log_error "Invalid choice."
        return 1
      fi
    fi
  fi

  local flavor
  for flavor in "${flavors[@]}"; do
    action_build_release_flavor "$flavor" || return 1
  done
}

action_build_release_flavor() {
  local built_apk=""
  local flavor="${1:-}"
  local cap=""
  local apk_sub="release"
  local bundle_sub="release"
  local out_name="app-release"
  if [[ -n "$flavor" ]]; then
    cap="$(printf '%s' "$flavor" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
    apk_sub="$flavor/release"
    bundle_sub="${flavor}Release"
    out_name="app-${flavor}-release"
    log_info "Release flavor: ${BOLD}${flavor}${RESET}"
  fi
  cd "$CONFIG_project_dir"
  require_gradlew || return 1
  local gradlew_bin="$GRADLEW"

  local r_type="${CONFIG_release_type:-apk}"
  if [[ -n "$flavor" ]]; then
    r_type="$(get_config_val "release_type_${flavor}" "$r_type")"
  fi
  local tasks=()
  case "$r_type" in
    aab|bundle)
      tasks=("bundle${cap}Release")
      ;;
    both|all)
      tasks=("assemble${cap}Release" "bundle${cap}Release")
      ;;
    apk|*)
      tasks=("assemble${cap}Release")
      ;;
  esac

  local cached_pass="$CONFIG_keystore_pass"
  local alias_name="${CONFIG_keystore_alias:-}"

  # If keystore is configured, ensure we have a valid password BEFORE starting Gradle build
  if [[ -n "$CONFIG_keystore_file" ]]; then
    local ks_reason="" ks_rc=0
    ks_reason=$(keystore_access_error "$CONFIG_keystore_file") || ks_rc=$?
    if [[ $ks_rc -eq 2 ]]; then
      log_error "Keystore $CONFIG_keystore_file $ks_reason."
      return 1
    elif [[ $ks_rc -eq 1 ]]; then
      log_warn "Keystore $CONFIG_keystore_file $ks_reason. The release will be left unsigned."
      CONFIG_keystore_file=""
    fi
  fi

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
        local keytool_out="" keytool_rc=0
        keytool_out=$("$keytool_bin" -list -keystore "$CONFIG_keystore_file" -storepass "$cached_pass" 2>&1) || keytool_rc=$?
        if [[ $keytool_rc -eq 0 ]]; then
          if [[ -z "$alias_name" ]]; then
            alias_name=$(echo "$keytool_out" | grep "PrivateKeyEntry" | head -1 | cut -d',' -f1 | tr -d ' ' || echo "upload")
            [[ -z "$alias_name" ]] && alias_name="upload"
          fi
          break
        else
          case "$(classify_keystore_error "$keytool_out")" in
            password)
              log_error "Incorrect keystore password for $(basename "$CONFIG_keystore_file"). Try again."
              cached_pass=""
              ;;
            access)
              log_error "Could not open $(basename "$CONFIG_keystore_file"), this is not a password problem:"
              echo "$keytool_out" | head -3 >&2
              return 1
              ;;
            java)
              log_error "keytool could not find a Java runtime. Install a JDK or set JAVA_HOME."
              echo "$keytool_out" | head -3 >&2
              return 1
              ;;
            *)
              log_error "keytool failed:"
              echo "$keytool_out" | head -5 >&2
              return 1
              ;;
          esac
        fi
      else
        break
      fi
    done
  fi

  CONFIG_keystore_pass="$cached_pass"
  CONFIG_keystore_alias="$alias_name"

  log_info "Starting Release build in ${C_MUTED}$CONFIG_project_dir${RESET}..."
  local start_time=$(date +%s)
  log_info "Running Gradle task(s): ${BOLD}${tasks[*]}${RESET}..."
  if run_gradle_with_stats "$gradlew_bin" "${tasks[@]}" --daemon; then
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_success "Release build completed in ${BOLD}${duration}s${RESET}!"
    
    local out_dir=""

    if [[ "$r_type" == "aab" || "$r_type" == "bundle" || "$r_type" == "both" || "$r_type" == "all" ]]; then
      local out_aab=$(find "$CONFIG_project_dir" -maxdepth 8 -name "*.aab" 2>/dev/null | grep "/build/outputs/bundle/${bundle_sub}" | xargs ls -t 2>/dev/null | head -1 || true)
      if [[ -n "$out_aab" ]]; then
        # Sign AAB if jarsigner available and keystore provided
        if [[ -n "$CONFIG_keystore_file" && -f "$CONFIG_keystore_file" ]]; then
          log_info "Signing release bundle with ${C_ACCENT}$(basename "$CONFIG_keystore_file")${RESET}..."
          local jarsigner_bin=$(which jarsigner 2>/dev/null || echo "/usr/bin/jarsigner")
          if [[ -x "$jarsigner_bin" ]]; then
            local jar_out=""
            if jar_out=$("$jarsigner_bin" -keystore "$CONFIG_keystore_file" \
              -storepass "$cached_pass" \
              ${CONFIG_key_pass:+-keypass "$CONFIG_key_pass"} \
              "$out_aab" "$alias_name" 2>&1); then
              log_success "Release Bundle signed."
            else
              log_error "Bundle signing failed ($(classify_keystore_error "$jar_out")):"
              echo "$jar_out" | head -5 >&2
            fi
          fi
        fi
        log_info "Release Bundle: ${C_ACCENT}$out_aab${RESET}"
        out_dir="$(dirname "$out_aab")"
      fi
    fi

    if [[ "$r_type" == "apk" || "$r_type" == "both" || "$r_type" == "all" ]]; then
      local raw_apk=$(find "$CONFIG_project_dir" -maxdepth 8 -name "*release*.apk" ! -name "*.tmp.apk" ! -name "*-aligned.apk" 2>/dev/null | grep "/build/outputs/apk/${apk_sub}" | xargs ls -t 2>/dev/null | head -1 || true)
      local final_apk="$raw_apk"

      if [[ -n "$raw_apk" && -n "$CONFIG_keystore_file" && -f "$CONFIG_keystore_file" ]]; then
        # Locate apksigner in SDK
        local apksigner_bin=$(find "$HOME/Library/Android/sdk/build-tools" -name "apksigner" 2>/dev/null | sort -V | tail -1 || true)
        local zipalign_bin=$(find "$HOME/Library/Android/sdk/build-tools" -name "zipalign" 2>/dev/null | sort -V | tail -1 || true)
        
        local apk_dir=$(dirname "$raw_apk")
        local final_target_apk="$apk_dir/${out_name}.apk"
        local temp_signed_apk="$apk_dir/${out_name}-signed.tmp.apk"

        log_info "Signing release APK with ${C_ACCENT}$(basename "$CONFIG_keystore_file")${RESET}..."

        local to_sign="$raw_apk"
        if [[ -n "$zipalign_bin" && -x "$zipalign_bin" && "$raw_apk" == *"-unsigned.apk" ]]; then
          local aligned_apk="$apk_dir/${out_name}-aligned.tmp.apk"
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
              log_error "APK signing failed:"
              echo "$apksign_err" | head -5 >&2
              if [[ "$(classify_keystore_error "$apksign_err")" == "password" ]]; then
                echo -en "${C_PRIMARY}Enter Keystore / Key Password for $(basename "$CONFIG_keystore_file"): ${RESET}"
                read -rs cached_pass
                echo ""
              else
                log_warn "This is not a password problem, leaving the APK unsigned."
                break
              fi
            fi
          done

          if [[ $sign_success -eq 1 && -f "$temp_signed_apk" ]]; then
            rm -f "$apk_dir/${out_name}-aligned.tmp.apk"
            rm -f "$apk_dir/${out_name}-unsigned.apk"
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
      [[ -n "$final_apk" && -f "$final_apk" ]] && built_apk="$final_apk"
      [[ -n "$final_apk" && -z "$out_dir" ]] && out_dir="$(dirname "$final_apk")"
    fi

    if [[ -n "$out_dir" && -d "$out_dir" ]]; then
      prompt_release_output "$out_dir" "$built_apk" "$flavor"
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
  print_divider
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
  local serial="${1:-}"
  if [[ -z "$serial" ]]; then
    select_device
    serial="$SELECTED_DEVICE"
  fi
  if ! command -v scrcpy >/dev/null 2>&1; then
    log_error "'scrcpy' is not installed. Install it via 'brew install scrcpy'."
    return 1
  fi
  log_info "Starting screen mirror for ${C_PRIMARY}$serial${RESET}..."
  scrcpy -s "$serial" --window-title "$CONFIG_project_name ($serial)" --always-on-top >/dev/null 2>&1 &
  disown 2>/dev/null || true
  log_success "Mirroring started in background."
}

action_logs() {
  select_device
  if [[ -z "$CONFIG_package_name" ]]; then
    log_error "package_name is not configured for logcat streaming."
    return 1
  fi

  echo -e "${BOLD}${C_PRIMARY}=== Live Logcat: ${C_ACCENT}$CONFIG_package_name${C_PRIMARY} on ${SELECTED_DEVICE} ===${RESET}"
  echo -e "${C_MUTED}Press Ctrl+C to stop.${RESET}\n"

  # Trap Ctrl+C cleanly to return instead of exiting script
  local interrupted=0
  trap 'echo -e "\n${C_MUTED}Logcat stopped.${RESET}"; interrupted=1' INT

  # Stream logs and highlight PID/tags/levels
  while [[ $interrupted -eq 0 ]]; do
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
      if [[ $interrupted -eq 1 ]]; then
        break
      fi
      echo -e "${C_WARN}App process ended or crashed. Waiting for restart...${RESET}"
    fi
    sleep 1
  done
  trap - INT
}

action_run_all() {
  if ! action_build; then
    return 1
  fi
  if ! action_install; then
    return 1
  fi
  action_launch
  echo ""
  action_logs
}

action_sync() {
  log_info "Running Gradle sync & dependency check in ${C_MUTED}$CONFIG_project_dir${RESET}..."
  cd "$CONFIG_project_dir"
  require_gradlew || return 1
  local gradlew_bin="$GRADLEW"
  if "$gradlew_bin" help --daemon >/dev/null && "$gradlew_bin" tasks --daemon >/dev/null; then
    log_success "Gradle sync & daemon check complete!"
    return 0
  else
    log_error "Gradle sync failed."
    return 1
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

# Asks which product flavor to use for a debug build; empty result means no flavors are configured.
choose_debug_flavor() {
  if [[ -z "${CONFIG_release_flavors:-}" ]]; then
    return 0
  fi
  local all_flavors=()
  IFS=',' read -r -a all_flavors <<< "$CONFIG_release_flavors"
  if (( ${#all_flavors[@]} == 1 )); then
    echo "${all_flavors[0]}"
    return 0
  fi
  echo -e "\n${BOLD}${C_PRIMARY}=== Build flavor ===${RESET}" >&2
  local i=1
  for f in "${all_flavors[@]}"; do
    echo -e "  ${BOLD}[$i]${RESET} $f" >&2
    i=$((i + 1))
  done
  echo -en "${C_PRIMARY}Choose [1]: ${RESET}" >&2
  local choice
  read -r choice
  choice="${choice:-1}"
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#all_flavors[@]} )); then
    echo "${all_flavors[$((choice - 1))]}"
    return 0
  fi
  log_error "Invalid choice." >&2
  return 1
}

action_optimized_debug() {
  local gradle_file
  gradle_file=$(find_app_gradle_file)

  local flavor=""
  flavor=$(choose_debug_flavor) || return 1
  local original_task="$CONFIG_gradle_task"
  if [[ -n "$flavor" ]]; then
    local cap
    cap="$(printf '%s' "$flavor" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
    CONFIG_gradle_task="assemble${cap}Debug"
    log_info "Flavor: ${BOLD}${flavor}${RESET}"
  fi

  if [[ -z "$gradle_file" || ! -f "$gradle_file" ]]; then
    log_error "Could not locate app build.gradle(.kts) file."
    CONFIG_gradle_task="$original_task"
    return 1
  fi

  if ! grep -q "optimized dev build" "$gradle_file"; then
    log_error "Optimized dev build pattern not found in $gradle_file."
    CONFIG_gradle_task="$original_task"
    return 1
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
  CONFIG_gradle_task="$original_task"

  if [[ $build_failed -ne 0 ]]; then
    log_error "Optimized debug build/install encountered errors."
    return 1
  else
    log_success "Optimized debug build & install complete!"
    return 0
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

# Helper to extract live project info for dashboard
refresh_git_info() {
  PROJECT_GIT_BRANCH=""
  PROJECT_GIT_INFO=""
  local dir="$CONFIG_project_dir"
  [[ -d "$dir/.git" ]] || return 0
  local line header="" staged=0 modified=0 untracked=0 ahead=0 behind=0 out=""
  while IFS= read -r line; do
    if [[ "$line" == "## "* ]]; then
      header="${line#\#\# }"
      continue
    fi
    local x="${line:0:1}" y="${line:1:1}"
    if [[ "$x" == "?" ]]; then
      untracked=$((untracked + 1))
      continue
    fi
    [[ "$x" != " " ]] && staged=$((staged + 1))
    [[ "$y" != " " ]] && modified=$((modified + 1))
  done < <(git -C "$dir" status --porcelain=v1 -b 2>/dev/null)
  local branch="${header#No commits yet on }"
  branch="${branch%%...*}"
  PROJECT_GIT_BRANCH="${branch%% *}"
  [[ "$header" =~ ahead\ ([0-9]+) ]] && ahead="${BASH_REMATCH[1]}"
  [[ "$header" =~ behind\ ([0-9]+) ]] && behind="${BASH_REMATCH[1]}"
  (( staged > 0 )) && out+="${C_SUCCESS}+${staged}${RESET} "
  (( modified > 0 )) && out+="${C_WARN}~${modified}${RESET} "
  (( untracked > 0 )) && out+="${C_ERROR}?${untracked}${RESET} "
  (( ahead > 0 )) && out+="${C_PRIMARY}↑${ahead}${RESET} "
  (( behind > 0 )) && out+="${C_ACCENT}↓${behind}${RESET} "
  [[ -z "$out" ]] && out="${C_SUCCESS}clean${RESET}"
  PROJECT_GIT_INFO="$out"
}

refresh_gradle_info() {
  PROJECT_SDK=""
  PROJECT_VERSION=""
  local gradle_file content
  gradle_file=$(find_app_gradle_file)
  [[ -n "$gradle_file" && -f "$gradle_file" ]] || return 0
  content=$(<"$gradle_file")
  local sdk_re='compileSdk([[:space:]]*=|[[:space:]]*\{[[:space:]]*version[[:space:]]*=([[:space:]]*release\()?)[[:space:]]*([0-9]+)'
  local minor_re='compileSdkMinor[[:space:]]*=[[:space:]]*([0-9]+)'
  local name_re='versionName[[:space:]]*=[[:space:]]*"([^"]*)"'
  local code_re='versionCode[[:space:]]*=[[:space:]]*([0-9]+)'
  local sdk="" minor="" v_name="" v_code=""
  [[ "$content" =~ $sdk_re ]] && sdk="${BASH_REMATCH[3]}"
  [[ "$content" =~ $minor_re ]] && minor="${BASH_REMATCH[1]}"
  [[ "$content" =~ $name_re ]] && v_name="${BASH_REMATCH[1]}"
  [[ "$content" =~ $code_re ]] && v_code="${BASH_REMATCH[1]}"
  if [[ -n "$sdk" ]]; then
    PROJECT_SDK="SDK $sdk${minor:+.$minor}"
  fi
  if [[ -n "$v_name" ]]; then
    PROJECT_VERSION="v$v_name"
    [[ -n "$v_code" ]] && PROJECT_VERSION="$PROJECT_VERSION ($v_code)"
  fi
}

refresh_target_type() {
  local key="${CONFIG_project_name}|${CONFIG_FILE:-}|$CONFIG_project_dir"
  if [[ "${TARGET_TYPE_KEY:-}" != "$key" ]]; then
    TARGET_TYPE_KEY="$key"
    if check_is_wear_project "$CONFIG_project_name" "${CONFIG_FILE:-}" "$CONFIG_project_dir"; then
      TARGET_TYPE_VALUE=" [WearOS]"
    else
      TARGET_TYPE_VALUE=" [Phone]"
    fi
  fi
  PROJECT_TARGET_TYPE="$TARGET_TYPE_VALUE"
}

# Cached per device serial so redraws stay instant.
refresh_device_info() {
  [[ "${DEVICE_INFO_KEY:-}" == "${SELECTED_DEVICE:-}" ]] && return 0
  DEVICE_INFO_KEY="${SELECTED_DEVICE:-}"
  DEVICE_INFO=""
  [[ -z "$DEVICE_INFO_KEY" ]] && return 0
  local out name model android
  out="$(adb_cmd shell 'getprop ro.product.marketname; getprop ro.product.model; getprop ro.build.version.release' 2>/dev/null | tr -d '\r')" || true
  { IFS= read -r name; IFS= read -r model; IFS= read -r android; } <<< "$out"
  name="${name:-$model}"
  local kind="usb"
  is_wireless_serial "$DEVICE_INFO_KEY" && kind="wifi"
  DEVICE_INFO="${name:+$name · }${android:+Android $android · }$kind"
}

get_project_details() {
  refresh_git_info
  refresh_gradle_info
  refresh_target_type
}

load_env_secrets() {
  local env_file="$SCRIPT_DIR/.env"
  [[ -f "$env_file" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

apk_badging_value() {
  local apk="$1" field="$2"
  local aapt_bin
  aapt_bin=$(find "$HOME/Library/Android/sdk/build-tools" -name "aapt2" -o -name "aapt" 2>/dev/null | sort -V | tail -1 || true)
  [[ -n "$aapt_bin" && -x "$aapt_bin" ]] || return 0
  "$aapt_bin" dump badging "$apk" 2>/dev/null | head -1 | grep -oE "(^| )${field}='[^']*'" | head -1 | cut -d"'" -f2 || true
}

apk_field_value() {
  local apk="$1" field="$2"
  local aapt_bin
  aapt_bin=$(find "$HOME/Library/Android/sdk/build-tools" -name "aapt2" -o -name "aapt" 2>/dev/null | sort -V | tail -1 || true)
  [[ -n "$aapt_bin" && -x "$aapt_bin" ]] || return 0
  local key="$field"
  [[ "$field" == "minSdkVersion" ]] && key="sdkVersion"
  "$aapt_bin" dump badging "$apk" 2>/dev/null | grep -E "^${key}:'" | head -1 | cut -d"'" -f2 || true
}

html_escape() {
  local t="$1"
  t="${t//&/&amp;}"
  t="${t//</&lt;}"
  t="${t//>/&gt;}"
  printf '%s' "$t"
}

# Commits on the current branch not in any release or pre-release tag, newest first,
# trimmed so the whole caption stays under Telegram's 1024 character limit.
older_commits_label() {
  if (( $1 == 1 )); then printf '… 1 older commit'; else printf '… %d older commits' "$1"; fi
}

build_changelog_caption() {
  local head="$1"
  local limit=1000
  local repo="$CONFIG_project_dir"
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 0

  # Anything already in a tagged release (stable or pre-release) is excluded.
  local last_tag title
  last_tag=$(git -C "$repo" tag --sort=-creatordate 2>/dev/null | head -1 || true)
  local -a range=(HEAD)
  if [[ -n "$last_tag" ]]; then
    range=(HEAD --not --tags)
    title="<b>Changes since $(html_escape "$last_tag")</b>"
  else
    title="<b>Recent changes</b>"
  fi

  local -a lines=()
  local subject
  while IFS= read -r subject; do
    [[ -z "$subject" ]] && continue
    (( ${#subject} > 90 )) && subject="${subject:0:89}…"
    lines+=("• $(html_escape "$subject")")
  done < <(git -C "$repo" log --no-merges --format='%s' -n 200 "${range[@]}" 2>/dev/null)

  (( ${#lines[@]} == 0 )) && return 0

  local body=$'\n\n'"$title"$'\n'"<blockquote>"
  local total=${#lines[@]} shown=0 i line more
  for (( i = 0; i < total; i++ )); do
    line="${lines[$i]}"
    more=""
    (( i + 1 < total )) && more=$'\n'"$(older_commits_label $(( total - i - 1 )))"
    if (( ${#head} + ${#body} + 1 + ${#line} + ${#more} + 13 > limit )); then
      break
    fi
    (( shown > 0 )) && body+=$'\n'
    body+="$line"
    shown=$(( shown + 1 ))
  done
  (( shown == 0 )) && return 0
  (( shown < total )) && body+=$'\n'"$(older_commits_label $(( total - shown )))"
  body+="</blockquote>"
  printf '%s' "$body"
}

send_apk_to_tidwib() {
  local apk="$1" flavor="${2:-}"
  load_env_secrets
  local token="${TELEGRAM_BOT_TOKEN:-}"
  local chat_id="${CONFIG_telegram_chat_id:-$DEFAULT_TELEGRAM_CHAT_ID}"
  local topic_id="${CONFIG_telegram_topic_id:-$DEFAULT_TELEGRAM_TOPIC_ID}"

  if [[ "$apk" != *.apk || ! -f "$apk" ]]; then
    log_error "Only APK files can be sent. Nothing to send."
    return 1
  fi
  if [[ -z "$token" ]]; then
    log_error "TELEGRAM_BOT_TOKEN is not set in $SCRIPT_DIR/.env"
    return 1
  fi
  if [[ -z "$chat_id" ]]; then
    log_error "telegram_chat_id is not set in $(basename "${CONFIG_FILE:-config}")"
    return 1
  fi

  local size_bytes
  size_bytes=$(stat -f%z "$apk" 2>/dev/null || echo 0)
  if (( size_bytes > 50 * 1024 * 1024 )); then
    log_error "APK is larger than Telegram's 50 MB bot upload limit."
    return 1
  fi

  local version_name version_code package min_sdk target_sdk size_h branch commit built_at
  version_name=$(apk_badging_value "$apk" "versionName")
  version_code=$(apk_badging_value "$apk" "versionCode")
  package=$(apk_badging_value "$apk" "name")
  min_sdk=$(apk_field_value "$apk" "minSdkVersion")
  target_sdk=$(apk_field_value "$apk" "targetSdkVersion")
  size_h=$(awk -v b="$size_bytes" 'BEGIN { printf "%.1f MB", b / 1048576 }')
  branch=$(git -C "$CONFIG_project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  commit=$(git -C "$CONFIG_project_dir" rev-parse --short HEAD 2>/dev/null || true)
  built_at=$(date -r "$apk" "+%Y-%m-%d %H:%M %Z")

  local title_line="${CONFIG_project_name}"
  [[ -n "$version_name" ]] && title_line+=" v${version_name}"
  [[ -n "$version_code" ]] && title_line+=" (${version_code})"
  local caption="<b><u>$(html_escape "$title_line")</u></b>"
  local source_line="Release${flavor:+ (${flavor})}"
  [[ -n "$branch" ]] && source_line+=" from ${branch}@${commit}"
  caption+=$'\n'"<i>$(html_escape "$source_line")</i>"
  caption+=$'\n'"${built_at}"
  caption+=$(build_changelog_caption "$caption")

  echo ""
  echo -e "${BOLD}Upload to TIDWIB${RESET}"
  echo -e "  ${C_MUTED}File     ${RESET} $(basename "$apk")"
  echo -e "  ${C_MUTED}App      ${RESET} ${CONFIG_project_name}${package:+ ($package)}"
  echo -e "  ${C_MUTED}Version  ${RESET} ${version_name:-?} (${version_code:-?})"
  echo -e "  ${C_MUTED}Variant  ${RESET} release${flavor:+ · $flavor}"
  [[ -n "$min_sdk" ]] && echo -e "  ${C_MUTED}SDK      ${RESET} min ${min_sdk}${target_sdk:+, target $target_sdk}"
  echo -e "  ${C_MUTED}Size     ${RESET} ${size_h} (${size_bytes} bytes)"
  [[ -n "$branch" ]] && echo -e "  ${C_MUTED}Git      ${RESET} ${branch}@${commit}"
  echo ""

  local resp_file
  resp_file=$(mktemp)
  local stats=""
  stats=$(curl --progress-bar -X POST "https://api.telegram.org/bot${token}/sendDocument" \
    -o "$resp_file" -w '%{http_code} %{time_total} %{speed_upload}' \
    --form-string "chat_id=${chat_id}" \
    ${topic_id:+--form-string "message_thread_id=${topic_id}"} \
    --form-string "parse_mode=HTML" \
    --form-string "caption=${caption}" \
    -F "document=@${apk};type=application/vnd.android.package-archive") || true
  local response
  response=$(cat "$resp_file" 2>/dev/null || true)
  rm -f "$resp_file"

  local http_code time_total speed
  read -r http_code time_total speed <<< "${stats:-000 0 0}"

  if [[ "$response" == *'"ok":true'* ]]; then
    local message_id link=""
    message_id=$(echo "$response" | grep -oE '"message_id":[0-9]+' | head -1 | cut -d: -f2)
    if [[ -n "$message_id" && "$chat_id" == -100* ]]; then
      link="https://t.me/c/${chat_id#-100}/${message_id}${topic_id:+?thread=$topic_id}"
    fi
    log_success "Sent to TIDWIB in $(awk -v t="$time_total" 'BEGIN { printf "%.1fs", t }') at $(awk -v s="$speed" 'BEGIN { printf "%.1f MB/s", s / 1048576 }')."
    [[ -n "$message_id" ]] && log_info "Message ID: ${message_id}"
    [[ -n "$link" ]] && log_info "Link: ${C_ACCENT}${link}${RESET}"
  else
    log_error "Telegram upload failed (HTTP ${http_code}): $(echo "$response" | sed -E 's/bot[0-9]+:[A-Za-z0-9_-]+/bot<token>/g' | head -c 300)"
    return 1
  fi
}

prompt_release_output() {
  local out_dir="$1" apk="${2:-}" flavor="${3:-}"
  while true; do
    # Drop keys typed while the previous action ran so they can't trigger Finder or another upload.
    perl -MPOSIX -e 'tcflush(0, TCIFLUSH)' 2>/dev/null || true
    echo ""
    if [[ -n "$apk" ]]; then
      echo -en "${C_MUTED}Press ${BOLD}[Enter]${RESET}${C_MUTED} to open in Finder, ${BOLD}[T]${RESET}${C_MUTED} to send to TIDWIB chat, or ${BOLD}[Esc]${RESET}${C_MUTED} to return...${RESET}"
    else
      echo -en "${C_MUTED}Press ${BOLD}[Enter]${RESET}${C_MUTED} to open in Finder, or ${BOLD}[Esc]${RESET}${C_MUTED} to return...${RESET}"
    fi
    while true; do
      local key=""
      if ! IFS= read -rsn1 key; then
        echo ""
        return 0
      fi
      if [[ -z "$key" ]]; then
        echo ""
        open "$out_dir"
        log_info "Opened ${out_dir} in Finder."
        break
      elif [[ "$key" == $'\e' ]]; then
        local rest=""
        read_esc_tail; rest="$REST"
        if [[ -z "$rest" ]]; then
          echo ""
          return 0
        fi
      elif [[ -n "$apk" && ( "$key" == "t" || "$key" == "T" ) ]]; then
        echo ""
        send_apk_to_tidwib "$apk" "$flavor" || true
        break
      fi
    done
  done
}

prompt_reinstall_or_esc() {
  echo ""
  echo -en "${C_MUTED}Press ${BOLD}[Enter]${RESET}${C_MUTED} to re-install, or ${BOLD}[Esc]${RESET}${C_MUTED} to return...${RESET}"
  while true; do
    read_key || true
    case "$KEY_KIND" in
      enter) echo ""; return 0 ;;
      esc) echo ""; return 1 ;;
    esac
  done
}

# --- Submenu engine ---
# A submenu <name> provides <name>_draw and <name>_dispatch <sub> <arg>; it may set SUBMENU_QUIET=1 for interactive commands.
# Input is "<sub> [arg]" (an optional leading <prefix> letter is accepted); "once" runs a single command and returns.
submenu_run() {
  local name="$1" prefix="$2" input="${3:-}" once="${4:-}" first=1
  local prefix_re="^[${prefix}$(printf '%s' "$prefix" | tr '[:lower:]' '[:upper:]')]([a-zA-Z0-9]|[[:space:]])"
  while true; do
    if [[ -z "$input" ]]; then
      (( first )) && clear
      first=0
      "${name}_draw"
      print_back_hint
      read_line_esc "  ${C_ACCENT}${name} ❯${RESET} " || return 0
      input="$INPUT_LINE"
    fi
    input="$(trim "$input")"
    if [[ -z "$input" ]]; then
      continue
    fi
    [[ "$input" =~ $prefix_re ]] && input="$(trim "${input:1}")"

    local sub="${input%%[[:space:]]*}" arg=""
    [[ "$input" == *[[:space:]]* ]] && arg="$(trim "${input#"$sub"}")"
    sub="$(to_lower "$sub")"

    SUBMENU_QUIET=0
    echo ""
    if "${name}_dispatch" "$sub" "$arg"; then
      (( SUBMENU_QUIET )) || log_success "Done."
    else
      log_warn "${name} command did not complete."
    fi
    if [[ -n "$once" ]]; then
      (( SUBMENU_QUIET )) || pause_return
      return 0
    fi
    input=""
  done
}

# --- Git submenu ---
git_in_project() {
  cd "$CONFIG_project_dir" || return 1
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_error "$CONFIG_project_dir is not a git repository."
    return 1
  fi
}

git_do_develop() {
  git checkout develop && git pull
}

git_do_new_branch() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    ask_value "New branch name" || return 1
    name="$ASK_RESULT"
  fi
  git checkout -b "$name"
}

git_do_switch() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    local branches=() b
    while IFS= read -r b; do
      [[ -n "$b" ]] && branches+=("$b")
    done < <(git for-each-ref --sort=-committerdate --count=10 --format='%(refname:short)' refs/heads)
    if (( ${#branches[@]} == 0 )); then
      log_warn "No local branches found."
      return 1
    fi
    local current i
    current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    for i in "${!branches[@]}"; do
      b="${branches[$i]}"
      if [[ "$b" == "$current" ]]; then
        echo -e "  ${BOLD}$((i + 1)))${RESET} ${C_SUCCESS}$b${RESET} ${C_MUTED}(current)${RESET}"
      else
        echo -e "  ${BOLD}$((i + 1)))${RESET} $b"
      fi
    done
    ask_value "Select branch [1-${#branches[@]}] or type a name" || return 1
    local pick="$ASK_RESULT"
    if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#branches[@]} )); then
      name="${branches[$((pick - 1))]}"
    else
      name="$pick"
    fi
  fi
  git checkout "$name"
}

git_do_pr() {
  if ! command -v gh >/dev/null 2>&1; then
    log_error "GitHub CLI (gh) is not installed."
    return 1
  fi
  local id="${1:-}"
  if [[ -z "$id" ]]; then
    ask_value "PR number" || return 1
    id="$ASK_RESULT"
  fi
  id="${id#\#}"
  if [[ ! "$id" =~ ^[0-9]+$ ]]; then
    log_error "Invalid PR number '$id'."
    return 1
  fi
  gh pr checkout "$id"
}

git_do_commit() {
  local msg="${1:-}"
  if [[ -z "$msg" ]]; then
    ask_value "Commit message" || return 1
    msg="$ASK_RESULT"
  fi
  if [[ ${#msg} -ge 2 && ( ( "${msg:0:1}" == '"' && "${msg: -1}" == '"' ) || ( "${msg:0:1}" == "'" && "${msg: -1}" == "'" ) ) ]]; then
    msg="${msg:1:${#msg}-2}"
  fi
  git commit -m "$msg"
}

git_do_add() {
  git add . && log_success "Staged all changes."
}

git_draw() {
  refresh_git_info
  print_header "git" "${C_SUCCESS}${PROJECT_GIT_BRANCH}${RESET}  ${PROJECT_GIT_INFO}"
  print_section "BRANCH"
  print_menu_item "D" "Checkout & pull develop" "gd"
  print_menu_item "B" "New branch" "gb <name>"
  print_menu_item "S" "Switch branch" "gs <name>"
  print_menu_item "PR" "Checkout PR" "gpr <id|#id>"
  print_section "CHANGES"
  print_menu_item "C" "Commit" "gc <message>"
  print_menu_item "A" "Add all" "ga"
}

git_dispatch() {
  git_in_project || return 1
  case "$1" in
    d) git_do_develop ;;
    b) git_do_new_branch "$2" ;;
    s) git_do_switch "$2" ;;
    pr) git_do_pr "$2" ;;
    c) git_do_commit "$2" ;;
    a) git_do_add ;;
    *) log_warn "Unknown git command '$1'."; return 1 ;;
  esac
}

# --- Gradle submenu ---
gradle_props() {
  python3 - "$@" <<'PYEOF'
import re, sys
path, mode = sys.argv[1], sys.argv[2]
text = open(path).read()
m = re.search(r'defaultConfig\s*\{', text)
if not m:
    sys.exit(0)
start = m.end()
depth, i = 1, start
while i < len(text) and depth:
    depth += (text[i] == '{') - (text[i] == '}')
    i += 1
end = i - 1
block = text[start:end]
rules = [
    ('versionCode', r'(versionCode\s*=\s*)(\d+)()', 'versionCode'),
    ('versionName', r'(versionName\s*=\s*")([^"]*)(")', 'versionName'),
]
found = []
for key, rx, _ in rules:
    mm = re.search(rx, block)
    if mm:
        found.append((key, mm.group(2), rx))
for mm in re.finditer(r'^[ \t]*val\s+(\w+)\s*=\s*(\d+|"[^"]*")[ \t]*$', block, re.M):
    key = mm.group(1)
    found.append((key, mm.group(2).strip('"'), r'(^[ \t]*val\s+' + key + r'\s*=\s*"?)(\d+|(?<=")[^"]*)("?[ \t]*$)'))
for mm in re.finditer(r'buildConfigField\(\s*"(\w+)"\s*,\s*"(\w+)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)', block):
    if re.fullmatch(r'[\w.\-\\"]+', mm.group(3)) and not re.search(r'[A-Za-z_]\w*\.\w+\(', mm.group(3)):
        key = mm.group(2)
        found.append((key, mm.group(3), r'(buildConfigField\(\s*"\w+"\s*,\s*"' + key + r'"\s*,\s*")((?:[^"\\]|\\.)*)("\s*\))'))
if mode == 'list':
    for key, val, _ in found:
        print(f'{key}|{val}')
elif mode == 'set':
    key, new = sys.argv[3], sys.argv[4]
    for k, v, rx in found:
        if k == key:
            nb = re.sub(rx, lambda mm: mm.group(1) + new + mm.group(3), block, count=1, flags=re.M)
            open(path, 'w').write(text[:start] + nb + text[end:])
            break
PYEOF
}

gradle_props_menu() {
  SUBMENU_QUIET=1
  local gradle_file status=""
  gradle_file=$(find_app_gradle_file)
  if [[ -z "$gradle_file" ]]; then
    log_error "No app gradle file found."
    return 1
  fi
  while true; do
    local keys=() vals=() line
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      keys+=("${line%%|*}")
      vals+=("${line#*|}")
    done < <(gradle_props "$gradle_file" list)
    if (( ${#keys[@]} == 0 )); then
      log_warn "No editable properties found in $gradle_file"
      return 1
    fi
    clear
    print_header "gradle properties" "${C_PRIMARY}${gradle_file#$CONFIG_project_dir/}${RESET}"
    local i
    for i in "${!keys[@]}"; do
      print_menu_item "$((i + 1))" "${keys[$i]}" "${vals[$i]}"
    done
    echo ""
    echo -e "  ${C_MUTED}number to edit  ·  <n> <value> to set  ·  <n>+ to bump${RESET}"
    print_back_hint
    [[ -n "$status" ]] && echo -e "$status"
    status=""
    read_line_esc "  ${C_ACCENT}props ❯${RESET} " || return 0

    local input num rest new idx key cur
    input="$(trim "$INPUT_LINE")"
    [[ -z "$input" ]] && continue
    num="${input%%[^0-9]*}"
    rest="$(trim "${input#"$num"}")"
    if [[ -z "$num" ]] || (( num < 1 || num > ${#keys[@]} )); then
      status="${C_WARN}[WARN]${RESET} Invalid selection."
      continue
    fi
    idx=$((num - 1)); key="${keys[$idx]}"; cur="${vals[$idx]}"
    if [[ -z "$rest" ]]; then
      echo ""
      echo -e "  ${BOLD}$key${RESET} = ${C_ACCENT}$cur${RESET}"
      if [[ "$cur" =~ ^[0-9]+$ ]]; then
        ask_value "New value, or + to bump" || continue
      else
        ask_value "New value" || continue
      fi
      new="$ASK_RESULT"
    else
      new="$rest"
    fi
    if [[ "$new" == "+" ]]; then
      if [[ "$cur" =~ ^[0-9]+$ ]]; then
        new=$((cur + 1))
      else
        status="${C_WARN}[WARN]${RESET} $key is not numeric."
        continue
      fi
    fi
    if [[ "$cur" =~ ^[0-9]+$ && ! "$new" =~ ^[0-9]+$ ]]; then
      status="${C_WARN}[WARN]${RESET} $key must be a number."
      continue
    fi
    gradle_props "$gradle_file" set "$key" "$new"
    status="${C_SUCCESS}[SUCCESS]${RESET} $key: $cur → $new"
  done
}

gradle_draw() {
  refresh_gradle_info
  print_header "gradle" "${C_PRIMARY}${CONFIG_project_name}${RESET}" "${C_MUTED}${PROJECT_VERSION}${RESET}"
  print_menu_item "S" "Sync" "cs"
  print_menu_item "C" "Clean build" "cc"
  print_menu_item "P" "Properties" "cp" menu
}

gradle_dispatch() {
  case "$1" in
    s) action_sync ;;
    c) action_clean ;;
    p) gradle_props_menu ;;
    *) log_warn "Unknown gradle command '$1'."; return 1 ;;
  esac
}

# --- App submenu ---
app_draw() {
  print_header "app" "${C_PRIMARY}${CONFIG_package_name}${RESET}"
  print_menu_item "S" "Start" "as"
  print_menu_item "F" "Force stop" "af"
}

app_dispatch() {
  SUBMENU_QUIET=1
  case "$1" in
    s) action_launch ;;
    f) action_stop ;;
    *) log_warn "Unknown app command '$1'."; return 1 ;;
  esac
}

# --- Devices submenu ---
is_wireless_serial() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ || "$1" == *_adb-tls-connect* ]]; }

devices_refresh() {
  DEV_SERIALS=()
  DEV_MODELS=()
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    DEV_SERIALS+=("$(echo "$line" | awk '{print $1}')")
    DEV_MODELS+=("$(echo "$line" | grep -o 'model:[^ ]*' | cut -d: -f2 || true)")
  done < <(get_connected_devices)
}

devices_draw() {
  devices_refresh
  local current="${SELECTED_DEVICE:-none}"
  print_header "devices" "${C_SUCCESS}${current}${RESET}"
  print_section "CONNECTED"
  if (( ${#DEV_SERIALS[@]} == 0 )); then
    echo -e "  ${C_MUTED}No devices connected${RESET}"
  fi
  local i serial marker kind
  for i in "${!DEV_SERIALS[@]}"; do
    serial="${DEV_SERIALS[$i]}"
    marker="${C_MUTED}○${RESET}"
    [[ "$serial" == "$SELECTED_DEVICE" ]] && marker="${C_SUCCESS}●${RESET}"
    if is_wireless_serial "$serial"; then kind="wifi"; else kind="usb"; fi
    print_menu_item "$((i + 1))" "${marker} ${serial}" "${DEV_MODELS[$i]:-unknown} · $kind"
  done
  print_section "ACTIONS"
  print_menu_item "W" "Connect wireless" "dw [ip:port]"
  print_menu_item "P" "Pair wireless" "dp [ip:port code]"
  print_menu_item "M" "Mirror" "dm [n]"
  print_menu_item "X" "Disconnect" "dx [n]"
  print_menu_item "D" "Save as default" "dd"
}

devices_do_select() {
  local n="$1"
  if [[ ! "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#DEV_SERIALS[@]} )); then
    log_warn "No device [$n]."
    return 1
  fi
  SELECTED_DEVICE="${DEV_SERIALS[$((n - 1))]}"
  log_success "Selected ${BOLD}$SELECTED_DEVICE${RESET}."
}

devices_do_connect() {
  local addr="${1:-}"
  if [[ -z "$addr" ]]; then
    if discover_and_connect_mdns; then
      devices_refresh
      return 0
    fi
    echo -e "${C_MUTED}On phone: Settings → Developer options → Wireless debugging.${RESET}"
    ask_value "Phone IP:PORT" || return 1
    addr="$ASK_RESULT"
  fi
  [[ "$addr" == *:* ]] || addr="$addr:5555"
  if adb connect "$addr" 2>&1 | tee /dev/stderr | grep -qi "connected to"; then
    devices_refresh
    SELECTED_DEVICE="$addr"
    return 0
  fi
  return 1
}

devices_do_pair() {
  local addr="${1%%[[:space:]]*}" code=""
  [[ "$1" == *[[:space:]]* ]] && code="$(trim "${1#*[[:space:]]}")"
  if [[ -z "$addr" ]]; then
    ask_value "Pairing IP:PORT" || return 1
    addr="$ASK_RESULT"
  fi
  if [[ -z "$code" ]]; then
    ask_value "6-digit pairing code" || return 1
    code="$ASK_RESULT"
  fi
  adb pair "$addr" "$code" && echo -e "${C_MUTED}Now connect with ${BOLD}dw${RESET}${C_MUTED}.${RESET}"
}

devices_do_disconnect() {
  local serial="$SELECTED_DEVICE"
  if [[ -n "${1:-}" ]]; then
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= ${#DEV_SERIALS[@]} )) || { log_warn "No device [$1]."; return 1; }
    serial="${DEV_SERIALS[$(($1 - 1))]}"
  fi
  if ! is_wireless_serial "$serial"; then
    log_warn "${serial:-No device} is not a wireless device."
    return 1
  fi
  adb disconnect "$serial"
  [[ "$serial" == "$SELECTED_DEVICE" ]] && SELECTED_DEVICE=""
  return 0
}

devices_do_mirror() {
  SUBMENU_QUIET=1
  local serial="$SELECTED_DEVICE"
  if [[ -n "${1:-}" ]]; then
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= ${#DEV_SERIALS[@]} )) || { log_warn "No device [$1]."; return 1; }
    serial="${DEV_SERIALS[$(($1 - 1))]}"
  fi
  if [[ -z "$serial" ]]; then
    log_warn "No device selected."
    return 1
  fi
  action_mirror "$serial"
}

devices_do_default() {
  if [[ -z "$SELECTED_DEVICE" ]]; then
    log_warn "No device selected."
    return 1
  fi
  if [[ -z "${CONFIG_FILE:-}" || ! -f "$CONFIG_FILE" ]]; then
    log_warn "No config file to save into."
    return 1
  fi
  save_target_device_to_config "$SELECTED_DEVICE"
}

devices_dispatch() {
  devices_refresh
  case "$1" in
    [0-9]*) devices_do_select "$1" ;;
    w) devices_do_connect "$2" ;;
    p) devices_do_pair "$2" ;;
    x) devices_do_disconnect "$2" ;;
    m) devices_do_mirror "$2" ;;
    d) devices_do_default ;;
    *) log_warn "Unknown devices command '$1'."; return 1 ;;
  esac
}

# --- Interactive TUI Dashboard ---
show_dashboard() {
  select_device
  set -o history
  history -c
  local hist_file="$HOME/.android_build_history"
  [[ -f "$hist_file" ]] && history -r "$hist_file" 2>/dev/null || true

  local keep_screen=0
  MAIN_PROMPT=$'\001'"$(printf '%b' "$C_ACCENT")"$'\002'"  ❯ "$'\001'"$(printf '%b' "$RESET")"$'\002'
  while true; do
    get_project_details
    if (( keep_screen )); then echo ""; else clear; fi
    keep_screen=0
    ui_refresh_width
    refresh_device_info
    box_top "android-build"
    box_row "${C_ACCENT}◆${RESET} ${BOLD}${CONFIG_project_name}${RESET}${C_MUTED}${PROJECT_TARGET_TYPE}${RESET}" "${C_MUTED}${PROJECT_VERSION}${RESET}"
    box_row "${C_PRIMARY}▪${RESET} ${CONFIG_package_name}" "${C_MUTED}${PROJECT_SDK}${RESET}"
    if [[ -n "$SELECTED_DEVICE" ]]; then
      box_row "${C_SUCCESS}▸${RESET} ${DEVICE_INFO:-$SELECTED_DEVICE}" "${C_MUTED}${SELECTED_DEVICE}${RESET}"
    else
      box_row "${C_ERROR}▸${RESET} ${C_MUTED}No device${RESET}"
    fi
    if [[ -n "$PROJECT_GIT_BRANCH" ]]; then
      box_row "${C_WARN}±${RESET} ${C_SUCCESS}${PROJECT_GIT_BRANCH}${RESET}  ${PROJECT_GIT_INFO}"
    fi
    box_bottom
    echo ""

    print_section "BUILD"
    if [[ "$CONFIG_show_run_debug" == "true" ]]; then
      print_menu_item "R" "Run & Debug"
    fi
    print_menu_item "I" "Install Debug"
    if has_optimized_build_config; then
      print_menu_item "O" "Optimized debug"
    fi
    print_menu_item "B" "Release build"
    print_menu_item "L" "Logcat"

    print_section "PROJECT"
    print_menu_item "C" "Configure Gradle" "cs cc cp" menu
    print_menu_item "T" "Format code"
    print_menu_item "Y" "Import icons"
    print_menu_item "G" "Git" "gd gb gs gpr gc ga" menu
    print_menu_item "P" "Switch project"

    print_section "DEVICE"
    print_menu_item "A" "App" "as af" menu
    print_menu_item "D" "Devices" "dw dm dp dx" menu

    print_section "OTHER"
    print_menu_item "E" "Open in editor"
    print_menu_item "Q" "Quit"
    echo ""
    read -e -rp "$MAIN_PROMPT" opt
    if [[ -n "$opt" ]]; then
      history -s "$opt"
      history -w "$hist_file" 2>/dev/null || true
    fi

    case "$opt" in
      r|R|1)
        if [[ "$CONFIG_show_run_debug" == "true" ]]; then
          run_and_pause action_run_all
        else
          log_warn "Invalid input."; keep_screen=1
        fi
        ;;
      i|I|2)
        while true; do
          echo ""
          if action_build; then
            action_install || true
          fi
          prompt_reinstall_or_esc || break
        done
        ;;
      o|O)
        if has_optimized_build_config; then
          while true; do
            echo ""
            action_optimized_debug || true
            prompt_reinstall_or_esc || break
          done
        else
          log_warn "Optimized dev build is not configured in this project."; keep_screen=1
        fi
        ;;
      l|L|3) run_and_pause action_logs ;;
      a|A) submenu_run app a ;;
      a[[:space:]]*|A[[:space:]]*|a[a-zA-Z]*|A[a-zA-Z]*) submenu_run app a "${opt:1}" once; keep_screen=1 ;;
      g|G) submenu_run git g ;;
      g[[:space:]]*|G[[:space:]]*|g[a-zA-Z]*|G[a-zA-Z]*) submenu_run git g "${opt:1}" once ;;
      t|T) run_and_pause action_format_code ;;
      c|C) submenu_run gradle c ;;
      c[[:space:]]*|C[[:space:]]*|c[a-zA-Z]*|C[a-zA-Z]*) submenu_run gradle c "${opt:1}" once ;;
      6) run_and_pause action_clean ;;
      b|B) echo ""; action_build_release || read -rp "Press Enter to return..." ;;
      y|Y) run_and_pause action_import_icons ;;
      d|D) submenu_run devices d ;;
      d[[:space:]]*|D[[:space:]]*|d[a-zA-Z0-9]*|D[a-zA-Z0-9]*) submenu_run devices d "${opt:1}" once; keep_screen=1 ;;
      p|P)
        select_project_interactive
        load_config "${CONFIG_FILE:-}"
        select_device
        ;;
      e|E) action_open_editor || true; keep_screen=1 ;;
      q|Q) quit_and_cleanup ;;
      "") ;;
      *) log_warn "Invalid input."; keep_screen=1 ;;
    esac
  done
}

# Kills leftover Gradle/Kotlin daemons and other java processes, sparing apps inside .app bundles (Android Studio etc.).
quit_and_cleanup() {
  local pids=()
  local pid cmd
  while read -r pid; do
    [[ -z "$pid" ]] && continue
    cmd=$(ps -o command= -p "$pid" 2>/dev/null) || continue
    [[ "$cmd" == *".app/Contents/"* ]] && continue
    pids+=("$pid")
  done < <(pgrep -x java)
  if (( ${#pids[@]} > 0 )); then
    echo -e "${C_MUTED}Stopping ${#pids[@]} java process(es)...${RESET}"
    kill "${pids[@]}" 2>/dev/null || true
    sleep 2
    for pid in "${pids[@]}"; do
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    done
  fi
  exit 0
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
  echo -e "  sync                Run Gradle sync & daemon check"
  echo -e "  wifi                Connect to a wireless ADB device"
  echo -e "  devices             List connected devices"
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
    devices_refresh; devices_do_connect ""
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

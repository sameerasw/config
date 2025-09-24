#!/bin/bash
set -euo pipefail

# === UNIVERSAL MAC BUILD SCRIPT ===
# A configurable build script for macOS applications with DMG creation and notarization
# Usage: ./build-mac.sh [config_file] [-y]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG="template.build.config"

# === ARGUMENT PARSING ===
CONFIG_FILE=""
SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -y|--yes)
      SKIP_CONFIRM=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [config_file] [-y|--yes] [-h|--help]"
      echo "  config_file: Path to configuration file (default: template.build.config)"
      echo "  -y, --yes:   Skip confirmation prompts"
      echo "  -h, --help:  Show this help message"
      exit 0
      ;;
    *)
      if [[ -z "$CONFIG_FILE" ]]; then
        CONFIG_FILE="$1"
      else
        echo "Error: Unknown argument '$1'"
        exit 1
      fi
      shift
      ;;
  esac
done

# Set default config file if none provided
if [[ -z "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$DEFAULT_CONFIG"
fi

# Make config file path absolute if relative
if [[ "$CONFIG_FILE" != /* ]]; then
  CONFIG_FILE="$SCRIPT_DIR/$CONFIG_FILE"
fi

# === LOAD CONFIGURATION ===
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Configuration file '$CONFIG_FILE' not found."
  echo "Please create a configuration file or specify a valid path."
  exit 1
fi

# Function to get config value
get_config() {
  local key="$1"
  local default="${2:-}"
  local value=$(grep "^[[:space:]]*$key[[:space:]]*=" "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Remove quotes if present
  if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
    value="${BASH_REMATCH[1]}"
  fi

  echo "${value:-$default}"
}

# Function to parse config file and set variables
parse_config() {
  local config_file="$1"

  # Read all config values
  CONFIG_project_name=$(get_config "project_name")
  CONFIG_project_dir=$(get_config "project_dir")
  CONFIG_output_dir=$(get_config "output_dir")
  CONFIG_skip_confirmation=$(get_config "skip_confirmation" "false")
  CONFIG_steps=$(get_config "steps")
  CONFIG_updates_dir=$(get_config "updates_dir")
  CONFIG_dmg_name=$(get_config "dmg_name")
  CONFIG_background_image=$(get_config "background_image")
  CONFIG_developer_id=$(get_config "developer_id")
  CONFIG_team_id=$(get_config "team_id")
  CONFIG_apple_id_keychain_service=$(get_config "apple_id_keychain_service")
  CONFIG_app_password_keychain_service=$(get_config "app_password_keychain_service")
  CONFIG_sparkle_dir=$(get_config "sparkle_dir")
  CONFIG_dmg_window_size=$(get_config "dmg_window_size" "600,400")
  CONFIG_dmg_icon_size=$(get_config "dmg_icon_size" "128")
  CONFIG_dmg_text_size=$(get_config "dmg_text_size" "16")
}

# Parse the configuration file
parse_config "$CONFIG_FILE"

# === VALIDATE REQUIRED CONFIG ===
if [[ -z "$CONFIG_project_name" ]]; then
  echo "Error: Required configuration 'project_name' is missing from $CONFIG_FILE"
  exit 1
fi

if [[ -z "$CONFIG_project_dir" ]]; then
  echo "Error: Required configuration 'project_dir' is missing from $CONFIG_FILE"
  exit 1
fi

if [[ -z "$CONFIG_output_dir" ]]; then
  echo "Error: Required configuration 'output_dir' is missing from $CONFIG_FILE"
  exit 1
fi

if [[ -z "$CONFIG_steps" ]]; then
  echo "Error: Required configuration 'steps' is missing from $CONFIG_FILE"
  exit 1
fi

# === APPLY CONFIG OVERRIDES ===
if [[ "$CONFIG_skip_confirmation" == "true" ]]; then
  SKIP_CONFIRM=true
fi

# === PARSE STEPS ===
IFS=',' read -ra STEPS <<< "$CONFIG_steps"
NUM_STEPS=${#STEPS[@]}

# Trim whitespace from steps
for i in "${!STEPS[@]}"; do
  STEPS[i]=$(echo "${STEPS[i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
done

# === COLORS ===
RESET="\033[0m"
DIM="\033[2m"
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"

# === UTILITY FUNCTIONS ===
log_info() {
  echo -e "${BLUE}[INFO]${RESET} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${RESET} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${RESET} $1" >&2
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${RESET} $1"
}

print_header() {
  echo
  echo "======================================="
  echo "$CONFIG_project_name Build Script"
  echo "======================================="
  echo "Project: $CONFIG_project_name"
  echo "Project Dir: $CONFIG_project_dir"
  echo "Output Dir: $CONFIG_output_dir"
  echo "Config File: $CONFIG_FILE"
  echo "======================================="
  echo
}

print_progress() {
  local current=$1
  echo
  echo "======================================="
  echo "$CONFIG_project_name Build Progress"
  echo "======================================="
  for ((i=0;i<NUM_STEPS;i++)); do
    if (( i+1 < current )); then
      echo -e "${DIM}✅ ${STEPS[i]}${RESET}"
    elif (( i+1 == current )); then
      echo -e "${YELLOW}➡ ${STEPS[i]}${RESET}"
    else
      echo "   ${STEPS[i]}"
    fi
  done
  echo "======================================="
  echo
}

confirm_action() {
  local message="$1"
  if [ "$SKIP_CONFIRM" = true ]; then
    return 0
  fi
  read -rp "$message [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    return 1
  fi
}

# === BUILD STEP FUNCTIONS ===
cleanup_updates_directory() {
  log_info "Cleaning up updates directory: $CONFIG_output_dir"

  if [[ ! -d "$CONFIG_output_dir" ]]; then
    log_info "Output directory doesn't exist, creating it..."
    mkdir -p "$CONFIG_output_dir"
    return 0
  fi

  cd "$CONFIG_output_dir"
  local files
  files=$(find . -maxdepth 1 ! -name '*.app' ! -name '.')

  if [ -z "$files" ]; then
    log_info "Nothing to delete."
    return 0
  fi

  echo "Files to be deleted:"
  echo "$files"
  echo

  if ! confirm_action "Proceed with deletion of non-.app files?"; then
    log_error "Cleanup aborted."
    exit 1
  fi

  echo "$files" | xargs rm -rf
  log_success "Cleanup complete."
}

build_dmg() {
  log_info "Building DMG package..."
  cd "$CONFIG_output_dir"

  # Get DMG name from config or default
  local dmg_name="${CONFIG_dmg_name:-$CONFIG_project_name.dmg}"

  # Remove existing DMG if it exists
  if [[ -f "$dmg_name" ]]; then
    rm "$dmg_name"
  fi

  # Parse window size from config
  local window_size="$CONFIG_dmg_window_size"
  IFS=',' read -ra window_dims <<< "$window_size"
  local width="${window_dims[0]:-600}"
  local height="${window_dims[1]:-400}"

  # Build create-dmg command with available options
  local cmd=(
    create-dmg
    --volname "$CONFIG_project_name"
    --window-pos 200 120
    --window-size "$width" "$height"
    --icon-size "$CONFIG_dmg_icon_size"
    --icon "$CONFIG_project_name.app" 100 100
    --hide-extension "$CONFIG_project_name.app"
    --app-drop-link 380 100
  )

  # Add background image if specified
  if [[ -n "$CONFIG_background_image" && -f "$CONFIG_background_image" ]]; then
    cmd+=(--background "$CONFIG_background_image")
  fi

  # Add DMG name and source directory
  cmd+=("$dmg_name")
  cmd+=("dmg_src/")

  # Execute the command
  "${cmd[@]}"
  log_success "DMG created successfully."
}

notarize_dmg() {
  log_info "Notarizing DMG..."
  cd "$CONFIG_output_dir"

  local dmg_file="${CONFIG_dmg_name:-$CONFIG_project_name.dmg}"

  # Code sign the DMG
  if [[ -n "$CONFIG_developer_id" ]]; then
    codesign --sign "$CONFIG_developer_id" --timestamp "$dmg_file"
  else
    log_error "developer_id not specified in configuration"
    exit 1
  fi

  # Get credentials from keychain
  local apple_id=""
  local app_password=""

  if [[ -n "$CONFIG_apple_id_keychain_service" ]]; then
    apple_id=$(security find-generic-password -s "$CONFIG_apple_id_keychain_service" -w 2>/dev/null || true)
  fi

  if [[ -n "$CONFIG_app_password_keychain_service" ]]; then
    app_password=$(security find-generic-password -s "$CONFIG_app_password_keychain_service" -w 2>/dev/null || true)
  fi

  # Submit for notarization
  if [[ -n "$apple_id" && -n "$CONFIG_team_id" && -n "$app_password" ]]; then
    xcrun notarytool submit "$dmg_file" \
      --apple-id "$apple_id" \
      --team-id "$CONFIG_team_id" \
      --password "$app_password" \
      --wait
  else
    log_error "Missing notarization credentials. Check keychain services and team_id in config."
    exit 1
  fi

  log_success "DMG notarized successfully."
}

staple_validate_dmg() {
  log_info "Stapling and validating DMG..."
  cd "$CONFIG_output_dir"

  local dmg_file="${CONFIG_dmg_name:-$CONFIG_project_name.dmg}"

  xcrun stapler staple "$dmg_file"
  xcrun stapler validate "$dmg_file"

  log_success "DMG stapled and validated successfully."
}

generate_sparkle_appcast() {
  log_info "Generating Sparkle appcast..."

  local sparkle_dir="$CONFIG_sparkle_dir"

  # Auto-detect Sparkle directory if not specified
  if [[ -z "$sparkle_dir" ]]; then
    sparkle_dir=$(find ~/Library/Developer/Xcode/DerivedData -type d -path "*/SourcePackages/artifacts/sparkle/Sparkle" -print -quit 2>/dev/null || true)
  fi

  if [[ -n "$sparkle_dir" && -d "$sparkle_dir" ]]; then
    cd "$sparkle_dir"
    ./bin/generate_appcast "$CONFIG_output_dir"
  else
    log_error "Sparkle directory not found. Please specify sparkle_dir in config or ensure Sparkle is available in Xcode DerivedData."
    exit 1
  fi

  log_success "Sparkle appcast generated successfully."
}

# === STEP DISPATCHER ===
execute_step() {
  local step_name="$1"
  case "$step_name" in
    "Cleanup updates directory"|"cleanup")
      cleanup_updates_directory
      ;;
    "Build DMG"|"build_dmg"|"dmg")
      build_dmg
      ;;
    "Notarize DMG"|"notarize"|"notarize_dmg")
      notarize_dmg
      ;;
    "Staple & Validate DMG"|"staple"|"validate"|"staple_validate")
      staple_validate_dmg
      ;;
    "Generate Sparkle Appcast"|"appcast"|"sparkle")
      generate_sparkle_appcast
      ;;
    *)
      log_error "Unknown build step: $step_name"
      exit 1
      ;;
  esac
}

# === MAIN EXECUTION ===
main() {
  print_header

  # Validate directories
  if [[ ! -d "$CONFIG_project_dir" ]]; then
    log_error "Project directory not found: $CONFIG_project_dir"
    exit 1
  fi

  # Create output directory if it doesn't exist
  mkdir -p "$CONFIG_output_dir"

  # Execute build steps
  for i in "${!STEPS[@]}"; do
    step_num=$((i+1))
    step_name="${STEPS[i]}"

    print_progress "$step_num"
    log_info "Executing step $step_num: $step_name"

    execute_step "$step_name"

    log_success "Step $step_num completed successfully!"
  done

  print_progress $((NUM_STEPS+1))
  echo -e "${BOLD}${GREEN}🎉 All steps completed successfully!${RESET}"
  echo
  log_info "Build artifacts are available in: $CONFIG_output_dir"
}

# Run main function
main "$@"
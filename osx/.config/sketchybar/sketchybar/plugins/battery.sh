#!/bin/sh

PERCENTAGE="$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)"
CHARGING="$(pmset -g batt | grep 'AC Power')"

if [ "$PERCENTAGE" = "" ]; then
  exit 0
fi

# Using more universally compatible icons
case "${PERCENTAGE}" in
  9[0-9]|100) ICON="🔋"  # Full battery
  ;;
  [6-8][0-9]) ICON="🔋"  # High battery
  ;;
  [3-5][0-9]) ICON="🔋"  # Medium battery
  ;;
  [1-2][0-9]) ICON="🪫"  # Low battery
  ;;
  *) ICON="⚠️"          # Critical battery
esac

if [[ "$CHARGING" != "" ]]; then
  ICON="⚡"              # Charging
fi

# The item invoking this script (name $NAME) will get its icon and label
# updated with the current battery status
sketchybar --set "$NAME" icon="$ICON" label="${PERCENTAGE}%"

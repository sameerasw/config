#!/usr/bin/env bash

# Calculate usage percentage: (Total - Available) / Total * 100, rounded down
USAGE_PERCENTAGE=$(df -k / | awk 'NR==2{printf "%d%%", int(($2 - $4) / $2 * 100)}')

# Set the sketchybar label to the calculated percentage
sketchybar --set $NAME label="$USAGE_PERCENTAGE"
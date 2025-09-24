#!/usr/bin/env bash

if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
  sketchybar --set $NAME background.drawing=on
  sketchybar --set $NAME label.color=0x00000000
else
  sketchybar --set $NAME background.drawing=off
    sketchybar --set $NAME label.color=0xFFffffff
fi
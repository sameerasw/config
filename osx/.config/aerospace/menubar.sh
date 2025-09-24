#!/bin/bash

# Check the current state of the autohide menu bar
CURRENT_STATE=$(osascript -e 'tell application "System Events" to get autohide menu bar of dock preferences')

# Toggle the state
if [ "$CURRENT_STATE" = "true" ]; then
  osascript -e 'tell application "System Events" to set autohide menu bar of dock preferences to false'
  echo "Menu bar autohide disabled."
else
  osascript -e 'tell application "System Events" to set autohide menu bar of dock preferences to true'
  echo "Menu bar autohide enabled."
fi
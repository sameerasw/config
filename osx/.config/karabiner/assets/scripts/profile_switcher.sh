#!/bin/bash

# Define profiles
profiles=("Default" "Caps")

# Read the current profile from a file
current_profile=$(cat ~/.karabiner_profile 2>/dev/null)

# Find the index of the current profile
index=0
for i in "${!profiles[@]}"; do
  if [[ "${profiles[$i]}" == "$current_profile" ]]; then
    index=$I
    break
  fi
done

# Calculate the next profile index
next_index=$(( (index + 1) % ${#profiles[@]} ))

# Set the next profile
next_profile=${profiles[$next_index]}
echo "$next_profile" > ~/.karabiner_profile

# Change the Karabiner profile
/Library/Application\ Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli --select-profile "$next_profile"

# Display a notification
osascript -e "display notification \"$next_profile Profile Activated\" with title \"Karabiner Elements\""
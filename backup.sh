#!/bin/zsh
set -euo pipefail

# Repo root is where this script lives
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$REPO_DIR/osx"

echo "Backing up dotfiles to $BACKUP_DIR"

# Map of source -> destination (relative to $HOME -> relative to $BACKUP_DIR)
declare -A FILES_TO_BACKUP=(
  [".zshrc"]=".zshrc"
  [".vimrc"]=".vimrc"
  [".bashrc"]=".bashrc"
  [".zprofile"]=".zprofile"
  [".profile"]=".profile"
  [".bash_profile"]=".bash_profile"
  [".aliases"]=".aliases"
  [".inputrc"]=".inputrc"
  [".dircolors"]=".dircolors"
  [".config/aerospace-swipe/"]=".config/aerospace-swipe/"
  [".config/aerospace/"]=".config/aerospace/"
  [".config/amethyst/"]=".config/amethyst/"
  [".config/fastfetch/"]=".config/fastfetch/"
  [".config/karabiner"]=".config/karabiner"
  [".config/nvim/"]=".config/nvim/"
  [".config/sketchybar"]=".config/sketchybar"
)

for SRC in "${(@k)FILES_TO_BACKUP}"; do
  DEST_REL="${FILES_TO_BACKUP[$SRC]}"
  SRC_PATH="$HOME/$SRC"
  DEST_PATH="$BACKUP_DIR/$DEST_REL"

  if [[ -e "$SRC_PATH" ]]; then
    mkdir -p "$(dirname "$DEST_PATH")"
    echo "→ Copying $SRC_PATH → $DEST_PATH"
    rsync -a --delete "$SRC_PATH" "$DEST_PATH"
  else
    echo "Skipping $SRC_PATH (not found)"
  fi
done

echo "Backup complete!"


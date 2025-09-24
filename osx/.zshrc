source ~/.zplug/init.zsh


# Get the current hour in 24-hour format
hour=$(date +"%H")

# Define time ranges
morning_start=5    # 5 AM
morning_end=11     # 11 AM
afternoon_start=12 # 12 PM
afternoon_end=17   # 5 PM

# Check the time of day and set a greeting
if [ "$hour" -ge "$morning_start" ] && [ "$hour" -le "$morning_end" ]; then
    greeting="Good morning"
elif [ "$hour" -ge "$afternoon_start" ] && [ "$hour" -le "$afternoon_end" ]; then
    greeting="Good afternoon"
else
    greeting="Good evening"
fi

# Full ASCII art and greeting line
art_and_greeting="✦ $greeting, Sameera! ✦"

# Get terminal width
term_width=$(tput cols)

# Strip ANSI codes if any and get string length
text_length=${#art_and_greeting}

# Calculate padding
padding=$(( (term_width - text_length) / 2 ))

# Print centered art + greeting
printf "%*s%s\n" "$padding" "" "$art_and_greeting"

fastfetch --config minimal





#Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="agnoster"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# defaults
MAGIC_ENTER_GIT_COMMAND='git status -u .'
MAGIC_ENTER_OTHER_COMMAND='ls -lh .'

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
git
zsh-autosuggestions
sudo
web-search
copypath
copybuffer
dirhistory
history
command-not-found
dnf
qrcode
magic-enter
)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
source ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
source ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

alias reload="omz reload"
alias cls="clear"
alias zs="code ~/.zshrc"
alias neofetch="neofetch --source ~/git/dotfiles/8\).txt"
alias android="scrcpy -m 1200 -b 4M -S -t --video-codec=h265 --window-title='Sameera Pixel'"
alias androidw="scrcpy -m 800 -b 2M -e -S --video-codec=h265 --window-title='Sameera Pixel'"
alias androidd="scrcpy -m 750 -w -b 1M --video-codec=h265 --window-title='Sameera Pixel' --new-display=800x1400"
alias gadd="git add ."
alias gcom="git commit -m"
alias gpush="git push"
alias gpull="git pull"
alias glog="git log"
alias gstatus="git status"
alias gdiff="git diff"
alias gclone="git clone"
alias gfetch="git fetch"
alias gremote="git remote set-url origin "
alias macapp="xattr -d com.apple.quarantine "
alias btkill="sudo pkill bluetoothd"
alias arcb="watch -n0.1 killall Dock"
alias noticlear="killall NotificationCenter"
alias nvimpath="cd /opt/homebrew/Cellar/neovim/0.10.2_1/share/nvim/runtime"
alias app-quarantine="xattr -d com.apple.quarantine /Applications/"
alias cdsparkle='cd "$(find ~/Library/Developer/Xcode/DerivedData -type d -path "*/AirSync-*/SourcePackages/artifacts/sparkle/Sparkle" -print -quit)"'
alias cdupdates="cd /Users/sameerasandakelum/GIT/airsync-mac/updates"
alias build-airsync="/Users/sameerasandakelum/git/config/build-mac.sh /Users/sameerasandakelum/GIT/airsync-mac/airsync.build.config"







export CMAKE_PREFIX_PATH="/Users/sameerasandakelum/GIT/synergy-core/deps/qt/6.7.2/macos:$CMAKE_PREFIX_PATH"


# Created by `pipx` on 2024-08-17 12:32:10
export PATH="$PATH:/Users/sameerasandakelum/.local/bin"
export PATH="$PATH:/Library/PostgreSQL/15/bin"
export PATH="$PATH:/opt/scrcpy"
export PATH="$PATH:/Users/sameerasandakelum/dev"
export PATH="$PATH:/Users/sameerasandakelum/git/config"

source /Users/sameerasandakelum/.zlugin/zlugin.zsh

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh











PATH=~/.console-ninja/.bin:$PATH


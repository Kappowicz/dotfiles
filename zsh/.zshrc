# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

#update automatically every 13 days
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 13

#basic plugins that everybody should have
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

#show current directory after 'cd'
function chpwd() {
    # Not in agent shells: Claude Code cds before every command, and the
    # listing landed in front of each result.
    [[ -n $CLAUDECODE ]] && return
    if (( $+commands[lsd] )); then lsd -F; else command ls -F; fi
}

#make 'man' pages colorful
export LESS_TERMCAP_mb=$'\e[1;31m'
export LESS_TERMCAP_md=$'\e[1;31m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;33;44m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[4;1;32m'
export LESS_TERMCAP_mr=$'\e[7m'
export LESS_TERMCAP_mh=$'\e[2m'
export LESS_TERMCAP_ZN=$'\e[74m'
export LESS_TERMCAP_ZV=$'\e[75m'
export LESS_TERMCAP_ZO=$'\e[73m'
export LESS_TERMCAP_ZW=$'\e[75m'
export MANPAGER='less'

#aliases for basic shell commands, each only when its tool is installed
#(all of them are in the Brewfile), so a machine without them keeps working.
if (( $+commands[lsd] )); then
    alias ls='lsd'
    alias l='lsd -l'
    alias la='lsd -a'
    alias lla='lsd -la'
    alias lt='lsd --tree'
fi
if (( $+commands[bat] )); then alias cat='bat --paging=never'; fi
#search everything, including ignored and hidden files. deliberately not named
#'grep': rg takes different flags, so pasted grep commands would misbehave.
if (( $+commands[rg] )); then alias rgg='rg --no-ignore --hidden --glob "!.git"'; fi
if (( $+commands[btop] )); then alias top='btop'; fi
if (( $+commands[duf] )); then alias df='duf'; fi
if (( $+commands[nvim] )); then
    alias vim='nvim'
    alias vi='nvim'
fi

#make history file unlimited in size
HISTSIZE=999999999
SAVEHIST=999999999

setopt APPEND_HISTORY #makes shell append history rather than overwriting it
setopt HIST_IGNORE_ALL_DUPS #don't write the same command twice to history
setopt HIST_REDUCE_BLANKS #delete unnecessary spaces from commands
setopt SHARE_HISTORY #share history between separate shell windows
setopt EXTENDED_HISTORY #save timestamp with each command
setopt HIST_IGNORE_SPACE #a leading space keeps a command (e.g. with a secret) out of history


#simple extract command to make extracting different types easier
extract () {
   if (( $# != 1 )); then
       echo 'Usage: extract <archive>' >&2
       return 2
   fi
   if [ -f "$1" ] ; then
       case $1 in
           *.tar.bz2|*.tar.gz|*.tar|*.tbz2|*.tgz) tar xf "$1" ;;
           *.bz2)       bunzip2 -- "$1" ;;
           *.rar|*.7z)  7zz x -- "$1" ;;
           *.gz)        gunzip -- "$1" ;;
           *.zip)       unzip "$1" ;;
           *.Z)         uncompress "$1" ;;
           *)           echo "'$1' cannot be extracted via extract()" >&2; return 1 ;;
       esac
   else
       echo "'$1' is not a valid file" >&2
       return 1
   fi
}
#java + android sdk — same JDK/SDK that flutter itself uses, so manual
#gradle invocations don't spawn a second daemon with a different JVM.
#guarded, so this file still works on a machine without Android Studio.
if [ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]; then
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi
for _sdk in "$HOMEBREW_PREFIX/share/android-commandlinetools" "$HOME/Library/Android/sdk"; do
    if [ -d "$_sdk" ]; then
        export ANDROID_HOME="$_sdk"
        export PATH="$ANDROID_HOME/platform-tools:$PATH"
        break
    fi
done
unset _sdk

#fzf: ctrl-r history search, ctrl-t files, alt-c cd
if (( $+commands[fzf] )); then source <(fzf --zsh); fi

#zoxide: 'z <fragment>' jumps to frequently used dirs
if (( $+commands[zoxide] )); then eval "$(zoxide init zsh)"; fi

alias agy2="HOME=$HOME/.agy-profile2 agy --dangerously-skip-permissions"

alias agy3="HOME=$HOME/.agy-profile3 agy --dangerously-skip-permissions"

alias agy1="agy --dangerously-skip-permissions"
# limity agentów: kolory, bez nagłówka watch, bez wrap.
# Co minutę: Claude/Cursor/Codex z API, Antigravity z cache (-f; świeży probe: limits -r).
alias wlimits='watch -c -t -n 60 -w -- limits -f'

if [[ -o interactive ]] && [ -t 1 ] && [ -z "$ANTIGRAVITY_AGENT" ] && [ -z "$CLAUDECODE" ]; then
    ls
fi

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
    lsd -F
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

#aliases for basic shell commands
#you have to install: lsd, bat, rg, btop, duf, nvim.
alias ls='lsd'
alias l='lsd -l'
alias la='lsd -a'
alias lla='lsd -la'
alias lt='lsd --tree'
alias cat='bat --paging=never'
alias grep='rg --no-ignore --hidden --glob "!.git"'
alias top='btop'
alias df='duf'
alias vim='nvim'
alias vi='nvim'

#make history file unlimited in size
HISTSIZE=999999999
SAVEHIST=999999999

setopt APPEND_HISTORY #makes shell append history rather than overwriting it
setopt HIST_IGNORE_ALL_DUPS #don't write the same coomand twice to history
setopt HIST_REDUCE_BLANKS #delete unncecessary spaces from commands
setopt SHARE_HISTORY #share history between separate shell windows
setopt EXTENDED_HISTORY #save timestamp with each command


#simple extract command to make extracting different types easier
extract () {
   if [ -f $1 ] ; then
       case $1 in
           *.tar.bz2)   tar xjf $1     ;;
           *.tar.gz)    tar xzf $1     ;;
           *.bz2)       bunzip2 $1     ;;
           *.rar)       unrar x $1     ;;
           *.gz)        gunzip $1      ;;
           *.tar)       tar xf $1      ;;
           *.tbz2)      tar xjf $1     ;;
           *.tgz)       tar xzf $1     ;;
           *.zip)       unzip $1       ;;
           *.Z)         uncompress $1  ;;
           *.7z)        7z x $1        ;;
           *)           echo "'$1' cannot be extracted via extract()" ;;
       esac
   else
       echo "'$1' is not a valid file"
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
source <(fzf --zsh)

#zoxide: 'z <fragment>' jumps to frequently used dirs
eval "$(zoxide init zsh)"



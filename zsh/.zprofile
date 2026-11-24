# Homebrew: /opt/homebrew on Apple Silicon, /usr/local on Intel,
# /home/linuxbrew (or ~/.linuxbrew) on Linux.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
elif [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x "$HOME/.linuxbrew/bin/brew" ]; then
  eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
fi

# User local bin (scripts from this repo land here)
export PATH="$HOME/.local/bin:$PATH"

# Homebrew: /opt/homebrew on Apple Silicon, /usr/local on Intel.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# User local bin (scripts from this repo land here)
export PATH="$HOME/.local/bin:$PATH"

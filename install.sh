#!/usr/bin/env bash
# ==============================================================================
# macOS dotfiles bootstrap
#
# Idempotent: safe to re-run. Anything it replaces is moved aside with a
# .backup-<timestamp> suffix first.
#
#   ./install.sh            # ask for confirmation, then do everything
#   ./install.sh --yes      # no prompt (for unattended use)
#   ./install.sh --no-brew  # skip the Brewfile step
# ==============================================================================

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SUFFIX=".backup-$(date +%Y%m%d%H%M%S)"
ASSUME_YES=0
SKIP_BREW=0

for a in "$@"; do
    case "$a" in
        --yes|-y)   ASSUME_YES=1 ;;
        --no-brew)  SKIP_BREW=1 ;;
        *) printf 'Unknown argument: %s\n' "$a" >&2; exit 2 ;;
    esac
done

echo "Setting up macOS from ${DOTFILES_DIR}"
echo
echo "This will replace the following with symlinks into this repo:"
echo "  ~/.zshrc  ~/.zprofile  ~/.gitconfig  ~/.config/{git/ignore,ghostty,linearmouse,topgrade.toml}"
echo "  ~/.ssh/config  ~/.local/bin/mac-{update,cleanup}  VS Code settings.json"
echo "It also installs Homebrew + everything in Brewfile, oh-my-zsh, and two"
echo "launchd agents that update and clean up weekly."
echo "Existing files are backed up, not deleted."
echo
if [ "$ASSUME_YES" -eq 0 ]; then
    read -r -p "Continue? [y/N] " reply
    case "$reply" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 1 ;; esac
fi

# ------------------------------------------------------------------------------
# 1. Homebrew and packages
# ------------------------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
    echo "==> Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

if [ "$SKIP_BREW" -eq 0 ] && [ -f "${DOTFILES_DIR}/Brewfile" ]; then
    echo "==> Installing packages and applications from Brewfile (this takes a while)..."
    brew bundle --file="${DOTFILES_DIR}/Brewfile" || echo "!! Some packages need manual attention."
fi

# ------------------------------------------------------------------------------
# 2. oh-my-zsh and the plugins .zshrc expects
# ------------------------------------------------------------------------------
# Without these, every new shell errors out on the `source $ZSH/oh-my-zsh.sh`
# line in zsh/.zshrc.
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
if [ ! -d "$ZSH_DIR" ]; then
    echo "==> Installing oh-my-zsh..."
    RUNZSH=no KEEP_ZSHRC=yes sh -c \
        "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    target="${ZSH_DIR}/custom/plugins/${plugin}"
    if [ ! -d "$target" ]; then
        echo "==> Installing ${plugin}..."
        git clone --depth=1 "https://github.com/zsh-users/${plugin}.git" "$target"
    fi
done

# ------------------------------------------------------------------------------
# 3. Target directories
# ------------------------------------------------------------------------------
mkdir -p "$HOME/.config/ghostty" \
         "$HOME/.config/git" \
         "$HOME/.config/linearmouse" \
         "$HOME/.local/bin" \
         "$HOME/.local/state" \
         "$HOME/Library/LaunchAgents" \
         "$HOME/Library/Logs/dotfiles" \
         "$HOME/Library/Application Support/Code/User"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

# ------------------------------------------------------------------------------
# 4. Machine-specific files, generated from templates (never tracked in git)
# ------------------------------------------------------------------------------
if [ ! -f "$HOME/.gitconfig.local" ]; then
    cp "${DOTFILES_DIR}/git/gitconfig.local.example" "$HOME/.gitconfig.local"
    echo "==> Created ~/.gitconfig.local — EDIT IT, it still says 'Your Name'."
    NEEDS_IDENTITY=1
fi
if [ ! -f "${DOTFILES_DIR}/ssh/config" ]; then
    cp "${DOTFILES_DIR}/ssh/config.example" "${DOTFILES_DIR}/ssh/config"
    echo "==> Created ssh/config from the template — edit it for your own hosts."
fi

# ------------------------------------------------------------------------------
# 5. Symlinks
# ------------------------------------------------------------------------------
link_file() {
    local src="$1" dst="$2"

    if [ ! -e "$src" ]; then
        echo "!! Source missing: $src"
        return
    fi
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        echo "   already linked: $dst"
        return
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        echo "   backing up: $dst -> ${dst}${BACKUP_SUFFIX}"
        mv "$dst" "${dst}${BACKUP_SUFFIX}"
    fi
    echo "   linking: $dst"
    ln -s "$src" "$dst"
}

echo "==> Linking configuration files..."
link_file "${DOTFILES_DIR}/zsh/.zshrc"                    "$HOME/.zshrc"
link_file "${DOTFILES_DIR}/zsh/.zprofile"                 "$HOME/.zprofile"
link_file "${DOTFILES_DIR}/git/.gitconfig"                "$HOME/.gitconfig"
link_file "${DOTFILES_DIR}/git/ignore"                    "$HOME/.config/git/ignore"
link_file "${DOTFILES_DIR}/ghostty/config"                "$HOME/.config/ghostty/config"
link_file "${DOTFILES_DIR}/linearmouse/linearmouse.json"  "$HOME/.config/linearmouse/linearmouse.json"
link_file "${DOTFILES_DIR}/topgrade/topgrade.toml"        "$HOME/.config/topgrade.toml"
link_file "${DOTFILES_DIR}/vscode/settings.json"          "$HOME/Library/Application Support/Code/User/settings.json"

link_file "${DOTFILES_DIR}/ssh/config" "$HOME/.ssh/config"
chmod 600 "${DOTFILES_DIR}/ssh/config" 2>/dev/null || true

link_file "${DOTFILES_DIR}/bin/mac-update"  "$HOME/.local/bin/mac-update"
link_file "${DOTFILES_DIR}/bin/mac-cleanup" "$HOME/.local/bin/mac-cleanup"
chmod +x "${DOTFILES_DIR}/bin/mac-update" "${DOTFILES_DIR}/bin/mac-cleanup"

# ------------------------------------------------------------------------------
# 6. LaunchAgents
# ------------------------------------------------------------------------------
echo "==> Installing background jobs (LaunchAgents)..."
for template in "${DOTFILES_DIR}/launchd"/*.plist; do
    [ -f "$template" ] || continue
    name="$(basename "$template")"
    label="${name%.plist}"
    target="$HOME/Library/LaunchAgents/${name}"

    # __HOME__ is a placeholder so the plists work for any user.
    sed "s|__HOME__|$HOME|g" "$template" > "$target"

    launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$target" 2>/dev/null \
        || launchctl load "$target" 2>/dev/null \
        || echo "!! Could not load ${label} — load it manually."
    echo "   installed: ${label}"
done

echo
echo "Done. Restart your terminal, or run: exec zsh"
if [ "${NEEDS_IDENTITY:-0}" -eq 1 ]; then
    echo
    echo "!! Before your first commit, set your name and email in ~/.gitconfig.local"
fi

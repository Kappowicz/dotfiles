#!/usr/bin/env bash
# ==============================================================================
# macOS dotfiles bootstrap (on Linux it hands over to install-linux.sh)
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
if [ "$(uname -s)" = Linux ]; then exec "${DOTFILES_DIR}/install-linux.sh" "$@"; fi
BACKUP_SUFFIX=".backup-$(date +%Y%m%d%H%M%S)"
# Apple Silicon first, then Intel.
BREW_CANDIDATES=(/opt/homebrew/bin/brew /usr/local/bin/brew)
FINISH_MESSAGE="Setup complete. Restart your terminal; see RECOVERY.md for manual steps."
# shellcheck source=bin/lib/install-common.sh
source "${DOTFILES_DIR}/bin/lib/install-common.sh"
ASSUME_YES=0
SKIP_BREW=0
SKIP_CLI=0
SKIP_SETTINGS=0
SKIP_AGENTS=0

for a in "$@"; do
    case "$a" in
        --yes|-y)   ASSUME_YES=1 ;;
        --no-brew)  SKIP_BREW=1 ;;
        --no-cli) SKIP_CLI=1 ;;
        --no-settings) SKIP_SETTINGS=1 ;;
        --no-agents) SKIP_AGENTS=1 ;;
        *) printf 'Unknown argument: %s\n' "$a" >&2; exit 2 ;;
    esac
done

echo "Setting up macOS from ${DOTFILES_DIR}"
echo
echo "This will replace the following with symlinks into this repo:"
echo "  ~/.zshrc  ~/.zprofile  ~/.config/{git/ignore,ghostty,linearmouse,topgrade.toml}"
echo "  ~/.ssh/config  VS Code and Cursor settings.json"
echo "  ~/.local/bin/{mac-update,mac-cleanup,mac-settings,mac-backup,limits}"
echo "  status-line scripts in ~/.claude and ~/.gemini/antigravity-cli"
echo "    (also under ~/.agy-profile2 and ~/.agy-profile3, only if they already exist)"
echo "Existing files are backed up, not deleted."
echo
echo "It also:"
echo "  - installs Homebrew and everything in Brewfile        (skip: --no-brew)"
echo "  - installs the Claude Code, Cursor Agent, Antigravity"
echo "    and Codex CLIs when missing                         (skip: --no-cli)"
echo "  - installs oh-my-zsh and two zsh plugins"
echo "  - creates ~/.gitconfig from a template when missing, and copies default"
echo "    Claude Code, Codex and Antigravity settings where none exist yet"
echo "  - applies the macOS preferences in macos/settings.json (skip: --no-settings)"
echo "  - installs two launchd agents that update and clean"
echo "    up weekly                                           (skip: --no-agents)"
echo
if [ "$ASSUME_YES" -eq 0 ]; then
    read -r -p "Continue? [y/N] " reply
    case "$reply" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 1 ;; esac
fi

if [ "$(uname -s)" != Darwin ]; then echo "This installer requires macOS." >&2; exit 1; fi
if ! xcode-select -p >/dev/null 2>&1; then
    echo "Install Command Line Tools first: xcode-select --install" >&2
    exit 1
fi
trap finish EXIT

# ------------------------------------------------------------------------------
# 1. Homebrew and packages
# ------------------------------------------------------------------------------
# Resolve an existing installation before deciding that Homebrew is missing.
load_brew || true
if [ "$SKIP_BREW" -eq 0 ]; then
    if ! command -v brew >/dev/null 2>&1; then run_step "Homebrew" install_homebrew; fi
    if command -v brew >/dev/null 2>&1 && [ -f "${DOTFILES_DIR}/Brewfile" ]; then
        echo "==> Installing packages and applications from Brewfile (this takes a while)..."
        run_step "Homebrew packages" brew bundle --file="${DOTFILES_DIR}/Brewfile"
    fi
fi

export PATH="$HOME/.local/bin:$PATH"
if [ "$SKIP_CLI" -eq 0 ]; then run_step "Agent CLIs" "${DOTFILES_DIR}/bin/install-cli"; fi

# ------------------------------------------------------------------------------
# 2. oh-my-zsh and the plugins .zshrc expects
# ------------------------------------------------------------------------------
run_step "Oh My Zsh and plugins" install_oh_my_zsh

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
setup_gitconfig
setup_ssh_config

# ------------------------------------------------------------------------------
# 5. Symlinks
# ------------------------------------------------------------------------------
echo "==> Linking configuration files..."
FAILURES_BEFORE=${#FAILED_STEPS[@]}
link_file "${DOTFILES_DIR}/zsh/.zshrc"                    "$HOME/.zshrc"
link_file "${DOTFILES_DIR}/zsh/.zprofile"                 "$HOME/.zprofile"
link_file "${DOTFILES_DIR}/git/ignore"                    "$HOME/.config/git/ignore"
link_file "${DOTFILES_DIR}/ghostty/config"                "$HOME/.config/ghostty/config"
link_file "${DOTFILES_DIR}/linearmouse/linearmouse.json"  "$HOME/.config/linearmouse/linearmouse.json"
link_file "${DOTFILES_DIR}/topgrade/topgrade.toml"        "$HOME/.config/topgrade.toml"
link_file "${DOTFILES_DIR}/vscode/settings.json"          "$HOME/Library/Application Support/Code/User/settings.json"
mkdir -p "$HOME/Library/Application Support/Cursor/User"
link_file "${DOTFILES_DIR}/cursor/settings.json" "$HOME/Library/Application Support/Cursor/User/settings.json"

link_file "${DOTFILES_DIR}/ssh/config" "$HOME/.ssh/config"
chmod 600 "${DOTFILES_DIR}/ssh/config" 2>/dev/null || true

for script in mac-update mac-cleanup mac-settings mac-backup limits; do
    link_file "${DOTFILES_DIR}/bin/$script" "$HOME/.local/bin/$script"
done
group_done "Configuration links and Git include" "$FAILURES_BEFORE"

setup_agent_configs
if [ "$SKIP_SETTINGS" -eq 0 ]; then
    run_step "macOS preferences" "${DOTFILES_DIR}/bin/mac-settings" apply
fi

# ------------------------------------------------------------------------------
# 6. LaunchAgents
# ------------------------------------------------------------------------------
if [ "$SKIP_AGENTS" -eq 0 ]; then
echo "==> Installing background jobs (LaunchAgents)..."
for template in "${DOTFILES_DIR}/launchd"/*.plist; do
    [ -f "$template" ] || continue
    name="$(basename "$template")"
    label="${name%.plist}"
    target="$HOME/Library/LaunchAgents/${name}"

    # __HOME__ is a placeholder so the plists work for any user.
    rendered=$(mktemp)
    # plistlib also escapes home paths containing XML-special characters.
    python3 - "$template" "$rendered" "$HOME" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    data = plistlib.load(source)
def substitute(value):
    if isinstance(value, str): return value.replace('__HOME__', sys.argv[3])
    if isinstance(value, list): return [substitute(v) for v in value]
    if isinstance(value, dict): return {k: substitute(v) for k, v in value.items()}
    return value
with open(sys.argv[2], 'wb') as output:
    plistlib.dump(substitute(data), output)
PY
    if [ -e "$target" ] && ! cmp -s "$rendered" "$target"; then cp -p "$target" "$target${BACKUP_SUFFIX}"; fi
    mv "$rendered" "$target"

    launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
    run_step "LaunchAgent: ${label}" launchctl bootstrap "gui/$(id -u)" "$target"
done
fi

echo
echo "Restart your terminal, or run: exec zsh"
if [ "${NEEDS_IDENTITY:-0}" -eq 1 ]; then
    echo
    echo "!! Before your first commit, set your name and email in ~/.gitconfig"
fi

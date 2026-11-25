#!/usr/bin/env bash
# ==============================================================================
# Linux dotfiles bootstrap (tested on SteamOS; any distro with bash and git)
#
# install.sh hands over to this script on Linux. Same rules as on macOS:
# idempotent, and anything it replaces is moved aside with a .backup-<timestamp>
# suffix first. Everything lands in $HOME, so it survives SteamOS updates,
# which wipe /usr. Nothing here uses the system package manager.
#
#   ./install.sh            # ask for confirmation, then do everything
#   ./install.sh --yes      # no prompt (for unattended use)
#   ./install.sh --no-brew  # skip Homebrew and Brewfile.linux
#   ./install.sh --no-cli   # skip the agent CLIs
# ==============================================================================

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SUFFIX=".backup-$(date +%Y%m%d%H%M%S)"
ASSUME_YES=0
SKIP_BREW=0
SKIP_CLI=0
# Homebrew's two supported Linux prefixes, in the order the installer prefers.
BREW_CANDIDATES=(/home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew")
# SteamOS's deck user has no password, so Homebrew's sudo step cannot work yet.
BREW_FAILURE_HINT="!! Homebrew needs sudo. On SteamOS set a password first (run: passwd), then re-run install.sh."
# shellcheck source=bin/lib/install-common.sh
source "${DOTFILES_DIR}/bin/lib/install-common.sh"

for a in "$@"; do
    case "$a" in
        --yes|-y)   ASSUME_YES=1 ;;
        --no-brew)  SKIP_BREW=1 ;;
        --no-cli)   SKIP_CLI=1 ;;
        # macOS-only steps; accepted so the same command line works on both.
        --no-settings|--no-agents) ;;
        *) printf 'Unknown argument: %s\n' "$a" >&2; exit 2 ;;
    esac
done

echo "Setting up Linux from ${DOTFILES_DIR}"
echo
echo "This will replace the following with symlinks into this repo:"
echo "  ~/.zshrc  ~/.zprofile  ~/.config/git/ignore  ~/.ssh/config"
echo "  ~/.local/bin/limits"
echo "  ~/.config/ghostty/config, only where Ghostty is installed"
echo "  VS Code and Cursor settings.json, only where those editors are installed"
echo "  status-line scripts in ~/.claude and ~/.gemini/antigravity-cli"
echo "    (also under ~/.agy-profile2 and ~/.agy-profile3, only if they already exist)"
echo "Existing files are backed up, not deleted."
echo
echo "It also:"
echo "  - installs Homebrew and everything in Brewfile.linux (skip: --no-brew)"
echo "  - installs the Claude Code, Cursor Agent, Antigravity"
echo "    and Codex CLIs when missing                         (skip: --no-cli)"
echo "  - installs oh-my-zsh and two zsh plugins"
echo "  - creates ~/.gitconfig from a template when missing, and copies default"
echo "    Claude Code, Codex and Antigravity settings where none exist yet"
echo "  - adds Homebrew to ~/.bashrc, so bash (the SteamOS default) finds it too"
echo "It does not change your login shell; the report says how."
echo
if [ "$ASSUME_YES" -eq 0 ]; then
    read -r -p "Continue? [y/N] " reply
    case "$reply" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 1 ;; esac
fi

if [ "$(uname -s)" != Linux ]; then echo "This installer requires Linux." >&2; exit 1; fi
for tool in git curl; do
    if ! command -v "$tool" >/dev/null 2>&1; then echo "Install $tool first." >&2; exit 1; fi
done

trap finish EXIT

# ------------------------------------------------------------------------------
# 1. Homebrew and packages
# ------------------------------------------------------------------------------
load_brew || true
if [ "$SKIP_BREW" -eq 0 ]; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "==> Homebrew asks for sudo once, to create /home/linuxbrew."
        run_step "Homebrew" install_homebrew
    fi
    if command -v brew >/dev/null 2>&1 && [ -f "${DOTFILES_DIR}/Brewfile.linux" ]; then
        echo "==> Installing packages from Brewfile.linux (this takes a while)..."
        run_step "Homebrew packages" brew bundle --file="${DOTFILES_DIR}/Brewfile.linux"
    fi
fi

export PATH="$HOME/.local/bin:$PATH"
if [ "$SKIP_CLI" -eq 0 ]; then run_step "Agent CLIs" "${DOTFILES_DIR}/bin/install-cli"; fi

# ------------------------------------------------------------------------------
# 2. oh-my-zsh and the plugins .zshrc expects
# ------------------------------------------------------------------------------
if command -v zsh >/dev/null 2>&1; then
    run_step "Oh My Zsh and plugins" install_oh_my_zsh
else
    echo "!! zsh is not installed; skipping oh-my-zsh. bash keeps working." >&2
    FAILED_STEPS+=("Oh My Zsh (zsh missing)")
fi

# ------------------------------------------------------------------------------
# 3. Target directories
# ------------------------------------------------------------------------------
mkdir -p "$HOME/.config/git" "$HOME/.local/bin" "$HOME/.local/state"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

# ------------------------------------------------------------------------------
# 4. Machine-specific files, generated from templates (never tracked in git)
# ------------------------------------------------------------------------------
setup_gitconfig
setup_ssh_config
# UseKeychain is macOS-only: Linux OpenSSH refuses to read a config containing
# it, which breaks every ssh and git push. Teach this config to skip it.
if grep -qi '^[[:space:]]*UseKeychain' "${DOTFILES_DIR}/ssh/config" &&
   ! grep -qi '^[[:space:]]*IgnoreUnknown.*UseKeychain' "${DOTFILES_DIR}/ssh/config"; then
    ssh_config_tmp=$(mktemp)
    { echo "IgnoreUnknown UseKeychain"; cat "${DOTFILES_DIR}/ssh/config"; } > "$ssh_config_tmp"
    cat "$ssh_config_tmp" > "${DOTFILES_DIR}/ssh/config"
    rm -f "$ssh_config_tmp"
    echo "==> Added 'IgnoreUnknown UseKeychain' to ssh/config for Linux OpenSSH."
fi

# ------------------------------------------------------------------------------
# 5. Symlinks
# ------------------------------------------------------------------------------
echo "==> Linking configuration files..."
FAILURES_BEFORE=${#FAILED_STEPS[@]}
link_file "${DOTFILES_DIR}/zsh/.zshrc"   "$HOME/.zshrc"
link_file "${DOTFILES_DIR}/zsh/.zprofile" "$HOME/.zprofile"
link_file "${DOTFILES_DIR}/git/ignore"    "$HOME/.config/git/ignore"

# Editors: native package or Flatpak, linked only where the editor has already
# created its settings directory, so a machine without them gets no stray dirs.
for user_dir in "$HOME/.config/Code/User" "$HOME/.var/app/com.visualstudio.code/config/Code/User"; do
    if [ -d "$user_dir" ]; then link_file "${DOTFILES_DIR}/vscode/settings.json" "$user_dir/settings.json"; fi
done
if [ -d "$HOME/.config/Cursor/User" ]; then
    link_file "${DOTFILES_DIR}/cursor/settings.json" "$HOME/.config/Cursor/User/settings.json"
fi

# Ghostty has no Flatpak or Linux Homebrew build; on SteamOS it runs from a
# distrobox and is exported to the app menu. By default it would start the
# container's bash, so a machine-local include makes it start zsh inside the
# container, which shares $HOME and sees Homebrew via a /home/linuxbrew link
# (see README). Not the host's zsh via distrobox-host-exec: that adds a second
# pty layer that echoes every typed character twice. The shared config stays
# identical to macOS.
ghostty_launcher=""
for desktop_file in "$HOME"/.local/share/applications/*ghostty*.desktop; do
    if [ -f "$desktop_file" ]; then ghostty_launcher="$desktop_file"; break; fi
done
if command -v ghostty >/dev/null 2>&1 || [ -n "$ghostty_launcher" ]; then
    mkdir -p "$HOME/.config/ghostty"
    link_file "${DOTFILES_DIR}/ghostty/config" "$HOME/.config/ghostty/config"
    ghostty_local="$HOME/.config/ghostty/local.conf"
    # Only for a distrobox-only Ghostty; a native one uses the host's shell as is.
    if ! command -v ghostty >/dev/null 2>&1 && [ -n "$ghostty_launcher" ] &&
       grep -q '^Exec=.*distrobox-enter' "$ghostty_launcher" && [ ! -e "$ghostty_local" ]; then
        {
            echo "# Written by install-linux.sh: Ghostty runs in a distrobox; start zsh inside it."
            echo "# Needs zsh and the /home/linuxbrew link in the container (see README)."
            echo "# Delete this file if you install Ghostty natively on the host instead."
            echo "command = /usr/bin/zsh -l"
            echo "# Quit with the last window: a lingering single instance keeps the old"
            echo "# config, so changes (like this file) would never apply."
            echo "quit-after-last-window-closed = true"
        } > "$ghostty_local"
        echo "==> Created ~/.config/ghostty/local.conf (Ghostty starts zsh in its distrobox)."
    fi
fi

link_file "${DOTFILES_DIR}/ssh/config" "$HOME/.ssh/config"
chmod 600 "${DOTFILES_DIR}/ssh/config" 2>/dev/null || true

# The mac-* scripts drive Homebrew casks, launchd and `defaults`; only the
# portable one is linked here.
link_file "${DOTFILES_DIR}/bin/limits" "$HOME/.local/bin/limits"
group_done "Configuration links and Git include" "$FAILURES_BEFORE"

setup_agent_configs

# ------------------------------------------------------------------------------
# 6. bash: SteamOS logs in with bash, and Konsole starts it by default
# ------------------------------------------------------------------------------
BASHRC_MARKER="# dotfiles: Homebrew (Linux)"
if ! grep -Fxq "$BASHRC_MARKER" "$HOME/.bashrc" 2>/dev/null; then
    {
        echo
        echo "$BASHRC_MARKER"
        # Literal $ on purpose: these lines are evaluated by bash at startup.
        # shellcheck disable=SC2016
        echo 'for _brew in /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do'
        # shellcheck disable=SC2016
        echo '    if [ -x "$_brew" ]; then eval "$("$_brew" shellenv)"; break; fi'
        echo 'done; unset _brew'
    } >> "$HOME/.bashrc"
fi
COMPLETED_STEPS+=("Homebrew in ~/.bashrc")

echo
if command -v zsh >/dev/null 2>&1 && [ "$(basename "${SHELL:-}")" != zsh ]; then
    echo "To use zsh and these settings by default, either:"
    # -l: a login shell reads ~/.zprofile, which puts Homebrew and ~/.local/bin
    # on PATH (macOS terminals start login shells by default; Konsole does not).
    echo "  - set Konsole's profile command to $(command -v zsh) -l   (Settings -> Edit Current Profile), or"
    echo "  - change your login shell:  chsh -s $(command -v zsh)"
fi
if [ "${NEEDS_IDENTITY:-0}" -eq 1 ]; then
    echo
    echo "!! Before your first commit, set your name and email in ~/.gitconfig"
fi

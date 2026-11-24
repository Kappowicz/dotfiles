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

FAILED_STEPS=()
COMPLETED_STEPS=()
finish() {
    local status=$?
    trap - EXIT
    echo
    echo "Installation report:"
    if [ "${#COMPLETED_STEPS[@]}" -gt 0 ]; then printf '  OK: %s\n' "${COMPLETED_STEPS[@]}"; fi
    if [ "${#FAILED_STEPS[@]}" -gt 0 ]; then
        printf '  FAILED: %s\n' "${FAILED_STEPS[@]}" >&2
        status=1
    fi
    if [ "$status" -ne 0 ]; then
        echo "Setup incomplete. Fix the errors above and re-run install.sh." >&2
    else
        echo "Setup complete. See RECOVERY.md for manual steps."
    fi
    exit "$status"
}
trap finish EXIT
group_done() { # group_done <name> <failures before>
    if [ "${#FAILED_STEPS[@]}" -eq "$2" ]; then COMPLETED_STEPS+=("$1"); fi
}
run_step() {
    local name="$1"
    shift
    if "$@"; then
        COMPLETED_STEPS+=("$name")
    else
        FAILED_STEPS+=("$name")
        echo "!! Failed: $name" >&2
    fi
}
load_brew() {
    local candidate
    for candidate in "${BREW_CANDIDATES[@]}"; do
        if [ -x "$candidate" ]; then eval "$("$candidate" shellenv)"; return 0; fi
    done
    return 1
}

# ------------------------------------------------------------------------------
# 1. Homebrew and packages
# ------------------------------------------------------------------------------
load_brew || true
if [ "$SKIP_BREW" -eq 0 ] && ! command -v brew >/dev/null 2>&1; then
    echo "==> Homebrew not found. Installing (it asks for sudo once, to create /home/linuxbrew)..."
    BREW_INSTALLER=$(mktemp)
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$BREW_INSTALLER"
    if [ "$ASSUME_YES" -eq 1 ]; then
        NONINTERACTIVE=1 /bin/bash "$BREW_INSTALLER"
    else
        /bin/bash "$BREW_INSTALLER"
    fi
    rm -f "$BREW_INSTALLER"
    load_brew || true
fi

if [ "$SKIP_BREW" -eq 0 ] && [ -f "${DOTFILES_DIR}/Brewfile.linux" ]; then
    echo "==> Installing packages from Brewfile.linux (this takes a while)..."
    run_step "Homebrew packages" brew bundle --file="${DOTFILES_DIR}/Brewfile.linux"
fi

export PATH="$HOME/.local/bin:$PATH"
if [ "$SKIP_CLI" -eq 0 ]; then run_step "Agent CLIs" "${DOTFILES_DIR}/bin/install-cli"; fi

# ------------------------------------------------------------------------------
# 2. oh-my-zsh and the plugins .zshrc expects
# ------------------------------------------------------------------------------
ZSH_DIR="$HOME/.oh-my-zsh"
if ! command -v zsh >/dev/null 2>&1; then
    echo "!! zsh is not installed; skipping oh-my-zsh. bash keeps working." >&2
    FAILED_STEPS+=("Oh My Zsh (zsh missing)")
else
    if [ ! -d "$ZSH_DIR" ]; then
        echo "==> Installing oh-my-zsh..."
        OMZ_INSTALLER=$(mktemp)
        curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$OMZ_INSTALLER"
        ZSH="$ZSH_DIR" RUNZSH=no KEEP_ZSHRC=yes CHSH=no sh "$OMZ_INSTALLER"
        rm -f "$OMZ_INSTALLER"
    fi
    for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
        target="${ZSH_DIR}/custom/plugins/${plugin}"
        if [ ! -d "$target" ]; then
            echo "==> Installing ${plugin}..."
            git clone --depth=1 "https://github.com/zsh-users/${plugin}.git" "$target"
        fi
    done
    COMPLETED_STEPS+=("Oh My Zsh and plugins")
fi

# ------------------------------------------------------------------------------
# 3. Target directories
# ------------------------------------------------------------------------------
mkdir -p "$HOME/.config/git" "$HOME/.local/bin" "$HOME/.local/state"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

# ------------------------------------------------------------------------------
# 4. Machine-specific files, generated from templates (never tracked in git)
# ------------------------------------------------------------------------------
# ~/.gitconfig is a real file, not a symlink; see the same step in install.sh.
if [ ! -f "$HOME/.gitconfig" ] || [ -L "$HOME/.gitconfig" ]; then
    if [ -L "$HOME/.gitconfig" ]; then
        echo "   replacing the old ~/.gitconfig symlink with a real file"
        mv "$HOME/.gitconfig" "$HOME/.gitconfig${BACKUP_SUFFIX}"
    fi
    cp "${DOTFILES_DIR}/git/gitconfig.example" "$HOME/.gitconfig"
    git config --file "$HOME/.gitconfig" --replace-all include.path "${DOTFILES_DIR}/git/.gitconfig"
    echo "==> Created ~/.gitconfig — EDIT IT, it still says 'Your Name'."
    NEEDS_IDENTITY=1
fi
if ! git config --file "$HOME/.gitconfig" --get-all include.path | grep -Fxq -- "${DOTFILES_DIR}/git/.gitconfig"; then
    cp -p "$HOME/.gitconfig" "$HOME/.gitconfig${BACKUP_SUFFIX}"
    git config --file "$HOME/.gitconfig" --add include.path "${DOTFILES_DIR}/git/.gitconfig"
fi
if [ ! -f "${DOTFILES_DIR}/ssh/config" ]; then
    if [ -f "$HOME/.ssh/config" ] && [ ! -L "$HOME/.ssh/config" ]; then
        cp "$HOME/.ssh/config" "${DOTFILES_DIR}/ssh/config"
        echo "==> Preserved existing SSH configuration in ssh/config (gitignored)."
    else
        cp "${DOTFILES_DIR}/ssh/config.example" "${DOTFILES_DIR}/ssh/config"
        echo "==> Created ssh/config from the template — edit it for your own hosts."
    fi
fi
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
link_file() {
    local src="$1" dst="$2"

    if [ ! -e "$src" ]; then
        echo "!! Source missing: $src" >&2
        FAILED_STEPS+=("Missing source: $src")
        return 0
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

link_file "${DOTFILES_DIR}/ssh/config" "$HOME/.ssh/config"
chmod 600 "${DOTFILES_DIR}/ssh/config" 2>/dev/null || true

# The mac-* scripts drive Homebrew casks, launchd and `defaults`; only the
# portable one is linked here.
link_file "${DOTFILES_DIR}/bin/limits" "$HOME/.local/bin/limits"
group_done "Configuration links and Git include" "$FAILURES_BEFORE"
FAILURES_BEFORE=${#FAILED_STEPS[@]}

copy_config() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then cp "$src" "$dst"; fi
}
copy_config "${DOTFILES_DIR}/codex/config.toml" "$HOME/.codex/config.toml"
copy_config "${DOTFILES_DIR}/claude/settings.json" "$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude/hooks" "$HOME/.gemini/antigravity-cli"
link_file "${DOTFILES_DIR}/claude/statusline.sh" "$HOME/.claude/statusline.sh"
link_file "${DOTFILES_DIR}/claude/hooks/skill-statusline.sh" "$HOME/.claude/hooks/skill-statusline.sh"
# Extra Antigravity profiles (agy2/agy3) each need their own sign-in, so on
# Linux they are set up only when already present, never created.
agy_profiles=("$HOME")
for extra in "$HOME/.agy-profile2" "$HOME/.agy-profile3"; do
    if [ -d "$extra" ]; then agy_profiles+=("$extra"); fi
done
for profile_home in "${agy_profiles[@]}"; do
    copy_config "${DOTFILES_DIR}/antigravity/settings.json" "$profile_home/.gemini/antigravity-cli/settings.json"
    mkdir -p "$profile_home/.gemini/antigravity-cli"
    link_file "${DOTFILES_DIR}/antigravity/statusline.py" "$profile_home/.gemini/antigravity-cli/statusline.py"
done
group_done "Agent settings and status lines (existing settings preserved)" "$FAILURES_BEFORE"

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
    echo "  - set Konsole's profile command to $(command -v zsh)   (Settings -> Edit Current Profile), or"
    echo "  - change your login shell:  chsh -s $(command -v zsh)"
fi
if [ "${NEEDS_IDENTITY:-0}" -eq 1 ]; then
    echo
    echo "!! Before your first commit, set your name and email in ~/.gitconfig"
fi

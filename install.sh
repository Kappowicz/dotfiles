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
echo "    (also under ~/.agy-profile2 and ~/.agy-profile3, created if missing)"
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
        echo "Setup complete. Restart your terminal; see RECOVERY.md for manual steps."
    fi
    exit "$status"
}
trap finish EXIT
# For groups of link_file calls, which record a missing source themselves:
# report the group as OK only if none was recorded since <failures before>.
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

# ------------------------------------------------------------------------------
# 1. Homebrew and packages
# ------------------------------------------------------------------------------
# Resolve an existing installation before deciding that Homebrew is missing.
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi
if [ "$SKIP_BREW" -eq 0 ] && ! command -v brew >/dev/null 2>&1; then
    echo "==> Homebrew not found. Installing..."
    BREW_INSTALLER=$(mktemp)
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$BREW_INSTALLER"
    if [ "$ASSUME_YES" -eq 1 ]; then
        NONINTERACTIVE=1 /bin/bash "$BREW_INSTALLER"
    else
        /bin/bash "$BREW_INSTALLER"
    fi
    rm -f "$BREW_INSTALLER"
fi
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

if [ "$SKIP_BREW" -eq 0 ] && [ -f "${DOTFILES_DIR}/Brewfile" ]; then
    echo "==> Installing packages and applications from Brewfile (this takes a while)..."
    run_step "Homebrew packages" brew bundle --file="${DOTFILES_DIR}/Brewfile"
fi

export PATH="$HOME/.local/bin:$PATH"
if [ "$SKIP_CLI" -eq 0 ]; then run_step "Agent CLIs" "${DOTFILES_DIR}/bin/install-cli"; fi

# ------------------------------------------------------------------------------
# 2. oh-my-zsh and the plugins .zshrc expects
# ------------------------------------------------------------------------------
# Without these, every new shell errors out on the `source $ZSH/oh-my-zsh.sh`
# line in zsh/.zshrc.
ZSH_DIR="$HOME/.oh-my-zsh"
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
# ~/.gitconfig is a real file, not a symlink: `git config --global` writes to
# that path, and a symlink would point those writes straight into the repo.
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
FAILURES_BEFORE=${#FAILED_STEPS[@]}

# Mutable app configs are real files: tools can save private/machine-specific
# settings without putting those writes into the tracked repository.
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
for profile_home in "$HOME" "$HOME/.agy-profile2" "$HOME/.agy-profile3"; do
    copy_config "${DOTFILES_DIR}/antigravity/settings.json" "$profile_home/.gemini/antigravity-cli/settings.json"
    mkdir -p "$profile_home/.gemini/antigravity-cli"
    link_file "${DOTFILES_DIR}/antigravity/statusline.py" "$profile_home/.gemini/antigravity-cli/statusline.py"
done
group_done "Agent settings and status lines (existing settings preserved)" "$FAILURES_BEFORE"
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

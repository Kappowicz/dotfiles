#!/usr/bin/env bash
# Shared by install.sh (macOS) and install-linux.sh; compatible with macOS bash 3.2.
#
# Callers set DOTFILES_DIR, BACKUP_SUFFIX, ASSUME_YES and BREW_CANDIDATES (the
# brew executables to look for, in order) before sourcing, then use:
#   trap finish EXIT            print the step report when the script ends
#   run_step <name> <cmd...>    run a step, record it, carry on if it fails
#   group_done <name> <before>  record a group of link_file calls as OK
#   link_file <src> <dst>       symlink, moving aside whatever was there
#   copy_config <src> <dst>     copy a default config only where none exists
#   load_brew                   put an existing Homebrew on PATH
#   install_homebrew            run Homebrew's official installer
#   install_oh_my_zsh           oh-my-zsh and the plugins .zshrc expects
#   setup_gitconfig             ~/.gitconfig from the template, with our include
#   setup_ssh_config            ssh/config from ~/.ssh/config or the template
#   setup_agent_configs         agent defaults and status-line links
# Optional: FINISH_MESSAGE (the report's success line) and BREW_FAILURE_HINT
# (printed when installing Homebrew fails).

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
        echo "${FINISH_MESSAGE:-Setup complete. See RECOVERY.md for manual steps.}"
    fi
    exit "$status"
}

# For groups of link_file calls, which record a missing source themselves:
# report the group as OK only if none was recorded since <failures before>.
group_done() { # group_done <name> <failures before>
    if [ "${#FAILED_STEPS[@]}" -eq "$2" ]; then COMPLETED_STEPS+=("$1"); fi
}

# set -e does not apply inside the command run here, so step functions must
# return non-zero themselves when something fails.
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

# Mutable app configs are real files: tools can save private/machine-specific
# settings without putting those writes into the tracked repository.
copy_config() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then cp "$src" "$dst"; fi
}

load_brew() {
    local candidate
    for candidate in "${BREW_CANDIDATES[@]}"; do
        if [ -x "$candidate" ]; then eval "$("$candidate" shellenv)"; return 0; fi
    done
    return 1
}

install_homebrew() {
    local installer status=0
    echo "==> Homebrew not found. Installing..."
    installer=$(mktemp) || return 1
    if curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
        if [ "$ASSUME_YES" -eq 1 ]; then
            NONINTERACTIVE=1 /bin/bash "$installer" || status=1
        else
            /bin/bash "$installer" || status=1
        fi
    else
        status=1
    fi
    rm -f "$installer"
    load_brew || status=1
    if [ "$status" -ne 0 ] && [ -n "${BREW_FAILURE_HINT:-}" ]; then
        echo "$BREW_FAILURE_HINT" >&2
    fi
    return "$status"
}

# Without these, every new shell errors out on the `source $ZSH/oh-my-zsh.sh`
# line in zsh/.zshrc.
install_oh_my_zsh() {
    local zsh_dir="$HOME/.oh-my-zsh" installer plugin target
    if [ ! -d "$zsh_dir" ]; then
        echo "==> Installing oh-my-zsh..."
        installer=$(mktemp) || return 1
        if ! curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$installer" ||
           ! ZSH="$zsh_dir" RUNZSH=no KEEP_ZSHRC=yes CHSH=no sh "$installer"; then
            rm -f "$installer"
            return 1
        fi
        rm -f "$installer"
    fi
    for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
        target="${zsh_dir}/custom/plugins/${plugin}"
        if [ ! -d "$target" ]; then
            echo "==> Installing ${plugin}..."
            git clone --depth=1 "https://github.com/zsh-users/${plugin}.git" "$target" || return 1
        fi
    done
}

# ~/.gitconfig is a real file, not a symlink: `git config --global` writes to
# that path, and a symlink would point those writes straight into the repo.
# Sets NEEDS_IDENTITY=1 when it creates the file from the template.
setup_gitconfig() {
    local include="${DOTFILES_DIR}/git/.gitconfig"
    if [ ! -f "$HOME/.gitconfig" ] || [ -L "$HOME/.gitconfig" ]; then
        if [ -L "$HOME/.gitconfig" ]; then
            echo "   replacing the old ~/.gitconfig symlink with a real file"
            mv "$HOME/.gitconfig" "$HOME/.gitconfig${BACKUP_SUFFIX}"
        fi
        cp "${DOTFILES_DIR}/git/gitconfig.example" "$HOME/.gitconfig"
        git config --file "$HOME/.gitconfig" --replace-all include.path "$include"
        echo "==> Created ~/.gitconfig — EDIT IT, it still says 'Your Name'."
        # shellcheck disable=SC2034  # read by the caller's closing message
        NEEDS_IDENTITY=1
    fi
    if ! git config --file "$HOME/.gitconfig" --get-all include.path | grep -Fxq -- "$include"; then
        cp -p "$HOME/.gitconfig" "$HOME/.gitconfig${BACKUP_SUFFIX}"
        git config --file "$HOME/.gitconfig" --add include.path "$include"
    fi
}

setup_ssh_config() {
    if [ -f "${DOTFILES_DIR}/ssh/config" ]; then return 0; fi
    if [ -f "$HOME/.ssh/config" ] && [ ! -L "$HOME/.ssh/config" ]; then
        cp "$HOME/.ssh/config" "${DOTFILES_DIR}/ssh/config"
        echo "==> Preserved existing SSH configuration in ssh/config (gitignored)."
    else
        cp "${DOTFILES_DIR}/ssh/config.example" "${DOTFILES_DIR}/ssh/config"
        echo "==> Created ssh/config from the template — edit it for your own hosts."
    fi
}

setup_agent_configs() {
    local before=${#FAILED_STEPS[@]} extra profile_home
    copy_config "${DOTFILES_DIR}/codex/config.toml" "$HOME/.codex/config.toml"
    copy_config "${DOTFILES_DIR}/claude/settings.json" "$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude/hooks"
    link_file "${DOTFILES_DIR}/claude/statusline.sh" "$HOME/.claude/statusline.sh"
    link_file "${DOTFILES_DIR}/claude/hooks/skill-statusline.sh" "$HOME/.claude/hooks/skill-statusline.sh"
    # Extra Antigravity profiles (agy2/agy3) each need their own sign-in, so
    # they are set up only when already present, never created. Sign in with
    # `agy2` / `agy3` first, then re-run install.sh to add their status line.
    local profiles=("$HOME")
    for extra in "$HOME/.agy-profile2" "$HOME/.agy-profile3"; do
        if [ -d "$extra" ]; then profiles+=("$extra"); fi
    done
    for profile_home in "${profiles[@]}"; do
        copy_config "${DOTFILES_DIR}/antigravity/settings.json" "$profile_home/.gemini/antigravity-cli/settings.json"
        link_file "${DOTFILES_DIR}/antigravity/statusline.py" "$profile_home/.gemini/antigravity-cli/statusline.py"
    done
    group_done "Agent settings and status lines (existing settings preserved)" "$before"
}

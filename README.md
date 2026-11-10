# macOS Dotfiles

Personal macOS setup: shell configuration, a package/application inventory,
editor and terminal settings, agent CLIs, saved macOS preferences, and two
scheduled maintenance jobs. See [RECOVERY.md](RECOVERY.md) for the full reset
checklist and private-data backup procedure.

> These are **my** dotfiles. They are generic enough to fork, but `install.sh`
> replaces files in your home directory and installs background jobs. Read it
> before you run it, and fill in the placeholders below — otherwise you will
> commit as someone else.

---

## Requirements

- macOS on Apple Silicon or Intel (Homebrew is detected either way)
- Command Line Tools: `xcode-select --install`
- Roughly 20 GB of disk and a good hour — the `Brewfile` pulls Android Studio,
  Flutter and a number of GUI apps. Trim it to taste first.

## Fill these in before installing

| Where | What to change |
| --- | --- |
| `git/gitconfig.example` | Your name and email. Becomes `~/.gitconfig` on first run — a real file, never tracked. |
| `ssh/config.example` | Your own hosts. Copied to `ssh/config` on first run, which is gitignored. |
| `Brewfile` | The application list is mine. Remove what you do not want. |
| `bin/mac-update` | `SKIP_CASKS` — casks to hold back, e.g. a toolchain pinned by your CI. |
| `bin/mac-cleanup` | `PROJECTS_DIR` if your checkouts do not live in `~/Projects`. |
| `bin/mac-*` | `BATTERY_MIN` — battery percentage above which the jobs may run unplugged (65). |
| `launchd/*.plist` | The hours the jobs run (12:00 and 13:00 by default). |

## Install

```bash
git clone https://github.com/Kappowicz/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

The script asks for confirmation, then:

1. Installs **Homebrew** if missing, and everything in the `Brewfile`.
2. Installs Claude Code, Cursor Agent, Antigravity CLI and Codex CLI when missing.
3. Installs **oh-my-zsh** plus `zsh-autosuggestions` and `zsh-syntax-highlighting`,
   which `.zshrc` expects.
4. Creates `~/.gitconfig` and `ssh/config` when needed, preserves an existing
   SSH configuration, and ensures existing Git configs include shared settings.
5. Symlinks the configs into place, backing up anything already there as
   `<file>.backup-<timestamp>`.
6. Copies portable agent defaults on fresh machines and links status-line hooks.
   Existing agent config files are preserved so local trust/auth settings stay local.
7. Restores the preferences in `macos/settings.json`, backing up changed domains
   under `~/.local/state/dotfiles/preferences/`.
8. Installs two launchd agents, resolving `__HOME__` to the current user.
9. Prints an installation report and returns nonzero if a recorded step fails.

Flags: `--yes` skips the prompt; `--no-brew` skips Homebrew installation and
packages; `--no-cli`, `--no-settings`, and `--no-agents` skip the respective steps.
The shell/config step still runs with these flags.

CLI installers follow the official [Claude Code](https://code.claude.com/docs/en/setup),
[Cursor](https://prod.cursor.com/docs/cli/installation),
[Antigravity](https://www.antigravity.google/docs/cli/install/) and
[OpenAI Codex](https://developers.openai.com/cookbook/examples/codex/using_goals_in_codex)
instructions. Existing installations are not migrated or upgraded by bootstrap.

---

## Layout

```text
dotfiles/
├── Brewfile                  # Homebrew formulae, casks and VS Code extensions
├── install.sh                # Idempotent bootstrap
├── zsh/
│   ├── .zshrc                # Aliases (only for installed tools), history, fzf, zoxide, extract()
│   └── .zprofile             # PATH and Homebrew init
├── git/
│   ├── .gitconfig            # Shared settings, included by ~/.gitconfig
│   ├── gitconfig.example     # Template for ~/.gitconfig (identity lives there)
│   └── ignore                # Global gitignore
├── ghostty/config            # Terminal (Citruszest theme)
├── linearmouse/              # Pointer acceleration and reversed scrolling
├── topgrade/topgrade.toml    # Update tool configuration
├── vscode/settings.json      # Dart/Flutter settings
├── cursor/settings.json      # Cursor editor preferences
├── claude/                   # Portable settings, status line and hook
├── codex/config.toml         # Portable defaults without project trust paths
├── antigravity/              # CLI settings and portable quota status line
├── macos/settings.json       # Allowlisted macOS and Rectangle preferences
├── exports/README.md         # App export/import instructions
├── RECOVERY.md               # Reset and private-data recovery checklist
├── tests/                    # Isolated regression checks
├── .github/workflows/        # The same checks on every push
├── ssh/config.example        # SSH template — the real config stays local
├── bin/
│   ├── mac-update            # Weekly updates via topgrade
│   ├── mac-cleanup           # Weekly disk cleanup
│   ├── install-cli           # Native installers + npm Codex installation
│   ├── mac-settings          # Export/apply macOS preferences
│   ├── mac-backup            # Encrypted private configuration backup
│   └── limits                # Agent quota dashboard (Python standard library)
└── launchd/                  # Agent templates for the two scripts
```

## Maintenance jobs

Both run daily from launchd but gate themselves: real work happens about once a
week, only on mains power or a battery above 65%, and never while a build or
emulator is detected (the cleanup checks emulators). Idle Gradle daemons are
checked through installed distributions' `--status`; an unreadable status skips
maintenance conservatively. A missed slot costs a day, not the week. Logs land in
`~/Library/Logs/dotfiles/` and are trimmed to their newest part past 1 MB.

```bash
BATTERY_MIN=80 mac-update      # raise the bar for one run
```

```bash
mac-update --dry-run     # show what would be upgraded
mac-cleanup --dry-run    # show what would be deleted
mac-cleanup --force      # ignore the gates and run now
mac-update --force       # same; in a terminal it also offers pinned casks
                         # and `sudo mas upgrade` — one question, one password
```

`--force` bypasses power/time gates, while build/emulator guards still apply.
Only one of the two jobs runs at a time (lock in `~/.local/state/`), so a forced
run never overlaps the scheduled one. Each logged run starts with a dated
`=== ... ===` line.
Failed jobs preserve error output and do not record a successful run, so they
can retry at the next daily slot. Gradle transforms are left to Gradle's cleanup.
Ollama is declared as a Homebrew service and starts after bootstrap.

## Day-to-day

Refresh the package list after installing something new:

```bash
brew bundle dump --file=/tmp/Brewfile.current --force
diff -u ~/dotfiles/Brewfile /tmp/Brewfile.current
```

Review the diff and update the checked-in list, preserving service declarations.
The Brewfile installs current available versions; it is not a version lockfile.

Refresh saved macOS preferences with `mac-settings export`; preview restoration
with `mac-settings apply --dry-run`. Refresh private app exports as described in
[exports/README.md](exports/README.md).

Since shell/editor configs are symlinked, editing `~/.zshrc` edits the repo directly:

```bash
cd ~/dotfiles && git add . && git commit -m "Update configs" && git push
```

## Security

`.gitignore` blocks SSH private keys, `*.pem`, `*.key`, tokens and `.env*`.
Machine-specific files — `~/.gitconfig` and `ssh/config` — stay untracked.
Agent defaults exclude account tokens, project trust lists and private workspace
context. CLI apps write to real local config files, not the tracked defaults.
Keep app exports in gitignored `exports/private/`; `mac-backup` encrypts selected
private files with `age` without creating a plaintext archive on disk.
Ignore patterns are a convenience, not a guarantee: review staged changes before
committing. See [RECOVERY.md](RECOVERY.md) for backup coverage and exclusions.

`~/.gitconfig` is deliberately a real file that *includes* `git/.gitconfig`,
rather than a symlink to it. `git config --global ...` writes to that path, so a
symlink would let any tool that sets a global option quietly edit a tracked file
and put your name and email into the next commit.

On GitHub, turn on *Settings → Emails → Keep my email address private* and
*Block command line pushes that expose my email* before your first commit.

## License

MIT — see [LICENSE](LICENSE).

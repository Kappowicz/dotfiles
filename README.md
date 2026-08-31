# macOS Dotfiles

Personal macOS setup: shell configuration, a `Brewfile` with every package and
application, editor and terminal settings, and two scheduled maintenance jobs.

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
| `git/gitconfig.local.example` | Your name and email. Copied to `~/.gitconfig.local` on first run; that file is never tracked. |
| `ssh/config.example` | Your own hosts. Copied to `ssh/config` on first run, which is gitignored. |
| `Brewfile` | The application list is mine. Remove what you do not want. |
| `bin/mac-update` | `SKIP_CASKS` — casks to hold back, e.g. a toolchain pinned by your CI. |
| `bin/mac-cleanup` | `PROJECTS_DIR` if your checkouts do not live in `~/Projects`. |
| `launchd/*.plist` | The hours the jobs run (12:00 and 13:00 by default). |

## Install

```bash
git clone https://github.com/Kappowicz/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

The script asks for confirmation, then:

1. Installs **Homebrew** if missing, and everything in the `Brewfile`.
2. Installs **oh-my-zsh** plus `zsh-autosuggestions` and `zsh-syntax-highlighting`,
   which `.zshrc` expects.
3. Creates `~/.gitconfig.local` and `ssh/config` from their `.example` templates.
4. Symlinks the configs into place, backing up anything already there as
   `<file>.backup-<timestamp>`.
5. Installs two launchd agents, resolving `__HOME__` to the current user.

Flags: `--yes` skips the prompt, `--no-brew` skips the package step.

---

## Layout

```text
dotfiles/
├── Brewfile                  # Homebrew formulae, casks and VS Code extensions
├── install.sh                # Idempotent bootstrap
├── zsh/
│   ├── .zshrc                # Aliases, history, fzf, zoxide, extract()
│   └── .zprofile             # PATH and Homebrew init
├── git/
│   ├── .gitconfig            # Settings only; identity is included from ~/.gitconfig.local
│   ├── gitconfig.local.example
│   └── ignore                # Global gitignore
├── ghostty/config            # Terminal (Citruszest theme)
├── linearmouse/              # Pointer acceleration and reversed scrolling
├── topgrade/topgrade.toml    # Update tool configuration
├── vscode/settings.json      # Dart/Flutter settings
├── ssh/config.example        # SSH template — the real config stays local
├── bin/
│   ├── mac-update            # Weekly updates via topgrade
│   └── mac-cleanup           # Weekly disk cleanup
└── launchd/                  # Agent templates for the two scripts
```

## Maintenance jobs

Both run daily from launchd but gate themselves: real work happens about once a
week, only on AC power, and never while a build or emulator is running. A missed
slot costs a day, not the week. Logs land in `~/Library/Logs/dotfiles/`.

```bash
mac-update --dry-run     # show what would be upgraded
mac-cleanup --dry-run    # show what would be deleted
mac-cleanup --force      # ignore the gates and run now
```

## Day-to-day

Refresh the package list after installing something new:

```bash
brew bundle dump --file=~/dotfiles/Brewfile --force
```

Since everything is symlinked, editing `~/.zshrc` edits the repo directly:

```bash
cd ~/dotfiles && git add . && git commit -m "Update configs" && git push
```

## Security

`.gitignore` blocks SSH private keys, `*.pem`, `*.key`, tokens and `.env*`.
Machine-specific files — `~/.gitconfig.local` and `ssh/config` — are generated
from `.example` templates and never tracked, so no identity, host or address
from a real machine ends up in this repository.

On GitHub, turn on *Settings → Emails → Keep my email address private* and
*Block command line pushes that expose my email* before your first commit.

## License

MIT — see [LICENSE](LICENSE).

# Mac recovery checklist

## Before resetting

- Commit the intended dotfiles changes and ensure a copy exists off this Mac.
  Uncommitted changes and an archive saved only on this disk will be lost.
- Refresh the package inventory with `brew bundle dump` to a temporary file,
  then compare it with `Brewfile`. Preserve explicit entries such as
  `brew "ollama", restart_service: true`, rather than blindly overwriting them.
- Capture current macOS preferences: `./bin/mac-settings export`.
- Export Raycast and any app-specific settings as described in
  [exports/README.md](exports/README.md).
- Preview private backup contents: `./bin/mac-backup --dry-run`.
- Create an encrypted backup on an external disk, supplying any extra files
  relative to your home directory:

  ```bash
  ./bin/mac-backup /Volumes/Backup/mac-private.tar.gz.age \
      Projects/my-app/android/key.properties \
      Projects/my-app/android/upload-keystore.jks
  ```

  Only add paths that actually apply to your projects. The script includes SSH,
  local Git identity, rclone/GitHub configuration, selected CLI credentials and
  settings, user skills, Claude Code project memory and `exports/private`. It
  does not back up all projects,
  app databases, VMs or documents. Use Time Machine or a separate data backup
  for those. Keep the archive passphrase separately, and test decryption before
  erasing the disk:

  ```bash
  age --decrypt /Volumes/Backup/mac-private.tar.gz.age | tar -tzf -
  ```

- Back up required signing certificates and their private keys from Keychain
  Access as password-protected `.p12` files. Include them in the encrypted
  backup using an extra HOME-relative path, or store them separately.
- Check iCloud Keychain sync/password-manager access and recovery codes.
  A file backup cannot reconstruct credentials that exist only in Keychain.
- Save required VM files and confirm access to VMware downloads/licences.

## After installing macOS

1. Sign in to Apple ID/iCloud as needed and install Command Line Tools:
   `xcode-select --install`. Wait for installation to finish.
2. Restore or clone this repo to `~/dotfiles`.
3. If using the private backup, install `age`, then decrypt into a staging
   directory and inspect the files before copying them into your home:

   ```bash
   mkdir -p ~/restore-private
   age --decrypt /Volumes/Backup/mac-private.tar.gz.age \
       | tar -xzf - -C ~/restore-private
   ```

   Restore `.ssh`, `.gitconfig`, rclone configuration and needed settings from
   the staging directory. The archived `.ssh/config` is a real file because
   the backup follows symlinks. The installer preserves it in its gitignored
   `ssh/config`. If restoring to a different username or repo location, check
   machine-specific paths before using them. Restore signing keys to their
   original project paths and import `.p12` certificates into Keychain Access.
   Authentication tokens may expire; sign in again when necessary.
4. Run `cd ~/dotfiles && ./install.sh`. Fix any `FAILED` steps and rerun until
   the installation report is successful. Existing real agent settings are
   preserved; fresh machines receive the checked-in defaults.
5. Restart the terminal. Check `git config user.name` and `git config user.email`
   and replace any template identity before committing.
6. Sign in to GitHub (`gh auth login`), Claude Code, Codex, Cursor Agent and
   Antigravity. Sign in separately for `agy2` and `agy3` if you use those profiles.
   Verify the corresponding profile status-line settings before using `limits`.
7. Import Raycast/Rectangle exports and restore browser sync, Google Drive,
   VPN settings and other app accounts. Restore custom widgets from your data
   backup; this repo installs Übersicht but does not include the private
   `grafana.jsx` widget.
8. Install **Xcode** from the App Store if needed, **VMware Fusion** from the
   vendor, and rebuild apps that do not come from Homebrew from your own
   private repositories. Google Docs/Sheets/Slides shortcuts can be recreated
   from the browser. macOS builtin Safari needs no package entry.
9. Open the relevant apps and grant Accessibility, Screen Recording,
   Full Disk Access and login/background-item permissions where needed.
   Preferences may require relaunching Finder/Dock or logging out.
10. Verify the maintenance agents and their logs:

    ```bash
    launchctl print gui/$(id -u)/local.dotfiles.update
    launchctl print gui/$(id -u)/local.dotfiles.cleanup
    mac-update --dry-run
    mac-cleanup --dry-run
    brew services list
    ```

Android/Flutter toolchain provisioning is intentionally outside this recovery
workflow. The existing Brewfile entries and shell configuration remain available.

## Checks for repository changes

```bash
shellcheck -x install.sh bin/mac-update bin/mac-cleanup bin/install-cli \
    bin/mac-backup bin/lib/maintenance.sh claude/statusline.sh claude/hooks/skill-statusline.sh
bash -n install.sh bin/mac-update bin/mac-cleanup bin/install-cli bin/mac-backup claude/statusline.sh claude/hooks/skill-statusline.sh
zsh -n zsh/.zshrc zsh/.zprofile
plutil -lint launchd/*.plist
python3 -m unittest discover -s tests -v
```

The regression tests use temporary home directories and mock installers and
updaters. They do not replace a full trial restore on a clean Mac.

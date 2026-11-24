"""Linux installer checks in a temporary HOME; no real installs or network."""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform.startswith('linux'), 'install-linux.sh runs only on Linux')
class LinuxInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dotfiles-linux-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.home = self.root / 'home & spaces'
        self.home.mkdir()
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        for name in ['bin', 'zsh', 'git', 'ghostty', 'vscode', 'cursor', 'claude', 'codex', 'antigravity']:
            shutil.copytree(REPO / name, self.repo / name)
        (self.repo / 'ssh').mkdir()
        shutil.copy2(REPO / 'ssh/config.example', self.repo / 'ssh/config.example')
        for name in ['install.sh', 'install-linux.sh', 'Brewfile.linux']:
            shutil.copy2(REPO / name, self.repo / name)
        self.mock = self.root / 'mock'
        self.mock.mkdir()
        self.log = self.root / 'commands.log'
        self.env = dict(os.environ, HOME=str(self.home), SHELL='/bin/bash',
                        PATH=f'{self.mock}:/usr/bin:/bin', MOCK_LOG=str(self.log))
        self.stub('brew', '''
printf '%s\\n' "$*" >> "$MOCK_LOG"
if [ "${1:-}" = shellenv ]; then exit 0; fi
if [ "${1:-}" = bundle ]; then exit "${BREW_FAIL:-0}"; fi
exit 0
''')
        # Point the installer at the mock instead of any real Homebrew prefix.
        p = self.repo / 'install-linux.sh'
        p.write_text(p.read_text().replace(
            'BREW_CANDIDATES=(/home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew")',
            f'BREW_CANDIDATES=("{self.mock}/brew")'))
        for plugin in ['zsh-autosuggestions', 'zsh-syntax-highlighting']:
            (self.home / '.oh-my-zsh/custom/plugins' / plugin).mkdir(parents=True)

    def stub(self, name, body):
        p = self.mock / name
        p.write_text('#!/bin/bash\n' + body + '\n')
        p.chmod(0o755)

    def install(self, *args, **variables):
        return subprocess.run(['/bin/bash', str(self.repo / 'install.sh'), '--yes', *args],
                              env=dict(self.env, **variables), capture_output=True, text=True, timeout=60)

    def test_install_sh_hands_over_and_links_shell_config(self):
        r = self.install('--no-brew', '--no-cli', '--no-settings', '--no-agents')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('Setting up Linux', r.stdout)
        for name, target in [('.zshrc', 'zsh/.zshrc'), ('.zprofile', 'zsh/.zprofile'),
                             ('.config/git/ignore', 'git/ignore'), ('.local/bin/limits', 'bin/limits')]:
            self.assertEqual(os.readlink(self.home / name), str(self.repo / target))
        self.assertFalse((self.home / '.local/bin/mac-update').exists())
        self.assertFalse((self.home / 'Library').exists())

    def test_install_is_idempotent_and_preserves_identity(self):
        gitconfig = self.home / '.gitconfig'
        gitconfig.write_text('[user]\n name = Existing User\n email = test@example.invalid\n')
        bashrc = self.home / '.bashrc'
        bashrc.write_text('# existing\n')
        for _ in range(2):
            r = self.install('--no-brew', '--no-cli')
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('Existing User', gitconfig.read_text())
        self.assertEqual(gitconfig.read_text().count(str(self.repo / 'git/.gitconfig')), 1)
        self.assertEqual(bashrc.read_text().count('# dotfiles: Homebrew (Linux)'), 1)
        self.assertTrue(bashrc.read_text().startswith('# existing\n'))
        self.assertEqual(len(list(self.home.rglob('*.backup-*'))), 1)  # only the first include edit

    def test_bashrc_snippet_is_valid_bash(self):
        r = self.install('--no-brew', '--no-cli')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        check = subprocess.run(['bash', '-n', str(self.home / '.bashrc')], capture_output=True, text=True)
        self.assertEqual(check.returncode, 0, check.stderr)

    def test_ssh_config_from_template_is_accepted_by_openssh(self):
        r = self.install('--no-brew', '--no-cli')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        if shutil.which('ssh') is None:
            self.skipTest('ssh not installed')
        check = subprocess.run(['ssh', '-G', '-F', str(self.home / '.ssh/config'), 'example.invalid'],
                               capture_output=True, text=True)
        self.assertEqual(check.returncode, 0, check.stderr)

    def test_existing_ssh_config_with_usekeychain_is_fixed_once(self):
        ssh = self.home / '.ssh'
        ssh.mkdir()
        (ssh / 'config').write_text('Host *\n    UseKeychain yes\n')
        for _ in range(2):
            r = self.install('--no-brew', '--no-cli')
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        text = (self.repo / 'ssh/config').read_text()
        self.assertTrue(text.startswith('IgnoreUnknown UseKeychain\n'))
        self.assertEqual(text.count('IgnoreUnknown'), 1)

    def test_editor_settings_linked_only_where_editor_exists(self):
        (self.home / '.config/Code/User').mkdir(parents=True)
        r = self.install('--no-brew', '--no-cli')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue((self.home / '.config/Code/User/settings.json').is_symlink())
        self.assertFalse((self.home / '.config/Cursor').exists())

    def test_existing_agent_config_is_preserved(self):
        p = self.home / '.claude/settings.json'
        p.parent.mkdir()
        p.write_text('{"theme":"existing"}\n')
        r = self.install('--no-brew', '--no-cli')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(p.read_text(), '{"theme":"existing"}\n')

    def test_extra_agy_profiles_are_not_created(self):
        r = self.install('--no-brew', '--no-cli')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue((self.home / '.gemini/antigravity-cli/statusline.py').is_symlink())
        self.assertFalse((self.home / '.agy-profile2').exists())
        self.assertFalse((self.home / '.agy-profile3').exists())

    def test_existing_extra_agy_profile_is_configured(self):
        (self.home / '.agy-profile2').mkdir()
        r = self.install('--no-brew', '--no-cli')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue((self.home / '.agy-profile2/.gemini/antigravity-cli/statusline.py').is_symlink())
        self.assertFalse((self.home / '.agy-profile3').exists())

    def make_ghostty_launcher(self, exec_line):
        apps = self.home / '.local/share/applications'
        apps.mkdir(parents=True)
        (apps / 'arch-com.mitchellh.ghostty.desktop').write_text(f'[Desktop Entry]\nName=Ghostty\nExec={exec_line}\n')

    def test_ghostty_not_configured_when_absent(self):
        r = self.install('--no-brew', '--no-cli')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse((self.home / '.config/ghostty').exists())

    def test_distrobox_ghostty_gets_config_and_container_zsh(self):
        self.stub('zsh', 'exit 0')
        self.make_ghostty_launcher('/usr/bin/distrobox-enter  -n arch  --   ghostty --gtk-single-instance=true')
        for _ in range(2):
            r = self.install('--no-brew', '--no-cli')
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(os.readlink(self.home / '.config/ghostty/config'), str(self.repo / 'ghostty/config'))
        local = (self.home / '.config/ghostty/local.conf').read_text()
        self.assertIn('command = /usr/bin/zsh -l', local)
        self.assertNotIn('distrobox-host-exec', local)
        self.assertEqual(local.count('command ='), 1)

    def test_existing_ghostty_local_conf_is_preserved(self):
        self.stub('zsh', 'exit 0')
        self.make_ghostty_launcher('/usr/bin/distrobox-enter -n arch -- ghostty')
        (self.home / '.config/ghostty').mkdir(parents=True)
        (self.home / '.config/ghostty/local.conf').write_text('font-size = 14\n')
        r = self.install('--no-brew', '--no-cli')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual((self.home / '.config/ghostty/local.conf').read_text(), 'font-size = 14\n')

    def test_native_ghostty_wins_over_stale_distrobox_launcher(self):
        self.stub('zsh', 'exit 0')
        self.stub('ghostty', 'exit 0')
        self.make_ghostty_launcher('/usr/bin/distrobox-enter -n arch -- ghostty')
        r = self.install('--no-brew', '--no-cli')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue((self.home / '.config/ghostty/config').is_symlink())
        self.assertFalse((self.home / '.config/ghostty/local.conf').exists())

    def test_native_ghostty_gets_config_without_host_shell(self):
        self.stub('ghostty', 'exit 0')
        r = self.install('--no-brew', '--no-cli')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue((self.home / '.config/ghostty/config').is_symlink())
        self.assertFalse((self.home / '.config/ghostty/local.conf').exists())

    def test_brew_bundle_failure_is_reported(self):
        r = self.install('--no-cli', BREW_FAIL='1')
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn('FAILED: Homebrew packages', r.stderr)
        self.assertIn('bundle --file=', self.log.read_text())
        self.assertIn('Brewfile.linux', self.log.read_text())

    def test_unknown_argument_is_rejected(self):
        r = self.install('--bogus')
        self.assertEqual(r.returncode, 2)


if __name__ == '__main__':
    unittest.main()

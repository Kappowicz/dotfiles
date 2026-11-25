"""zsh/.zshrc sourced in a temporary HOME; runs on macOS and Linux."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('zsh'), 'zsh is not installed')
class ZshrcTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dotfiles-zsh-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.home = self.root / 'home & spaces'
        self.home.mkdir()
        self.repo = self.root / 'repo'
        shutil.copytree(REPO / 'zsh', self.repo / 'zsh')
        self.mock = self.root / 'mock'
        self.mock.mkdir()
        self.log = self.root / 'commands.log'
        self.zsh = shutil.which('zsh')
        # Only the mocks on PATH, so tools on the host (lsd, nvim, macOS's
        # pbcopy, ...) cannot change which aliases the tests see.
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.mock), MOCK_LOG=str(self.log))
        for name in ('WAYLAND_DISPLAY', 'NVM_DIR', 'NVM_BIN', 'CLAUDECODE'):
            self.env.pop(name, None)
        (self.home / '.oh-my-zsh').mkdir()

    def stub(self, name, body):
        p = self.mock / name
        p.write_text('#!/bin/bash\n' + body + '\n')
        p.chmod(0o755)

    def zsh_aliases(self):
        (self.home / '.oh-my-zsh/oh-my-zsh.sh').write_text('')
        r = subprocess.run([self.zsh, '-f', '-c', 'source "$1" && alias', 'zsh', str(self.repo / 'zsh/.zshrc')], env=self.env, cwd=self.root, capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stderr, '')
        return dict(line.split('=', 1) for line in r.stdout.splitlines() if '=' in line)

    def test_zshrc_loads_cleanly_without_optional_tools(self):
        aliases = self.zsh_aliases()
        for name in ('ls', 'cat', 'grep', 'rgg', 'top', 'df', 'vim'):
            self.assertNotIn(name, aliases)

    def test_zshrc_loads_nvm_when_present(self):
        nvm = self.home / '.nvm'
        nvm.mkdir()
        (nvm / 'nvm.sh').write_text('export NVM_LOADED=yes\n')
        (self.home / '.oh-my-zsh/oh-my-zsh.sh').write_text('')
        r = subprocess.run([self.zsh, '-f', '-c', 'source "$1" && print -r -- "$NVM_LOADED $NVM_DIR"', 'zsh', str(self.repo / 'zsh/.zshrc')], env=self.env, cwd=self.root, capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), f'yes {nvm}')

    def run_zshrc(self, command, **variables):
        (self.home / '.oh-my-zsh/oh-my-zsh.sh').write_text('')
        r = subprocess.run([self.zsh, '-f', '-c', f'source "$1" && {command}', 'zsh', str(self.repo / 'zsh/.zshrc')], env=dict(self.env, **variables), cwd=self.root, capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stderr, '')
        return r.stdout

    def make_nvm(self, versions, aliases):
        nvm = self.home / '.nvm'
        nvm.mkdir()
        # A stand-in nvm: records whether the slow path was taken.
        (nvm / 'nvm.sh').write_text('nvm() { print -r -- "nvm $*" >> "$MOCK_LOG"; }\n')
        for v in versions:
            (nvm / 'versions/node' / v / 'bin').mkdir(parents=True)
        for name, target in aliases.items():
            (nvm / 'alias' / name).parent.mkdir(parents=True, exist_ok=True)
            (nvm / 'alias' / name).write_text(target + '\n')
        self.log.write_text('')
        return nvm

    def test_zshrc_puts_newest_matching_nvm_default_on_path_without_nvm_use(self):
        nvm = self.make_nvm(['v2.1.0', 'v20.9.0', 'v20.11.1', 'v22.3.0'], {'default': '20'})
        out = self.run_zshrc('print -r -- "$path[1]"')
        self.assertEqual(out.strip(), str(nvm / 'versions/node/v20.11.1/bin'))
        self.assertEqual(self.log.read_text(), '')

    def test_zshrc_follows_nvm_lts_alias_chain(self):
        nvm = self.make_nvm(['v20.11.1', 'v22.3.0'], {'default': 'lts/*', 'lts/*': 'lts/iron', 'lts/iron': 'v20.11.1'})
        out = self.run_zshrc('print -r -- "$path[1] $NVM_BIN"')
        bin_dir = str(nvm / 'versions/node/v20.11.1/bin')
        self.assertEqual(out.strip(), f'{bin_dir} {bin_dir}')

    def test_zshrc_falls_back_to_nvm_for_unresolvable_default(self):
        self.make_nvm(['v22.3.0'], {'default': 'system'})
        self.run_zshrc('true')
        self.assertEqual(self.log.read_text(), 'nvm use --silent default\n')

    def test_zshrc_maps_pbcopy_to_wl_clipboard_only_on_wayland(self):
        self.stub('wl-copy', 'exit 0')
        self.stub('wl-paste', 'exit 0')
        out = self.run_zshrc('alias pbcopy pbpaste || true', WAYLAND_DISPLAY='wayland-0')
        self.assertIn('pbcopy=wl-copy', out)
        self.assertIn("pbpaste='wl-paste --no-newline'", out)
        out = self.run_zshrc('alias pbcopy || true')
        self.assertEqual(out, '')

    def test_zshrc_aliases_installed_tools_but_never_grep(self):
        for tool in ('lsd', 'bat', 'rg', 'btop', 'duf', 'nvim'):
            self.stub(tool, 'exit 0')
        self.stub('fzf', 'exit 0')
        self.stub('zoxide', 'exit 0')
        aliases = self.zsh_aliases()
        self.assertEqual(aliases['ls'], 'lsd')
        self.assertIn('rg --no-ignore', aliases['rgg'])
        self.assertNotIn('grep', aliases)
        for name in ('cat', 'top', 'df', 'vim', 'vi'):
            self.assertIn(name, aliases)


if __name__ == '__main__':
    unittest.main()

"""bin/install-cli with every network call and installer mocked."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]

# Stands in for Antigravity's bootstrap: like the real one it accepts only
# --dir, installs into $HOME/.local/bin and then runs `agy install`, which
# edits shell profiles unless told to skip them.
FAKE_AGY_BOOTSTRAP = r'''#!/bin/bash
set -euo pipefail
for a in "$@"; do echo "[ERROR] Unknown parameter: $a" >&2; exit 1; done
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/agy" <<'AGY'
#!/bin/bash
printf 'agy %s HOME=%s\n' "$*" "$HOME" >> "$MOCK_LOG"
if [ "${1:-}" = install ]; then
  [ "${AGY_SETUP_FAIL:-0}" = 1 ] && exit 3
  case " $* " in *" --skip-path "*) ;; *) echo 'export PATH=agy' >> "$HOME/.zshrc" ;; esac
  case " $* " in *" --skip-aliases "*) ;; *) echo 'alias agy=agy' >> "$HOME/.zshrc" ;; esac
fi
AGY
chmod +x "$HOME/.local/bin/agy"
# The real bootstrap ignores a failing setup step the same way.
"$HOME/.local/bin/agy" install || true
'''


class InstallCliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dotfiles-cli-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.home = self.root / 'home & spaces'
        self.home.mkdir()
        self.mock = self.root / 'mock'
        self.mock.mkdir()
        self.log = self.root / 'commands.log'
        self.log.write_text('')
        (self.root / 'agy-bootstrap.sh').write_text(FAKE_AGY_BOOTSTRAP)
        script = self.root / 'install-cli'
        lines = (REPO / 'bin/install-cli').read_text().splitlines()
        # Only $HOME/.local/bin and the mocks: never a real installer on the host.
        script.write_text('\n'.join(
            f'export PATH="$HOME/.local/bin:{self.mock}:/usr/bin:/bin"' if l.startswith('export PATH=') else l
            for l in lines) + '\n')
        self.script = script
        for name in ['claude', 'agent', 'codex']:
            self.stub(name, 'exit 0')
        self.stub('curl', f'''
out=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2 ;; *) url="$1"; shift ;; esac; done
printf 'curl %s\\n' "$url" >> "$MOCK_LOG"
[ "${{CURL_FAIL:-0}}" = 1 ] && exit 22
cp "{self.root}/agy-bootstrap.sh" "$out"
''')
        self.zshrc = self.home / '.zshrc'
        self.zshrc.write_text('# tracked\n')

    def stub(self, name, body):
        p = self.mock / name
        p.write_text('#!/bin/bash\n' + body + '\n')
        p.chmod(0o755)

    def run_cli(self, **variables):
        env = dict(os.environ, HOME=str(self.home), MOCK_LOG=str(self.log), **variables)
        return subprocess.run(['/bin/bash', str(self.script)], env=env, capture_output=True, text=True, timeout=30)

    def test_agy_installed_without_touching_shell_profiles(self):
        r = self.run_cli()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue(os.access(self.home / '.local/bin/agy', os.X_OK))
        self.assertEqual(self.zshrc.read_text(), '# tracked\n')
        self.assertIn(f'agy install --skip-aliases --skip-path HOME={self.home}\n', self.log.read_text())

    def test_bootstrap_gets_no_unsupported_flags(self):
        r = self.run_cli()
        self.assertNotIn('Unknown parameter', r.stderr)

    def test_existing_agy_is_left_alone(self):
        self.stub('agy', 'printf "agy %s\\n" "$*" >> "$MOCK_LOG"')
        r = self.run_cli()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('already installed: agy', r.stdout)
        self.assertNotIn('curl', self.log.read_text())

    def test_download_failure_is_reported(self):
        r = self.run_cli(CURL_FAIL='1')
        self.assertEqual(r.returncode, 1)
        self.assertIn('Installation failed: agy', r.stderr)
        self.assertFalse((self.home / '.local/bin/agy').exists())

    def test_failed_agy_setup_removes_binary_so_rerun_retries(self):
        r = self.run_cli(AGY_SETUP_FAIL='1')
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("setup step 'agy install'", r.stderr)
        self.assertFalse((self.home / '.local/bin/agy').exists())
        r = self.run_cli()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotIn('already installed: agy', r.stdout)
        self.assertTrue(os.access(self.home / '.local/bin/agy', os.X_OK))
        self.assertEqual(self.zshrc.read_text(), '# tracked\n')


if __name__ == '__main__':
    unittest.main()

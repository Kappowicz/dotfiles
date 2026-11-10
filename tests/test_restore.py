"""Regression checks in temporary HOME directories; no real installs or updates."""
import json
import io
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import tarfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dotfiles-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.home = self.root / 'home & spaces'
        self.home.mkdir()
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        # Copy only source/config files, never the machine-local SSH config.
        for name in ['bin', 'zsh', 'git', 'ghostty', 'linearmouse', 'topgrade', 'vscode', 'cursor', 'claude', 'codex', 'antigravity', 'macos', 'launchd']:
            shutil.copytree(REPO / name, self.repo / name)
        (self.repo / 'ssh').mkdir()
        shutil.copy2(REPO / 'ssh/config.example', self.repo / 'ssh/config.example')
        for name in ['install.sh', 'Brewfile']:
            shutil.copy2(REPO / name, self.repo / name)
        self.mock = self.root / 'mock'
        self.mock.mkdir()
        self.log = self.root / 'commands.log'
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.mock}:/usr/bin:/bin:/usr/sbin:/sbin', MOCK_LOG=str(self.log), LIMITS_HOME=str(self.home))
        self.stub('pgrep', 'exit 1')
        self.stub('brew', '''
printf '%s\\n' "$*" >> "$MOCK_LOG"
if [ "${1:-}" = shellenv ]; then exit 0; fi
if [ "${1:-}" = bundle ]; then exit "${BREW_FAIL:-0}"; fi
if [ "${1:-}" = list ]; then printf 'first\\nsecond\\n'; exit "${LIST_FAIL:-0}"; fi
if [ "${1:-}" = outdated ]; then printf 'first\\nsecond\\n%s' "${PINNED_OUTDATED:-}"; exit "${LIST_FAIL:-0}"; fi
if [ "${1:-}" = upgrade ] && [ "${3:-}" = first ]; then exit "${CASK_FAIL:-0}"; fi
exit 0
''')
        self.stub('topgrade', 'exit "${TOPGRADE_FAIL:-0}"')
        self.stub('pip3', 'exit 0')
        # The production PATH is deliberately fixed for launchd. In copies only,
        # substitute mocks so tests cannot invoke real updaters or package installs.
        for name in ['mac-update', 'mac-cleanup', 'install-cli']:
            p = self.repo / 'bin' / name
            s = p.read_text().splitlines()
            p.write_text('\n'.join(f'export PATH="{self.mock}:/usr/bin:/bin:/usr/sbin:/sbin"' if line.startswith('export PATH=') else line for line in s) + '\n')
        p = self.repo / 'install.sh'
        # Prevent the installer from resolving the host's absolute brew path.
        s = p.read_text().replace('/opt/homebrew/bin/brew', str(self.mock / 'brew')).replace('/usr/local/bin/brew', str(self.mock / 'missing-brew'))
        p.write_text(s)
        for plugin in ['zsh-autosuggestions', 'zsh-syntax-highlighting']:
            (self.home / '.oh-my-zsh/custom/plugins' / plugin).mkdir(parents=True)
        self.stub('launchctl', 'printf "%s\\n" "$*" >> "$MOCK_LOG"; [ "$1" = bootout ] && exit 0; exit "${LAUNCH_FAIL:-0}"')

    def stub(self, name, body):
        p = self.mock / name
        p.write_text('#!/bin/bash\n' + body + '\n')
        p.chmod(0o755)

    def run_script(self, name, *args, **variables):
        p = self.repo / ('install.sh' if name == 'install' else f'bin/{name}')
        return subprocess.run(['/bin/bash', str(p), *args], env=dict(self.env, **variables), capture_output=True, text=True, timeout=30)

    def test_update_failure_retries_without_success_stamp(self):
        r = self.run_script('mac-update', '--force', TOPGRADE_FAIL='42')
        self.assertEqual(r.returncode, 1, r.stderr)
        self.assertFalse((self.home / '.local/state/mac-update.last').exists())

    def test_cask_failure_does_not_stop_other_casks_or_stamp_success(self):
        r = self.run_script('mac-update', '--force', CASK_FAIL='1')
        self.assertEqual(r.returncode, 1)
        self.assertIn('upgrade --cask second', self.log.read_text())
        self.assertFalse((self.home / '.local/state/mac-update.last').exists())

    def test_success_stamps_and_dry_run_does_not(self):
        r = self.run_script('mac-update', '--dry-run')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse((self.home / '.local/state/mac-update.last').exists())
        r = self.run_script('mac-update', '--force')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.home / '.local/state/mac-update.last').exists())

    def test_pending_app_store_updates_are_reported_not_installed(self):
        self.stub('mas', 'printf "mas %s\\n" "$*" >> "$MOCK_LOG"; [ "$1" = outdated ] && echo "497799835 Xcode (26.1 -> 26.2)"; exit 0')
        self.stub('osascript', 'printf "osascript\\n" >> "$MOCK_LOG"')
        r = self.run_script('mac-update', '--force')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('Xcode', r.stdout)
        log = self.log.read_text()
        self.assertIn('osascript', log)
        self.assertNotIn('mas upgrade', log)
        self.assertTrue((self.home / '.local/state/mac-update.last').exists())

    def test_failed_cask_listing_is_reported(self):
        r = self.run_script('mac-update', '--force', LIST_FAIL='1')
        self.assertEqual(r.returncode, 1)
        self.assertFalse((self.home / '.local/state/mac-update.last').exists())

    def test_pinned_casks_are_not_upgraded_without_a_terminal(self):
        r = self.run_script('mac-update', '--force', PINNED_OUTDATED='steam\n')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('steam (pinned', r.stdout)
        self.assertNotIn('upgrade --cask steam', self.log.read_text())

    def test_log_output_is_dated_and_has_no_colour_codes(self):
        r = self.run_script('mac-update', '--force')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('=== ', r.stdout)
        self.assertIn('mac-update --force', r.stdout)
        self.assertNotIn('\033', r.stdout + r.stderr)

    def test_second_job_is_refused_while_lock_is_held(self):
        state = self.home / '.local/state'
        state.mkdir(parents=True)
        holder = subprocess.Popen(['sleep', '30'])
        self.addCleanup(holder.wait)
        self.addCleanup(holder.kill)
        (state / 'mac-maintenance.lock').symlink_to(str(holder.pid))
        r = self.run_script('mac-cleanup', '--force')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('Another maintenance job is running', r.stdout)
        self.assertNotIn('cleanup', self.log.read_text() if self.log.exists() else '')
        self.assertFalse((state / 'mac-cleanup.last').exists())

    def test_stale_lock_is_taken_over_and_released(self):
        state = self.home / '.local/state'
        state.mkdir(parents=True)
        dead = subprocess.Popen(['true'])
        dead.wait()
        lock = state / 'mac-maintenance.lock'
        lock.symlink_to(str(dead.pid))
        r = self.run_script('mac-update', '--force')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((state / 'mac-update.last').exists())
        self.assertFalse(lock.is_symlink())

    def test_missing_library_refuses_to_run(self):
        shutil.rmtree(self.repo / 'bin/lib')
        r = self.run_script('mac-cleanup', '--force')
        self.assertEqual(r.returncode, 1)
        self.assertIn('refusing to run', r.stderr)
        self.assertFalse(self.log.exists() and 'cleanup' in self.log.read_text())

    def test_gradle_removes_whole_stale_versions_only(self):
        files = self.home / '.gradle/caches/modules-2/files-2.1'
        stale = files / 'g.old/mod/1.0'
        fresh = files / 'g.new/mod/2.0'
        mixed = files / 'g.mix/mod/3.0'
        for d in (stale, fresh, mixed):
            (d / 'sha').mkdir(parents=True)
        (stale / 'sha/a.jar').write_text('x')
        os.utime(stale / 'sha/a.jar', (1, 1))
        (fresh / 'sha/a.jar').write_text('x')
        (mixed / 'sha/a.jar').write_text('x')
        os.utime(mixed / 'sha/a.jar', (1, 1))
        (mixed / 'sha/a.pom').write_text('x')  # read recently: keeps the version
        r = self.run_script('mac-cleanup', '--force')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse((files / 'g.old').exists())
        self.assertTrue((fresh / 'sha/a.jar').exists())
        self.assertTrue((mixed / 'sha/a.jar').exists())

    def test_idle_gradle_daemon_allows_maintenance_busy_daemon_blocks(self):
        self.stub('pgrep', '[ "$2" = GradleDaemon ]')
        gradle = self.home / '.gradle/wrapper/dists/test/gradle/bin/gradle'
        gradle.parent.mkdir(parents=True)
        gradle.write_text('#!/bin/bash\nprintf "  PID STATUS INFO\\n  123 %s test\\n" "$DAEMON_STATUS"\n')
        gradle.chmod(0o755)
        r = self.run_script('mac-update', '--force', DAEMON_STATUS='BUSY')
        self.assertEqual(r.returncode, 0)
        self.assertFalse((self.home / '.local/state/mac-update.last').exists())
        r = self.run_script('mac-update', '--force', DAEMON_STATUS='IDLE')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.home / '.local/state/mac-update.last').exists())

    def test_cleanup_handles_newline_path_and_preserves_recent_configs(self):
        project = self.home / 'Projects/project'
        project.mkdir(parents=True)
        (project / 'pubspec.yaml').write_text('name: test\n')
        build = project / '.dart_tool/flutter_build'
        build.mkdir(parents=True)
        old = build / 'old\nconfiguration'
        old.mkdir()
        os.utime(old, (1, 1))
        for i in range(8):
            (build / str(i)).mkdir()
        r = self.run_script('mac-cleanup', '--dry-run')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(old.exists())
        r = self.run_script('mac-cleanup', '--force')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(old.exists())
        self.assertEqual(len(list(build.iterdir())), 8)

    def test_install_preserves_identity_adds_include_and_is_idempotent(self):
        gitconfig = self.home / '.gitconfig'
        gitconfig.write_text('[user]\n name = Existing User\n email = test@example.invalid\n')
        r = self.run_script('install', '--yes', '--no-brew', '--no-cli', '--no-settings')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('Existing User', gitconfig.read_text())
        shared = str(self.repo / 'git/.gitconfig')
        self.assertEqual(gitconfig.read_text().count(shared), 1)
        for template in (self.repo / 'launchd').glob('*.plist'):
            data = plistlib.loads((self.home / 'Library/LaunchAgents' / template.name).read_bytes())
            self.assertEqual(data['ProgramArguments'][0], str(self.home / '.local/bin' / ('mac-cleanup' if 'cleanup' in template.name else 'mac-update')))
        before = list(self.home.rglob('*.backup-*'))
        r = self.run_script('install', '--yes', '--no-brew', '--no-cli', '--no-settings')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(gitconfig.read_text().count(shared), 1)
        self.assertEqual(list(self.home.rglob('*.backup-*')), before)

    def test_install_reports_brew_and_launchagent_failures(self):
        r = self.run_script('install', '--yes', '--no-cli', '--no-settings', BREW_FAIL='1', LAUNCH_FAIL='1')
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn('FAILED: Homebrew packages', r.stderr)
        self.assertIn('FAILED: LaunchAgent:', r.stderr)
        self.assertNotIn('Setup complete.', r.stdout)

    def test_existing_agent_config_is_preserved(self):
        p = self.home / '.claude/settings.json'
        p.parent.mkdir()
        p.write_text('{"theme":"existing"}\n')
        r = self.run_script('install', '--yes', '--no-brew', '--no-cli', '--no-settings', '--no-agents')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(json.loads(p.read_text()), {'theme': 'existing'})

    def test_limits_and_statusline_share_portable_profile_cache(self):
        # No network or auth calls: feed a synthetic status line and inspect its cache.
        payload = json.dumps({'email': 'synthetic@example.invalid', 'quota': {}, 'model': {}})
        profile = self.home / '.agy-profile2'
        profile.mkdir()
        r = subprocess.run(['python3', str(self.repo / 'antigravity/statusline.py')], input=payload, env=dict(self.env, HOME=str(profile)), capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        cached = self.home / '.cache/agent_limits/agy2.json'
        self.assertTrue(cached.exists())
        self.assertEqual(json.loads(cached.read_text())['email'], 'synthetic@example.invalid')

    def test_backup_encrypts_and_preserves_symlinked_ssh_config(self):
        age = shutil.which('age')
        keygen = shutil.which('age-keygen')
        if not age or not keygen:
            self.skipTest('age and age-keygen are required for the encryption round trip')
        key = self.root / 'test-identity'
        subprocess.run([keygen, '-o', str(key)], capture_output=True, check=True)
        recipient = subprocess.check_output([keygen, '-y', str(key)], text=True).strip()
        self.stub('age', 'exec "$REAL_AGE" -r "$TEST_RECIPIENT" -o "$3"')
        self.env.update(REAL_AGE=age, TEST_RECIPIENT=recipient)
        (self.home / '.ssh').mkdir()
        source = self.root / 'ssh-config'
        source.write_text('Host synthetic\n HostName example.invalid\n')
        (self.home / '.ssh/config').symlink_to(source)
        archive = self.root / 'private.tar.gz.age'
        r = self.run_script('mac-backup', str(archive))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        plaintext = subprocess.check_output([age, '--decrypt', '-i', str(key), str(archive)])
        with tarfile.open(fileobj=io.BytesIO(plaintext), mode='r:gz') as data:
            self.assertTrue(data.getmember('.ssh/config').isfile())
            self.assertEqual(data.extractfile('.ssh/config').read(), source.read_bytes())
        self.assertEqual(archive.stat().st_mode & 0o777, 0o600)
        r = self.run_script('mac-backup', str(archive))
        self.assertEqual(r.returncode, 1)

    def test_failed_backup_leaves_no_incomplete_archive(self):
        (self.home / '.ssh').mkdir()
        (self.home / '.ssh/config').write_text('Host synthetic\n')
        self.stub('age', 'exit 1')
        archive = self.root / 'failed.tar.gz.age'
        r = self.run_script('mac-backup', str(archive))
        self.assertEqual(r.returncode, 1)
        self.assertFalse(archive.exists())
        self.assertEqual(list(self.root.glob('.dotfiles-backup.*')), [])

    def test_backup_rejects_missing_explicit_paths(self):
        archive = self.root / 'private.tar.gz.age'
        r = self.run_script('mac-backup', str(archive), 'missing-signing-key.jks')
        self.assertEqual(r.returncode, 1)
        self.assertIn('Requested backup path is missing', r.stderr)
        self.assertFalse(archive.exists())

    def test_settings_validate_before_write_and_apply_idempotently(self):
        state = self.root / 'preferences.json'
        state.write_text('{}')
        self.env['MOCK_PREFS'] = str(state)
        defaults = self.mock / 'defaults'
        defaults.write_text('''#!/usr/bin/env python3
import json, os, pathlib, plistlib, sys
p = pathlib.Path(os.environ['MOCK_PREFS'])
data = json.loads(p.read_text())
action, domain = sys.argv[1:3]
if action == 'export':
    sys.stdout.buffer.write(plistlib.dumps(data.get(domain, {})))
elif action == 'write':
    key = sys.argv[3]
    if sys.argv[4] == '-bool': value = sys.argv[5] == 'true'
    elif sys.argv[4] == '-int': value = int(sys.argv[5])
    elif sys.argv[4] == '-string': value = sys.argv[5]
    else: value = plistlib.loads(sys.argv[4].encode())
    data.setdefault(domain, {})[key] = value
    p.write_text(json.dumps(data))
    with open(os.environ['MOCK_LOG'], 'a') as log: log.write('defaults write\\n')
''')
        defaults.chmod(0o755)
        snapshot = self.root / 'snapshot.json'
        snapshot.write_text(json.dumps({'com.apple.dock': {'autohide': True}, 'unsupported': {'token': 'synthetic'}}))
        command = [sys.executable, str(self.repo / 'bin/mac-settings'), 'apply', '--file', str(snapshot)]
        r = subprocess.run(command, env=self.env, capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(json.loads(state.read_text()), {})
        snapshot.write_text(json.dumps({'com.apple.dock': {'autohide': True}, 'com.knollsoft.Rectangle': {'toggleTodo': {'keyCode': 11, 'modifierFlags': 786432}}}))
        r = subprocess.run(command + ['--dry-run'], env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(state.read_text()), {})
        r = subprocess.run(command, env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(state.read_text()), json.loads(snapshot.read_text()))
        before = self.log.read_text()
        r = subprocess.run(command, env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.log.read_text(), before)
        self.assertTrue(list((self.home / '.local/state/dotfiles/preferences').glob('*/*.json')))

    def test_extract_handles_spaces_and_missing_arguments(self):
        text = (self.repo / 'zsh/.zshrc').read_text()
        start = text.index('extract () {')
        end = text.index('\n#java', start)
        command = ['zsh', '-f', '-c', text[start:end] + '\nextract "$@"', 'extract']
        r = subprocess.run(command, env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)
        archive = self.root / 'archive with spaces.tar.gz'
        with tarfile.open(archive, 'w:gz') as data:
            member = tarfile.TarInfo('sample.txt')
            member.size = 2
            data.addfile(member, io.BytesIO(b'ok'))
        r = subprocess.run(command + [str(archive)], env=self.env, cwd=self.root, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((self.root / 'sample.txt').read_text(), 'ok')


if __name__ == '__main__':
    unittest.main()

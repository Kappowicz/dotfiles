# Application exports

Keep private app exports in `exports/private/` (gitignored). The installer does
not import these automatically. `mac-backup` includes this directory in its
encrypted archive; move that archive off the Mac before resetting it.

- **Raycast:** Settings → Advanced → Export. Export settings, extensions,
  quicklinks, snippets and shortcuts to `private/raycast.rayconfig`. Save the
  export password separately if the app asks for one. Import through Raycast
  after reinstalling. Its internal database backups are not a portable export.
- **Rectangle:** export settings through the app if you have custom shortcuts.
  The checked-in macOS snapshot covers the current basic preferences and
  `toggleTodo` shortcut, not every possible Rectangle action.
- **Cursor / VS Code:** settings are in the repo. Put custom keybindings and
  snippets in the corresponding repo directory, or keep a private export here.
  Use Settings Sync for profiles and extensions not declared in Brewfile.
- **Antigravity:** the repo contains CLI settings and its quota status line.
  Reauthenticate each profile after a reset; IDE sessions and conversation
  databases are not restored by the bootstrap.
- **Agent skills/plugins:** private backup includes user skill directories.
  Reinstall plugins from their original sources after signing in; generated
  plugin caches and conversation history are not part of the bootstrap.

Do not put raw exports in tracked directories: snippets and extension settings
can contain personal data or credentials.

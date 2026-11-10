#!/usr/bin/env bash
# PostToolUse na narzedziu `Skill`: zapisuje nazwe uruchomionego skilla do pliku
# nazwanego identyfikatorem sesji, zeby statusline mial co pokazac.
#
# Dlaczego plik, a nie pole w JSON-ie paska: wejscie statusline (2.1.250) nie
# niesie informacji o skillu — ma model, workspace, context_window, rate_limits
# i sesje, ale nic o aktywnym skillu. To jedyny kanal miedzy hookiem a paskiem.
#
# Wpisu nie kasuje nic poza nowa sesja (inny identyfikator) i sprzataniem nizej:
# skill nie ma zdarzenia "koniec", a taki jak `caveman` obowiazuje do konca
# rozmowy. Pasek pokazuje wiec ostatnio uruchomiony skill sesji.
set -u
dir="$HOME/.claude/statusline-skills"
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty')
if [ -n "$sid" ] && [ -n "$skill" ]; then
  mkdir -p "$dir"
  printf '%s' "$skill" > "$dir/$sid"
fi
# Kazda sesja zostawia tu jeden plik; bez tego katalog rosnie bez konca.
find "$dir" -type f -mtime +7 -delete 2>/dev/null
exit 0

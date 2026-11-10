#!/usr/bin/env bash
# Status line: katalog (+worktree) · galaz gita (+liczba zmian) · model ·
# aktywny skill · zapelnienie okna kontekstu · zuzycie limitow 5h i 7d.
# Claude Code podaje kontekst sesji jako JSON na stdin.
input=$(cat)
model=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // "?"')
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // "."')
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
# `worktree` jest w JSON-ie tylko wewnatrz worktree — sama galaz nie mowi,
# w ktorym katalogu siedzisz, gdy dwa worktree maja rozne galezie tego repo.
wt=$(printf '%s' "$input" | jq -r '.worktree.name // empty')
# `used_percentage` to juz liczba 0–100 (albo null przed pierwszym zapytaniem).
ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
# Skilla nie ma w wejsciu paska — nazwe podrzuca hook PostToolUse na narzedziu
# `Skill` (~/.claude/hooks/skill-statusline.sh) przez plik nazwany sesja.
skill=""
[ -n "$sid" ] && [ -r "$HOME/.claude/statusline-skills/$sid" ] &&
  skill=$(head -c 40 "$HOME/.claude/statusline-skills/$sid" | tr -dc 'A-Za-z0-9:._-')

# `rate_limits` pojawia sie dopiero, gdy serwer odeslal naglowki limitow — na
# starcie sesji, przed pierwszym zapytaniem, tego klucza nie ma. Wtedy pomijamy
# dany segment, zamiast pokazywac mylace "0%".
#
# $1 — etykieta ("5h" / "7d"), $2 — procent, $3 — unix resetu, $4 — format daty.
# Wypisuje gotowy segment albo nic.
limit_segment() {
  [ -n "$2" ] || return 0
  local p color at
  p=$(printf '%.0f' "$2")
  # Progi arbitralne: zolty tam, gdzie warto zaczac oszczedzac, czerwony tam,
  # gdzie do konca okna zostalo juz malo.
  if [ "$p" -ge 80 ]; then color=31; elif [ "$p" -ge 50 ]; then color=33; else color=32; fi
  printf ' \033[2m·\033[0m \033[%sm%s %s%%\033[0m' "$color" "$1" "$p"
  # Moment resetu dokladamy dopiero przy wysokim zuzyciu — wczesniej to tylko
  # szum, a pasek konkuruje o miejsce ze sciezka i galezia.
  if [ "$p" -ge 50 ] && [ -n "$3" ]; then
    at=$(date -r "${3%%.*}" "+$4" 2>/dev/null)
    [ -n "$at" ] && printf '\033[2m (do %s)\033[0m' "$at"
  fi
}

read -r h_pct h_at d_pct d_at <<<"$(printf '%s' "$input" | jq -r '
  [ .rate_limits.five_hour.used_percentage // "-",
    .rate_limits.five_hour.resets_at       // "-",
    .rate_limits.seven_day.used_percentage // "-",
    .rate_limits.seven_day.resets_at       // "-" ] | @tsv')"
for v in h_pct h_at d_pct d_at; do [ "${!v}" = "-" ] && eval "$v=''"; done

# Okno tygodniowe resetuje sie za dni, wiec sama godzina nic nie mowi; %a jest
# zalezne od LC_TIME, dlatego dzien i miesiac liczbowo.
limits="$(limit_segment 5h "$h_pct" "$h_at" '%H:%M')$(limit_segment 7d "$d_pct" "$d_at" '%d.%m %H:%M')"

context=""
if [ -n "$ctx" ]; then
  # Kolor dopiero blisko kompaktowania: nizsze wartosci to normalny stan sesji,
  # a nie ostrzezenie.
  if [ "$ctx" -ge 90 ]; then c=31; elif [ "$ctx" -ge 70 ]; then c=33; else c=2; fi
  context=$(printf ' \033[2m·\033[0m \033[%sm%s%% ctx\033[0m' "$c" "$ctx")
fi

# Skill bez przygaszenia: to jedyny segment mowiacy, ze sesja chodzi w innym
# trybie niz zwykle — ma rzucac sie w oczy miedzy dimami.
skill_seg=""
[ -n "$skill" ] && skill_seg=$(printf ' \033[2m·\033[0m /%s' "$skill")

name=$(basename "$dir")
[ -n "$wt" ] && name="$name@$wt"
branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

if [ -n "$branch" ]; then
  n=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" != "0" ] && branch="$branch*$n"
  printf '\033[2m%s\033[0m \033[36m%s\033[0m \033[2m·\033[0m \033[35m%s\033[0m' "$name" "$branch" "$model"
else
  printf '\033[2m%s\033[0m \033[2m·\033[0m \033[35m%s\033[0m' "$name" "$model"
fi
printf '%s%s%s' "$skill_seg" "$context" "$limits"

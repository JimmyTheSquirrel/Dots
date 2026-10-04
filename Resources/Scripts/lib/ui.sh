# ui.sh — the shared look of rock's deploy tools.
#
# Not a script on its own: Modules/Shell/deploy-tools.nix PREPENDS this file to
# each tool's body before handing it to writeShellApplication, so shellcheck
# checks library + tool as one file and nothing is sourced at runtime.
#
# Everything here degrades to plain text when stdout isn't a terminal, when
# NO_COLOR is set, or when TERM is dumb — so piping a tool or running it from a
# script never gets escape codes or an interactive prompt it can't answer.

# ── Palette ───────────────────────────────────────────────────────────────────
# Gruvbox brights — the same family kitty uses (Modules/Shell/kitty.nix), so the
# UI looks like it belongs in this terminal instead of fighting it.
UI_AQUA="#8ec07c"
UI_BLUE="#83a598"
UI_PURPLE="#d3869b"
UI_YELLOW="#fabd2f"
UI_RED="#fb4934"
UI_GREEN="#b8bb26"
UI_FG="#ebdbb2"
UI_DIM="#928374"

UI_COLOR=0
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then UI_COLOR=1; fi
UI_INTERACTIVE=0
if [[ -t 0 && -t 1 ]]; then UI_INTERACTIVE=1; fi
UI_WIDTH=$(( $(tput cols 2>/dev/null || echo 80) ))
(( UI_WIDTH > 78 )) && UI_WIDTH=78
(( UI_WIDTH < 40 )) && UI_WIDTH=40

# gum reads its styling from the environment, so every prompt in every tool
# matches without repeating flags.
export GUM_CHOOSE_CURSOR="  ▸ "
export GUM_CHOOSE_CURSOR_FOREGROUND="$UI_AQUA"
export GUM_CHOOSE_SELECTED_FOREGROUND="$UI_AQUA"
export GUM_CHOOSE_ITEM_FOREGROUND="$UI_FG"
export GUM_CHOOSE_HEADER_FOREGROUND="$UI_DIM"
export GUM_CONFIRM_PROMPT_FOREGROUND="$UI_FG"
export GUM_CONFIRM_SELECTED_BACKGROUND="$UI_AQUA"
export GUM_CONFIRM_SELECTED_FOREGROUND="#1d2021"
export GUM_CONFIRM_UNSELECTED_FOREGROUND="$UI_DIM"
export GUM_INPUT_CURSOR_FOREGROUND="$UI_AQUA"
export GUM_INPUT_PROMPT_FOREGROUND="$UI_AQUA"
export GUM_SPIN_SPINNER="dot"
export GUM_SPIN_SPINNER_FOREGROUND="$UI_AQUA"
export GUM_SPIN_TITLE_FOREGROUND="$UI_DIM"

# ── Text ──────────────────────────────────────────────────────────────────────

# ui_c HEX TEXT… — TEXT in a 24-bit colour (plain without colour support).
ui_c() {
  local hex="$1"; shift
  if (( UI_COLOR )); then
    printf '\033[38;2;%d;%d;%dm%s\033[0m' "0x${hex:1:2}" "0x${hex:3:2}" "0x${hex:5:2}" "$*"
  else
    printf '%s' "$*"
  fi
}
ui_bold() { if (( UI_COLOR )); then printf '\033[1m%s\033[22m' "$*"; else printf '%s' "$*"; fi; }
ui_dim() { ui_c "$UI_DIM" "$@"; }

# ui_gradient TEXT — aqua → blue → purple across the string, one colour per
# character. Used for the wordmark only; anything more is noise.
ui_gradient() {
  local text="$1" n i r g b t
  n=${#text}
  if (( ! UI_COLOR || n < 2 )); then printf '%s' "$text"; return; fi
  for (( i = 0; i < n; i++ )); do
    t=$(( i * 1000 / (n - 1) ))
    if (( t < 500 )); then   # aqua (142,192,124) -> blue (131,165,152)
      r=$(( 142 + (131 - 142) * t / 500 )); g=$(( 192 + (165 - 192) * t / 500 )); b=$(( 124 + (152 - 124) * t / 500 ))
    else                     # blue -> purple (211,134,155)
      t=$(( t - 500 ))
      r=$(( 131 + (211 - 131) * t / 500 )); g=$(( 165 + (134 - 165) * t / 500 )); b=$(( 152 + (155 - 152) * t / 500 ))
    fi
    printf '\033[1;38;2;%d;%d;%dm%s' "$r" "$g" "$b" "${text:i:1}"
  done
  printf '\033[0m'
}

# ui_header TITLE [RIGHT] — the wordmark line every tool starts with. The mark
# is the Nerd Font NixOS snowflake (U+F313): kitty's FantasqueSansM Nerd Font
# Mono has it, and plain-Unicode ornaments (runes) have no glyph in any font
# installed here, so they'd render as boxes.
#     D O T S  ·  system-rebuild                         Sisyphus · rock
ui_header() {
  local title="$1" right="${2:-}" left pad
  left="  $(ui_c "$UI_BLUE" $'\uf313')  $(ui_gradient "D O T S")  $(ui_dim "·")  $(ui_bold "$(ui_c "$UI_FG" "$title")")"
  # visible width: 2+1+2+9+2+1+2+len(title)
  pad=$(( UI_WIDTH - 19 - ${#title} - ${#right} ))
  (( pad < 2 )) && pad=2
  echo
  printf '%s%*s%s\n' "$left" "$pad" "" "$(ui_c "$UI_PURPLE" "$right")"
  ui_rule
}

# ui_rule [LABEL] — a thin divider, optionally labelled: ── LABEL ──────────
ui_rule() {
  local label="${1:-}" line n
  if [[ -n "$label" ]]; then
    n=$(( UI_WIDTH - ${#label} - 7 ))
    printf -v line '%*s' "$n" ""
    printf '  %s %s %s\n' "$(ui_dim "──")" "$(ui_bold "$(ui_c "$UI_BLUE" "$label")")" "$(ui_dim "${line// /─}")"
  else
    printf -v line '%*s' "$(( UI_WIDTH - 2 ))" ""
    printf '  %s\n' "$(ui_dim "${line// /─}")"
  fi
}

ui_ok()   { printf '  %s %s\n' "$(ui_c "$UI_GREEN" "✔")" "$*"; }
ui_err()  { printf '  %s %s\n' "$(ui_c "$UI_RED" "✘")" "$*" >&2; }
ui_warn() { printf '  %s %s\n' "$(ui_c "$UI_YELLOW" "!")" "$*"; }
ui_info() { printf '  %s %s\n' "$(ui_c "$UI_BLUE" "›")" "$*"; }
ui_step() { printf '\n  %s %s\n' "$(ui_c "$UI_AQUA" "▶")" "$(ui_bold "$*")"; }

# ui_kv KEY VALUE — an aligned "key   value" row inside a section.
ui_kv() { printf '    %s %s\n' "$(ui_dim "$(printf '%-10s' "$1")")" "$2"; }

# ui_vlen TEXT — visible width: escape codes stripped, one cell per character
# (true for every glyph these tools print).
ui_vlen() {
  local LC_ALL=C.UTF-8 plain
  plain=$(printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g')
  printf '%s' "${#plain}"
}

# ui_box COLOUR TITLE LINE… — a rounded box drawn here rather than by
# `gum style`, which mis-measures lines carrying 24-bit colour and leaves the
# right border ragged. Plain indented text without colour.
ui_box() {
  local colour="$1" title="$2"; shift 2
  if (( ! UI_COLOR )); then
    printf '\n  %s\n' "$title"
    printf '    %s\n' "$@"
    echo
    return
  fi
  # Never wider than the terminal: margin 2 + border 1 + padding 2, both sides.
  local maxw=$(( UI_WIDTH - 10 )) w=0 l n bar piece
  local -a rows=()
  for l in "$@"; do
    n=$(ui_vlen "$l")
    if (( n <= maxw )); then rows+=("$l"); continue; fi
    # Too long: wrap the plain text (its colour is lost — only ever a command
    # or a path, where wrapping beats running off the edge).
    l=$(printf '%s' "$l" | sed 's/\x1b\[[0-9;]*m//g')
    while IFS= read -r piece; do rows+=("$piece"); done < <(LC_ALL=C.UTF-8 fold -w "$maxw" <<<"$l")
  done
  for l in "$title" "${rows[@]}"; do n=$(ui_vlen "$l"); (( n > w )) && w=$n; done
  (( w > maxw )) && w=$maxw
  printf -v bar '%*s' $(( w + 4 )) ""
  bar=${bar// /─}
  printf '\n  %s\n' "$(ui_c "$colour" "╭${bar}╮")"
  for l in "$(ui_bold "$(ui_c "$colour" "$title")")" "" "${rows[@]}"; do
    n=$(ui_vlen "$l")
    printf '  %s  %s%*s  %s\n' "$(ui_c "$colour" "│")" "$l" $(( w - n )) "" "$(ui_c "$colour" "│")"
  done
  printf '  %s\n\n' "$(ui_c "$colour" "╰${bar}╯")"
}

# ── Prompts (interactive only) ────────────────────────────────────────────────

# ui_choose HEADER "Label:value"… — prints the chosen VALUE; non-zero on Esc/^C.
ui_choose() {
  local header="$1"; shift
  (( UI_INTERACTIVE )) || { ui_err "a choice is needed but this isn't an interactive terminal"; return 2; }
  # The spacer goes to stderr with gum's own drawing: stdout is the answer,
  # and callers capture it with $(…).
  echo >&2
  gum choose --header "  $header" --label-delimiter ":" --height 14 "$@"
}

# ui_confirm PROMPT [default-no] — yes/no; non-zero for no, Esc or ^C.
ui_confirm() {
  local prompt="$1" def="${2:-}"
  (( UI_INTERACTIVE )) || return 1
  if [[ "$def" == "default-no" ]]; then
    gum confirm --default=false --prompt.margin "0 2" "$prompt"
  else
    gum confirm --prompt.margin "0 2" "$prompt"
  fi
}

# ui_input PROMPT [VALUE] — one line of text.
ui_input() {
  (( UI_INTERACTIVE )) || { printf '%s' "${2:-}"; return 0; }
  gum input --prompt "  ${1} › " --value "${2:-}" --width $(( UI_WIDTH - 4 ))
}

# ui_spin TITLE CMD… — run an external command behind a spinner, keeping its
# stdout. (gum spin runs commands, not shell functions.)
ui_spin() {
  local title="$1"; shift
  if (( UI_COLOR && UI_INTERACTIVE )); then
    gum spin --title " $title" --show-output -- "$@"
  else
    "$@"
  fi
}

# ── Formatting ────────────────────────────────────────────────────────────────

ui_duration() {
  local s="$1"
  if (( s >= 3600 )); then printf '%dh %02dm' $(( s / 3600 )) $(( s % 3600 / 60 ))
  elif (( s >= 60 )); then printf '%dm %02ds' $(( s / 60 )) $(( s % 60 ))
  else printf '%ds' "$s"; fi
}

# ui_ago EPOCH — "3m ago", "2h ago", "5d ago".
ui_ago() {
  local d=$(( $(date +%s) - $1 ))
  if (( d < 90 )); then printf 'just now'
  elif (( d < 5400 )); then printf '%dm ago' $(( d / 60 ))
  elif (( d < 172800 )); then printf '%dh ago' $(( d / 3600 ))
  else printf '%dd ago' $(( d / 86400 )); fi
}

ui_bytes() { numfmt --to=iec-i --suffix=B --format='%.1f' "$1" 2>/dev/null || printf '%sB' "$1"; }

# Leave the terminal sane on ^C: gum restores its own state, this just says so.
ui_on_interrupt() { printf '\n  %s\n\n' "$(ui_dim "cancelled")"; exit 130; }
trap ui_on_interrupt INT

# ── end of ui.sh ──────────────────────────────────────────────────────────────

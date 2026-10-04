# ui.sh — the shared look of rock's deploy tools.
#
# Not a script on its own: Modules/Shell/deploy-tools.nix PREPENDS this file to
# each tool's body before handing it to writeShellApplication, so shellcheck
# checks library + tool as one file and nothing is sourced at runtime.
#
# Everything here degrades to plain text when stdout isn't a terminal, when
# NO_COLOR is set, or when TERM is dumb — so piping a tool or running it from a
# script never gets escape codes or an interactive prompt it can't answer.
#
# Glyphs: block elements (▀▄█), box drawing and the powerline caps (U+E0B4/B6)
# are drawn by kitty itself, so they join up pixel-perfectly; the icons are Nerd
# Font (kitty's FantasqueSansM Nerd Font Mono has them all, one cell each).

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
UI_LINE="#504945"     # panel borders, rules
UI_BG="#1d2021"       # kitty's background — tints are mixed towards it

UI_COLOR=0
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then UI_COLOR=1; fi
UI_INTERACTIVE=0
if [[ -t 0 && -t 1 ]]; then UI_INTERACTIVE=1; fi
UI_WIDTH=$(( $(tput cols 2>/dev/null || echo 80) ))
(( UI_WIDTH > 78 )) && UI_WIDTH=78
(( UI_WIDTH < 48 )) && UI_WIDTH=48

# Raw escapes, empty without colour. Every colour helper ends with "default
# foreground" (39), never a full reset (0), so colouring a word inside a
# highlighted row keeps the row's background and weight.
UI_RFG="" UI_RBG="" UI_BLD="" UI_NBLD=""
if (( UI_COLOR )); then
  UI_RFG=$'\033[39m' UI_RBG=$'\033[49m' UI_BLD=$'\033[1m' UI_NBLD=$'\033[22m'
fi
UI_CAP_L=$''    # powerline round caps: the ends of a pill
UI_CAP_R=$''
UI_I_NIX=$''
UI_I_BACK=$''
UI_I_QUIT=$''

# gum draws the remaining prompts (confirm, input, spin); it reads its styling
# from the environment, so they all match without repeating flags.
export GUM_CONFIRM_PROMPT_FOREGROUND="$UI_FG"
export GUM_CONFIRM_SELECTED_BACKGROUND="$UI_AQUA"
export GUM_CONFIRM_SELECTED_FOREGROUND="$UI_BG"
export GUM_CONFIRM_UNSELECTED_FOREGROUND="$UI_DIM"
export GUM_INPUT_CURSOR_FOREGROUND="$UI_AQUA"
export GUM_INPUT_PROMPT_FOREGROUND="$UI_AQUA"
export GUM_SPIN_SPINNER="dot"
export GUM_SPIN_SPINNER_FOREGROUND="$UI_AQUA"
export GUM_SPIN_TITLE_FOREGROUND="$UI_DIM"

# ── Colour maths ──────────────────────────────────────────────────────────────
# All fork-free (printf -v into a variable), because the menu renders every row
# twice per redraw and a $(…) per colour would make arrow keys lag.

# ui_rgb HEX — UI_RGB="r;g;b".
ui_rgb() { printf -v UI_RGB '%d;%d;%d' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
# ui_fg VAR HEX / ui_bg VAR HEX — VAR = the escape selecting HEX ('' without colour).
ui_fg() { if (( UI_COLOR )); then ui_rgb "$2"; printf -v "$1" '\033[38;2;%sm' "$UI_RGB"; else printf -v "$1" '%s' ""; fi; }
ui_bg() { if (( UI_COLOR )); then ui_rgb "$2"; printf -v "$1" '\033[48;2;%sm' "$UI_RGB"; else printf -v "$1" '%s' ""; fi; }
# ui_mix VAR A B PCT — VAR = PCT% of colour A over colour B, as #rrggbb.
ui_mix() {
  local a="$2" b="$3" p="$4"
  printf -v "$1" '#%02x%02x%02x' \
    $(( (0x${a:1:2} * p + 0x${b:1:2} * (100 - p)) / 100 )) \
    $(( (0x${a:3:2} * p + 0x${b:3:2} * (100 - p)) / 100 )) \
    $(( (0x${a:5:2} * p + 0x${b:5:2} * (100 - p)) / 100 ))
}
# ui_grad T — UI_RGB at T (0–1000) along the house gradient, aqua → blue → purple.
ui_grad() {
  local t="$1"
  if (( t < 500 )); then
    printf -v UI_RGB '%d;%d;%d' $(( 142 - 11 * t / 500 )) $(( 192 - 27 * t / 500 )) $(( 124 + 28 * t / 500 ))
  else
    t=$(( t - 500 ))
    printf -v UI_RGB '%d;%d;%d' $(( 131 + 80 * t / 500 )) $(( 165 - 31 * t / 500 )) $(( 152 + 3 * t / 500 ))
  fi
}
# UI_GRAD[col] — the gradient's foreground escape for every column of a line.
UI_GRAD=()
if (( UI_COLOR )); then
  for (( _c = 0; _c < UI_WIDTH; _c++ )); do
    ui_grad $(( _c * 1000 / (UI_WIDTH - 1) ))
    UI_GRAD[_c]=$'\033[38;2;'"${UI_RGB}m"
  done
  unset _c
fi

# ── Text ──────────────────────────────────────────────────────────────────────

# ui_c HEX TEXT… — TEXT in a 24-bit colour (plain without colour support).
ui_c() {
  local e; ui_fg e "$1"; shift
  printf '%s%s%s' "$e" "$*" "$UI_RFG"
}
ui_bold() { printf '%s%s%s' "$UI_BLD" "$*" "$UI_NBLD"; }
ui_dim() { ui_c "$UI_DIM" "$@"; }

# ui_gradient TEXT — bold, aqua → blue → purple across the string.
ui_gradient() {
  local text="$1" n i
  n=${#text}
  if (( ! UI_COLOR || n < 2 )); then printf '%s' "$text"; return; fi
  for (( i = 0; i < n; i++ )); do
    ui_grad $(( i * 1000 / (n - 1) ))
    printf '\033[1;38;2;%sm%s' "$UI_RGB" "${text:i:1}"
  done
  printf '%s%s' "$UI_NBLD" "$UI_RFG"
}

# ui_vlen_v TEXT — UI_N = visible width: escapes stripped, one cell per
# character (true for every glyph these tools print). ui_vlen prints it.
ui_vlen_v() {
  local LC_ALL=C.UTF-8 s="$1" out=""
  while [[ "$s" == *$'\033['* ]]; do
    out+=${s%%$'\033['*}
    s=${s#*$'\033['}
    s=${s#*m}          # parameters are digits and ';' — the first m ends it
  done
  out+=$s
  UI_N=${#out}
}
ui_vlen() { ui_vlen_v "$1"; printf '%s' "$UI_N"; }

# ui_fit_v TEXT WIDTH — UI_FIT = plain TEXT cut to WIDTH cells with an ellipsis.
ui_fit_v() {
  local LC_ALL=C.UTF-8
  if (( ${#1} <= $2 )); then UI_FIT=$1; elif (( $2 > 1 )); then UI_FIT="${1:0:$(( $2 - 1 ))}…"; else UI_FIT=""; fi
}

# ui_repeat_v CHAR N — UI_REP = CHAR repeated N times.
ui_repeat_v() { local s; printf -v s '%*s' "$2" ""; UI_REP=${s// /$1}; }

# ui_pill HEX TEXT [FG] — TEXT on a rounded HEX chip: step numbers, the job
# tag on a banner, key caps.
ui_pill() {
  local hex="$1" text="$2" fg="${3:-$UI_BG}" e b f
  if (( ! UI_COLOR )); then printf '[%s]' "$text"; return; fi
  ui_fg e "$hex"; ui_bg b "$hex"; ui_fg f "$fg"
  printf '%s' "$e$UI_CAP_L$b$f$UI_BLD$text$UI_NBLD$UI_RBG$e$UI_CAP_R$UI_RFG"
}

# ui_logo LINE… — the DOTS wordmark, gradient across its columns, with up to
# three lines of context beside it.
UI_LOGO=(
  "█▀▀▄ ▄▀▀▄ ▀▀█▀▀ ▄▀▀▀"
  "█  █ █  █   █    ▀▀▄"
  "█▄▄▀ ▀▄▄▀   █   ▄▄▄▀"
)
ui_logo() {
  local row i out ch LC_ALL=C.UTF-8
  echo
  for row in 0 1 2; do
    out=""
    for (( i = 0; i < ${#UI_LOGO[row]}; i++ )); do
      ch=${UI_LOGO[row]:i:1}
      if [[ "$ch" == " " ]] || (( ! UI_COLOR )); then out+=$ch; continue; fi
      ui_grad $(( i * 1000 / (${#UI_LOGO[row]} - 1) ))
      out+=$'\033[38;2;'"${UI_RGB}m$ch"
    done
    printf '   %s%s    %s\n' "$out" "$UI_RFG" "${*:row+1:1}"
  done
}

# ui_header TITLE [RIGHT] — the one-line wordmark a CLI run starts with.
#     D O T S  ·  system-rebuild                         Sisyphus · rock
ui_header() {
  local title="$1" right="${2:-}" left pad
  left="  $(ui_c "$UI_BLUE" "$UI_I_NIX")  $(ui_gradient "D O T S")  $(ui_dim "·")  $(ui_bold "$(ui_c "$UI_FG" "$title")")"
  ui_vlen_v "$left"
  pad=$(( UI_WIDTH - UI_N - ${#right} ))
  (( pad < 2 )) && pad=2
  echo
  printf '%s%*s%s\n' "$left" "$pad" "" "$(ui_c "$UI_PURPLE" "$right")"
  ui_rule
}

# ui_rule [LABEL] — a thin divider, optionally labelled: ── LABEL ──────────
ui_rule() {
  local label="${1:-}"
  if [[ -n "$label" ]]; then
    ui_repeat_v ─ $(( UI_WIDTH - ${#label} - 7 ))
    printf '  %s %s %s\n' "$(ui_c "$UI_LINE" "──")" "$(ui_bold "$(ui_c "$UI_BLUE" "$label")")" "$(ui_c "$UI_LINE" "$UI_REP")"
  else
    ui_repeat_v ─ $(( UI_WIDTH - 2 ))
    printf '  %s\n' "$(ui_c "$UI_LINE" "$UI_REP")"
  fi
}

# ui_banner HEX TAG TITLE [SUB] [RIGHT] — the head of a job: a TAG pill, what
# it acts on, and a tinted rule.
#      SWITCH   Sisyphus  this machine                       rock-Sisyphus
ui_banner() {
  local hex="$1" tag="$2" title="$3" sub="${4:-}" right="${5:-}" left pad tint
  left="  $(ui_pill "$hex" " $tag ")  $(ui_bold "$(ui_c "$UI_FG" "$title")")${sub:+  $(ui_dim "$sub")}"
  ui_vlen_v "$left"
  pad=$(( UI_WIDTH - UI_N - ${#right} ))
  (( pad < 2 )) && pad=2
  echo
  printf '%s%*s%s\n' "$left" "$pad" "" "$(ui_dim "$right")"
  ui_mix tint "$hex" "$UI_BG" 45
  ui_repeat_v ─ $(( UI_WIDTH - 2 ))
  printf '  %s\n' "$(ui_c "$tint" "$UI_REP")"
}

# ui_stage HEX N TITLE — one numbered step of a job:  ⬤1  Build ───────────
ui_stage() {
  local head
  head="  $(ui_pill "$1" " $2 ")  $(ui_bold "$3") "
  ui_vlen_v "$head"
  ui_repeat_v ─ $(( UI_WIDTH - UI_N ))
  printf '\n%s%s\n' "$head" "$(ui_c "$UI_LINE" "$UI_REP")"
}

ui_ok()   { printf '  %s %s\n' "$(ui_c "$UI_GREEN" "✔")" "$*"; }
ui_err()  { printf '  %s %s\n' "$(ui_c "$UI_RED" "✘")" "$*" >&2; }
ui_warn() { printf '  %s %s\n' "$(ui_c "$UI_YELLOW" "!")" "$*"; }
ui_info() { printf '  %s %s\n' "$(ui_c "$UI_BLUE" "›")" "$*"; }
ui_step() { printf '\n  %s %s\n' "$(ui_c "$UI_AQUA" "▶")" "$(ui_bold "$*")"; }

# ui_kv KEY VALUE — an aligned "key   value" row inside a section.
ui_kv() { printf '    %s %s\n' "$(ui_dim "$(printf '%-10s' "$1")")" "$2"; }

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
  local maxw=$(( UI_WIDTH - 10 )) w=0 l piece
  local -a rows=()
  for l in "$@"; do
    ui_vlen_v "$l"
    if (( UI_N <= maxw )); then rows+=("$l"); continue; fi
    # Too long: wrap the plain text (its colour is lost — only ever a command
    # or a path, where wrapping beats running off the edge).
    l=$(printf '%s' "$l" | sed 's/\x1b\[[0-9;]*m//g')
    while IFS= read -r piece; do rows+=("$piece"); done < <(LC_ALL=C.UTF-8 fold -w "$maxw" <<<"$l")
  done
  for l in "$title" "${rows[@]}"; do ui_vlen_v "$l"; (( UI_N > w )) && w=$UI_N; done
  (( w > maxw )) && w=$maxw
  ui_repeat_v ─ $(( w + 4 ))
  printf '\n  %s\n' "$(ui_c "$colour" "╭${UI_REP}╮")"
  for l in "$(ui_bold "$(ui_c "$colour" "$title")")" "" "${rows[@]}"; do
    ui_vlen_v "$l"
    printf '  %s  %s%*s  %s\n' "$(ui_c "$colour" "│")" "$l" $(( w - UI_N )) "" "$(ui_c "$colour" "│")"
  done
  printf '  %s\n\n' "$(ui_c "$colour" "╰${UI_REP}╯")"
}

# ── Panels ────────────────────────────────────────────────────────────────────
# A panel is a full-width rounded frame: a title (or breadcrumb) set into the
# top border, rows of BODY, a bottom border. Menus are panels too. Geometry,
# for every row:   ␣␣│␣<cap><body: UI_WIDTH-8><cap>␣│
# The caps are spaces, or the round ends of a highlighted row.

# _ui_border MODE TEXT COL — append TEXT to UI_OUT in border colour, starting at
# column COL. MODE is "grad" (the gradient, column by column) or an escape.
_ui_border() {
  local mode="$1" text="$2" col="$3" i LC_ALL=C.UTF-8
  if [[ "$mode" != grad ]] || (( ! UI_COLOR )); then
    [[ "$mode" == grad ]] && mode=""
    UI_OUT+="$mode$text$UI_RFG"
    return
  fi
  for (( i = 0; i < ${#text}; i++ )); do UI_OUT+="${UI_GRAD[col + i]}${text:i:1}"; done
  UI_OUT+=$UI_RFG
}

# _ui_top MODE TITLE → UI_OUT = "  ╭─ TITLE ───…╮" (TITLE already coloured).
_ui_top() {
  ui_vlen_v "$2"
  local tl=$UI_N
  ui_repeat_v ─ $(( UI_WIDTH - 7 - tl ))
  UI_OUT="  "
  _ui_border "$1" "╭─ " 2
  UI_OUT+=$2
  _ui_border "$1" " ${UI_REP}╮" $(( 5 + tl ))
}
# _ui_bottom MODE → UI_OUT = "  ╰────…╯"
_ui_bottom() {
  ui_repeat_v ─ $(( UI_WIDTH - 4 ))
  UI_OUT="  "
  _ui_border "$1" "╰${UI_REP}╯" 2
}
# _ui_row MODE BODY [CAPL CAPR] → UI_OUT = one framed row; BODY is padded to
# the body width (it must already fit).
_ui_row() {
  ui_vlen_v "$2"
  local pad=$(( UI_WIDTH - 8 - UI_N ))
  (( pad < 0 )) && pad=0
  UI_OUT="  "
  _ui_border "$1" "│" 2
  printf -v UI_OUT '%s %s%s%*s%s ' "$UI_OUT" "${3:- }" "$2" "$pad" "" "${4:- }"
  _ui_border "$1" "│" $(( UI_WIDTH - 1 ))
}

# ui_panel BORDER-HEX TITLE ROW… — print a framed panel of pre-coloured rows.
ui_panel() {
  local mode row
  ui_fg mode "$1"
  _ui_top "$mode" "$(ui_bold "$(ui_c "$UI_DIM" "$2")")"; printf '%s\n' "$UI_OUT"
  shift 2
  for row in "$@"; do _ui_row "$mode" "$row"; printf '%s\n' "$UI_OUT"; done
  _ui_bottom "$mode"; printf '%s\n' "$UI_OUT"
}

# ── Menus ─────────────────────────────────────────────────────────────────────
# A menu is described, then shown:
#
#   ui_menu_new
#   ui_note "context, not selectable"
#   ui_item KEY ICON LABEL [DESC] [META] [COLOUR]
#   ui_gap
#   ui_item_back                       (or ui_item_quit at the top level)
#   ui_menu ACCENT CRUMB…              → UI_CHOICE
#
# UI_CHOICE is the picked item's KEY, "back" (esc, ←, h, backspace) or "quit"
# (q). Items are numbered 1–9 in order and the number picks one directly.
# UI_MENU_SEL=KEY starts the cursor on that item (it is cleared after each
# menu). ACCENT tints the frame and the cursor; "grad" uses the house gradient.
#
# It draws inline on stderr — stdout stays free for $(ui_choose …) — and
# erases itself once a choice is made, so the next menu or the job's output
# takes its place.
UI_CHOICE=""
UI_MENU_SEL=""
_UM_T=() _UM_K=() _UM_I=() _UM_L=() _UM_D=() _UM_M=() _UM_C=()

ui_menu_new() { _UM_T=(); _UM_K=(); _UM_I=(); _UM_L=(); _UM_D=(); _UM_M=(); _UM_C=(); }
ui_item() { _UM_T+=(item); _UM_K+=("$1"); _UM_I+=("${2:- }"); _UM_L+=("$3"); _UM_D+=("${4:-}"); _UM_M+=("${5:-}"); _UM_C+=("${6:-}"); }
ui_note() { _UM_T+=(note); _UM_K+=(""); _UM_I+=(""); _UM_L+=("$1"); _UM_D+=(""); _UM_M+=(""); _UM_C+=(""); }
ui_gap()  { _UM_T+=(gap); _UM_K+=(""); _UM_I+=(""); _UM_L+=(""); _UM_D+=(""); _UM_M+=(""); _UM_C+=(""); }
ui_item_back() { ui_gap; ui_item back "$UI_I_BACK" Back "" esc "$UI_DIM"; }
ui_item_quit() { ui_gap; ui_item quit "$UI_I_QUIT" Quit "" q "$UI_DIM"; }

# ui_read_key — UI_KEY = up / down / enter / back / quit / home / end / eof,
# or the character typed.
ui_read_key() {
  local k="" r=""
  IFS= read -rsn1 k || { UI_KEY=eof; return 0; }
  if [[ "$k" == $'\e' ]]; then   # an escape sequence, or Esc on its own
    while IFS= read -rsn1 -t 0.03 r; do k+=$r; [[ "$r" == [[:alpha:]~] ]] && break; done
  fi
  case "$k" in
    "" | " " | l | $'\e[C' | $'\eOC') UI_KEY=enter ;;
    k | $'\e[A' | $'\eOA') UI_KEY=up ;;
    j | $'\t' | $'\e[B' | $'\eOB') UI_KEY=down ;;
    h | $'\e' | $'\e[D' | $'\eOD' | $'\x7f' | $'\b') UI_KEY=back ;;
    g | $'\e[H' | $'\e[1~') UI_KEY=home ;;
    G | $'\e[F' | $'\e[4~') UI_KEY=end ;;
    q | Q) UI_KEY=quit ;;
    *) UI_KEY=$k ;;
  esac
}

# Terminal state a menu changes, put back on exit or ^C.
UI_STTY=""
ui_term_grab() {
  UI_STTY=$(stty -g 2>/dev/null || true)
  stty -echo 2>/dev/null || true
  (( UI_COLOR )) && printf '\033[?25l' >&2
  return 0
}
ui_term_release() {
  [[ -n "$UI_STTY" ]] && stty "$UI_STTY" 2>/dev/null
  UI_STTY=""
  (( UI_COLOR )) && printf '\033[?25h' >&2
  return 0
}

ui_menu() {
  local accent="$1"; shift
  local LC_ALL=C.UTF-8
  UI_CHOICE=quit
  if (( ! UI_INTERACTIVE )); then
    ui_err "a choice is needed but this isn't an interactive terminal"; return 0
  fi

  # ── frame colours
  local mode cur_hex
  if [[ "$accent" == grad ]]; then mode=grad; accent=$UI_AQUA
  else ui_mix cur_hex "$accent" "$UI_BG" 55; ui_fg mode "$cur_hex"; fi
  local e_acc e_fg e_dim e_line
  ui_fg e_acc "$accent"; ui_fg e_fg "$UI_FG"; ui_fg e_dim "$UI_DIM"; ui_fg e_line "$UI_LINE"

  # ── breadcrumb, set into the top border
  local crumb="" k last=$(( $# - 1 )) c=0
  for k in "$@"; do
    (( c )) && crumb+="$e_line › $UI_RFG"
    if (( c == 0 )) && [[ "$k" == DOTS ]]; then
      local e_blue; ui_fg e_blue "$UI_BLUE"
      crumb+="$e_blue$UI_I_NIX$UI_RFG $(ui_gradient DOTS)"
    elif (( c == last )); then crumb+="$UI_BLD$e_acc$k$UI_RFG$UI_NBLD"
    else crumb+="$e_fg$k$UI_RFG"; fi
    c=$(( c + 1 ))
  done

  # ── rows: each item rendered twice, plain and highlighted
  local n=${#_UM_T[@]} i lw=8 num=0 bw=$(( UI_WIDTH - 8 ))
  for (( i = 0; i < n; i++ )); do
    [[ "${_UM_T[i]}" == item ]] && (( ${#_UM_L[i]} + 3 > lw )) && lw=$(( ${#_UM_L[i]} + 3 ))
  done
  (( lw > bw - 12 )) && lw=$(( bw - 12 ))
  local -a plain=() lit=() sels=() nums=()
  local col hl e_col e_hl e_hlb e_lab nm label desc meta mlen dmax avail pad lp
  for (( i = 0; i < n; i++ )); do
    case "${_UM_T[i]}" in
      gap)  _ui_row "$mode" ""; plain[i]=$UI_OUT; lit[i]=$UI_OUT; continue ;;
      note)
        ui_vlen_v "${_UM_L[i]}"
        if (( UI_N > bw - 1 )); then ui_fit_v "$(printf '%s' "${_UM_L[i]}" | sed 's/\x1b\[[0-9;]*m//g')" $(( bw - 1 )); _ui_row "$mode" " $UI_FIT"
        else _ui_row "$mode" " ${_UM_L[i]}"; fi
        plain[i]=$UI_OUT; lit[i]=$UI_OUT; continue ;;
    esac
    sels+=("$i")
    col=${_UM_C[i]:-$accent}
    ui_fg e_col "$col"
    ui_mix hl "$col" "$UI_BG" 22
    ui_bg e_hlb "$hl"; ui_fg e_hl "$hl"
    nm=" "
    if [[ "${_UM_K[i]}" != back && "${_UM_K[i]}" != quit ]] && (( num < 9 )); then num=$(( num + 1 )); nm=$num; fi
    nums[i]=$nm
    ui_fit_v "${_UM_L[i]}" $(( lw - 1 )); label=$UI_FIT
    desc=${_UM_D[i]}; meta=${_UM_M[i]}
    [[ -n "$meta" && "$meta" != *$'\033'* ]] && meta="$e_dim$meta$UI_RFG"
    ui_vlen_v "$meta"; mlen=$UI_N
    avail=$(( bw - 7 - lw - 1 ))
    dmax=$avail; (( mlen )) && dmax=$(( avail - mlen - 2 ))
    if (( dmax < 4 && mlen )); then meta=""; mlen=0; dmax=$avail; fi
    ui_fit_v "$desc" "$dmax"; desc=$UI_FIT
    pad=$(( avail - ${#desc} - mlen ))
    lp=$(( lw - ${#label} ))
    # A red item (one that destroys something) says so before it's selected.
    e_lab=$e_fg; [[ "$col" == "$UI_RED" ]] && e_lab=$e_col
    _ui_row "$mode" "$(printf ' %s  %s  %s%*s%s%*s%s ' \
      "$e_dim$nm$UI_RFG" "$e_col${_UM_I[i]}$UI_RFG" "$e_lab$label$UI_RFG" "$lp" "" \
      "$e_dim$desc$UI_RFG" "$pad" "" "$meta")"
    plain[i]=$UI_OUT
    if (( UI_COLOR )); then
      _ui_row "$mode" "$(printf '%s %s  %s  %s%*s%s%*s%s %s' "$e_hlb" \
        "$UI_BLD$e_col$nm" "${_UM_I[i]}" "$label$UI_RFG$UI_NBLD" "$lp" "" \
        "$e_fg$desc$UI_RFG" "$pad" "" "$meta" "$UI_RBG")" \
        "$e_hl$UI_CAP_L$UI_RFG" "$e_hl$UI_CAP_R$UI_RFG"
    else
      _ui_row "$mode" "$(printf ' %s  %s  %s%*s%s%*s%s ' "$nm" "${_UM_I[i]}" "$label" "$lp" "" "$desc" "$pad" "" "$meta")" "▸" " "
    fi
    lit[i]=$UI_OUT
  done
  (( ${#sels[@]} )) || { ui_err "empty menu"; return 0; }

  local top bottom foot
  _ui_top "$mode" "$crumb"; top=$UI_OUT
  _ui_bottom "$mode"; bottom=$UI_OUT
  local kc="$e_fg" kd="$e_dim"
  foot="     $kc↑↓$kd move   $kc⏎$kd select"
  (( num )) && foot+="   ${kc}1–$num$kd pick"
  if [[ " ${_UM_K[*]} " == *" back "* ]]; then foot+="   ${kc}esc$kd back   ${kc}q$kd quit$UI_RFG"
  else foot+="   ${kc}q$kd quit$UI_RFG"; fi

  # ── start position
  local pos=0
  if [[ -n "$UI_MENU_SEL" ]]; then
    for k in "${!sels[@]}"; do [[ "${_UM_K[sels[k]]}" == "$UI_MENU_SEL" ]] && pos=$k; done
  fi
  UI_MENU_SEL=""

  # ── draw / key loop
  local total=$(( n + 3 )) frame drawn=0 j
  ui_term_grab
  while :; do
    frame="$top"$'\033[K\n'
    for (( j = 0; j < n; j++ )); do
      if (( j == sels[pos] )); then frame+="${lit[j]}"; else frame+="${plain[j]}"; fi
      frame+=$'\033[K\n'
    done
    frame+="$bottom"$'\033[K\n'"$foot"$'\033[K\n'
    (( drawn )) && printf '\033[%dF' "$total" >&2
    printf '%s' "$frame" >&2
    drawn=1
    ui_read_key
    case "$UI_KEY" in
      up)    pos=$(( (pos - 1 + ${#sels[@]}) % ${#sels[@]} )) ;;
      down)  pos=$(( (pos + 1) % ${#sels[@]} )) ;;
      home)  pos=0 ;;
      end)   pos=$(( ${#sels[@]} - 1 )) ;;
      enter) UI_CHOICE=${_UM_K[sels[pos]]}; break ;;
      back)  UI_CHOICE=back; break ;;
      quit | eof) UI_CHOICE=quit; break ;;
      [1-9])
        for k in "${!sels[@]}"; do
          if [[ "${nums[sels[k]]}" == "$UI_KEY" ]]; then pos=$k; UI_CHOICE=${_UM_K[sels[k]]}; break 2; fi
        done ;;
    esac
  done
  printf '\033[%dF\033[J' "$total" >&2
  ui_term_release
}

# ── Prompts (interactive only) ────────────────────────────────────────────────

# ui_choose HEADER "Label:value"… — a one-off menu; prints the chosen VALUE,
# non-zero on esc / q. For "pick one of these" questions inside a job.
ui_choose() {
  local header="$1" it
  shift
  (( UI_INTERACTIVE )) || { ui_err "a choice is needed but this isn't an interactive terminal"; return 2; }
  ui_menu_new
  for it in "$@"; do ui_item "${it##*:}" "›" "${it%:*}"; done
  ui_menu "$UI_AQUA" "$header"
  [[ "$UI_CHOICE" == back || "$UI_CHOICE" == quit ]] && return 1
  printf '%s\n' "$UI_CHOICE"
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

# ui_spin TITLE CMD… — run an external command behind a spinner, showing its
# output. (gum spin runs commands, not shell functions.)
ui_spin() {
  local title="$1"; shift
  if (( UI_COLOR && UI_INTERACTIVE )); then
    gum spin --title " $title" --show-output -- "$@"
  else
    "$@"
  fi
}
# ui_spin_out TITLE CMD… — the same, but only the command's stdout comes out
# (on stdout), so $(ui_spin_out …) captures a result.
ui_spin_out() {
  local title="$1"; shift
  if (( UI_COLOR && UI_INTERACTIVE )); then
    gum spin --title " $title" --show-stdout -- "$@"
  else
    "$@" 2>/dev/null
  fi
}

# ui_keys_wait — after a job: ⏎ goes back to the menu (status 0), anything
# else (q, esc, ^D) leaves (status 1).
ui_keys_wait() {
  printf '\n  %s %s   %s %s\n' \
    "$(ui_pill "$UI_LINE" " ⏎ " "$UI_FG")" "$(ui_dim "back to the menu")" \
    "$(ui_pill "$UI_LINE" " q " "$UI_FG")" "$(ui_dim "quit")"
  (( UI_INTERACTIVE )) || return 1
  ui_term_grab
  ui_read_key
  ui_term_release
  [[ "$UI_KEY" == enter || "$UI_KEY" == back ]]
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

# Leave the terminal sane on ^C: gum restores its own state; a menu may have
# hidden the cursor and turned echo off.
ui_on_interrupt() { ui_term_release; printf '\n  %s\n\n' "$(ui_dim "cancelled")"; exit 130; }
trap ui_on_interrupt INT

# ── end of ui.sh ──────────────────────────────────────────────────────────────

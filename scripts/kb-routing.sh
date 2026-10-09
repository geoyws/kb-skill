# Shared hosts.tsv routing and shell quoting for the three public wrappers.
# The caller supplies router_name and die(), plus the BOARD_* arrays.
shell_quote() {
  local value=${1-}
  local out="'"
  local prefix
  while [[ "$value" == *"'"* ]]; do
    prefix=${value%%"'"*}
    out+=$prefix
    out+="'\"'\"'"
    value=${value#*\'}
  done
  out+=$value
  out+="'"
  printf '%s' "$out"
}

board_exists() {
  local needle=$1 i
  for i in "${!BOARD_IDS[@]}"; do
    [[ "${BOARD_IDS[$i]}" = "$needle" ]] && return 0
  done
  return 1
}

lookup_board() {
  local needle=$1 i
  for i in "${!BOARD_IDS[@]}"; do
    if [[ "${BOARD_IDS[$i]}" = "$needle" ]]; then
      BOARD_HOME_HOST=${BOARD_HOME_HOSTS[$i]}
      BOARD_SSH_TARGET=${BOARD_SSH_TARGETS[$i]}
      BOARD_EXPECTED_REMOTE_HOST=${BOARD_EXPECTED_REMOTE_HOSTS[$i]}
      BOARD_KB_EXEC=${BOARD_KB_EXECS[$i]}
      return 0
    fi
  done
  return 1
}

load_table() {
  local table_file=$1
  [[ -r "$table_file" ]] || die "$router_name: routing table is not readable: $table_file"
  local line board home_host ssh_target expected_remote kb_exec extra
  local loaded=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    IFS=$'\t' read -r board home_host ssh_target expected_remote kb_exec extra <<<"$line"
    if [[ -n "${extra-}" || -z "${board-}" || -z "${home_host-}" || -z "${ssh_target-}" || -z "${expected_remote-}" || -z "${kb_exec-}" ]]; then
      die "$router_name: malformed routing row: $line"
    fi
    case "$kb_exec" in
      /*) ;;
      *) die "$router_name: KB executable path must be absolute: $kb_exec" ;;
    esac
    if board_exists "$board"; then
      die "$router_name: duplicate board mapping: $board"
    fi
    BOARD_IDS+=("$board")
    BOARD_HOME_HOSTS+=("$home_host")
    BOARD_SSH_TARGETS+=("$ssh_target")
    BOARD_EXPECTED_REMOTE_HOSTS+=("$expected_remote")
    BOARD_KB_EXECS+=("$kb_exec")
    loaded=1
  done <"$table_file"
  [[ "$loaded" -eq 1 ]] || die "$router_name: routing table has no rows: $table_file"
}

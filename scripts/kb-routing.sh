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

has_flag() {
  local name=$1
  shift
  local arg
  for arg in "$@"; do
    case "$arg" in
      "$name"|"$name="*) return 0 ;;
    esac
  done
  return 1
}

repo_identity_error() {
  printf '%s: %s\n' "$router_name" "$1" >&2
  exit 64
}

# Preserve ordinary argv, replacing --repo with a caller-derived key. Both
# wrappers source this file and pass the result as repo_identity_args. In
# particular, no routed lease write may capture the registry host's cwd.
capture_repo_identity() {
  local command=$1 explicit_repo="" repo_supplied=0 repo_path key
  shift
  local -a identity_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        [[ "$repo_supplied" -eq 0 ]] || repo_identity_error 'duplicate --repo option'
        [[ $# -ge 2 ]] || repo_identity_error '--repo requires a path'
        case "$2" in
          --repo|--repo=*) repo_identity_error 'duplicate --repo option' ;;
        esac
        explicit_repo=$2
        repo_supplied=1
        shift 2 ;;
      --repo=*)
        [[ "$repo_supplied" -eq 0 ]] || repo_identity_error 'duplicate --repo option'
        explicit_repo=${1#*=}
        repo_supplied=1
        shift ;;
      *) identity_args+=("$1"); shift ;;
    esac
  done
  repo_identity_args=("${identity_args[@]}")
  # The binary refuses this pair before any write; stripping --repo here
  # would hide the conflict, so refuse on the caller before ssh.
  if [[ "$repo_supplied" -eq 1 ]] && has_flag --no-repo-capture "${repo_identity_args[@]}"; then
    repo_identity_error '--repo and --no-repo-capture are mutually exclusive'
  fi
  if ! has_flag --repo-key "${repo_identity_args[@]}" && { [[ "$repo_supplied" -eq 1 ]] || ! has_flag --no-repo-capture "${repo_identity_args[@]}"; }; then
    if [[ "$repo_supplied" -eq 1 ]]; then
      repo_path=$explicit_repo
    elif [[ "$command" = heartbeat || "$command" = hb ]]; then
      repo_path=""
    else
      repo_path=$PWD
    fi
    if [[ -n "$repo_path" ]]; then
      key=$(python3 "$script_dir/kb-repo-identity.py" key "$repo_path") || repo_identity_error 'cannot derive repository identity'
      [[ -z "$key" ]] || repo_identity_args+=(--repo-key "$key")
    fi
  fi
  has_flag --no-repo-capture "${repo_identity_args[@]}" || repo_identity_args+=(--no-repo-capture)
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

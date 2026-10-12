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
      BOARD_LOGIN="${BOARD_LOGINS[$i]}"
      return 0
    fi
  done
  return 1
}

load_table() {
  local table_file=$1
  [[ -r "$table_file" ]] || die "$router_name: routing table is not readable: $table_file"
  local line board home_host ssh_target expected_remote kb_exec extra login fields rest
  local loaded=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    fields=0 rest=$line
    while [[ "$rest" == *$'\t'* ]]; do
      fields=$((fields + 1))
      rest=${rest#*$'\t'}
    done
    [[ $fields -eq 4 || $fields -eq 5 ]] || die "$router_name: malformed routing row: $line"
    if [[ $fields -eq 5 ]]; then
      login=$rest
      rest=${line%$'\t'*}
    else
      login=ssh
      rest=$line
    fi
    [[ "$rest" != *$'\t\t'* ]] || die "$router_name: malformed routing row: $line"
    IFS=$'\t' read -r board home_host ssh_target expected_remote kb_exec extra <<<"$rest"
    if [[ -n "${extra-}" || -z "${board-}" || -z "${home_host-}" || -z "${ssh_target-}" || -z "${expected_remote-}" || -z "${kb_exec-}" ]]; then
      die "$router_name: malformed routing row: $line"
    fi
    case "$login" in
      ssh|own) ;;
      *) repo_identity_error "login must be ssh or own: $login" ;;
    esac
    case "$kb_exec" in
      /*) ;;
      *) die "$router_name: KB executable path must be absolute: $kb_exec" ;;
    esac
    if [[ $login = own && $kb_exec = /root/* ]]; then
      repo_identity_error "board $board routes as your own login, so its KB executable must be one every login can run, not under /root: $kb_exec"
    fi
    if board_exists "$board"; then
      die "$router_name: duplicate board mapping: $board"
    fi
    BOARD_IDS+=("$board")
    BOARD_HOME_HOSTS+=("$home_host")
    BOARD_SSH_TARGETS+=("$ssh_target")
    BOARD_EXPECTED_REMOTE_HOSTS+=("$expected_remote")
    BOARD_KB_EXECS+=("$kb_exec")
    BOARD_LOGINS+=("$login")
    loaded=1
  done <"$table_file"
  [[ "$loaded" -eq 1 ]] || die "$router_name: routing table has no rows: $table_file"
}

# The effective remote user is a security boundary, not an actor assertion.
# A five-field route must never make this probe: its existing ssh argv is stable.
own_login_ssh_args() {
  local board=$1 target=$2 user='' key value
  own_login_args=()
  [[ $BOARD_LOGIN = own ]] || return 0
  if [[ -n ${KB_SSH_LOGIN-} ]]; then
    user=$KB_SSH_LOGIN
    own_login_args=(-l "$user")
  else
    local config
    config=$( "$ssh_bin" -G "$target" ) || repo_identity_error "cannot resolve ssh user for $target"
    while read -r key value _; do
      if [[ $key = user ]]; then user=$value; break; fi
    done <<<"$config"
    [[ -n $user ]] || repo_identity_error "board $board routes as your own login, but ssh -G $target named no user; set User for $target in your ssh config or export KB_SSH_LOGIN"
  fi
  [[ $user != root ]] || repo_identity_error "board $board routes as your own login, but ssh would log in to $target as root; set User for $target in your ssh config or export KB_SSH_LOGIN"
}

own_login_local_guard() {
  local board=$1
  [[ $BOARD_LOGIN != own || $EUID -ne 0 ]] || repo_identity_error "board $board routes as your own login, but this shell is root; run $router_name from your own account"
}

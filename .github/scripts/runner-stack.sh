#!/usr/bin/env bash
# One job per registered runner instance: N parallel jobs on a host = N registered installs, managed here as a stack over a base install.
set -euo pipefail

# .runner field names and per-instance state files verified against actions/runner's ConfigurationStore.cs and HostContext.cs.

PROG="$(basename "$0")"
DRY_RUN=0
BASE_OVERRIDE=""
LABELS=""
TOKEN=""

# Per-instance state: fresh copies must not inherit the base's identity/runtime state.
EXCLUDES=(
	_work
	_diag
	.runner
	.runner_migrated
	.credentials
	.credentials_migrated
	.credentials_rsaparams
	.certificates
	.options
	.setup_info
	.service
	.runner-stack-labels
	.path
	update.finished
	svc.sh
	runsvc.sh
)

die() {
	echo "${PROG}: error: $*" >&2
	exit 1
}

usage() {
	cat <<EOF
Usage: ${PROG} <status|add|remove> [options]

  status                 List stack instances: base dir, name, service state, _work dir.
  add                    Push one more runner instance onto the stack.
  remove                 Pop the highest-numbered instance off the stack.

Options:
  --base <dir>           Base runner install (default: script dir if it has config.sh,
                          else /opt/actions-runner, else /home/ubuntu/actions-runner).
  --labels <a,b,...>     Labels for a new instance (add only). Defaults to the contents
                          of <base>/.runner-stack-labels; required (and saved there) the
                          first time.
  --token <TOKEN>        Registration token (add) or removal token (remove). Falls back
                          to \$RUNNER_TOKEN. If neither is set, prints a gh CLI snippet to
                          run on your own workstation and exits 2.
  --dry-run              Print the commands add/remove would run, without running them.
  -h, --help             Show this help.

Environment:
  RUNNER_TOKEN                  Same as --token.
  RUNNER_STACK_SKIP_ROOT_CHECK  TEST-ONLY: set to 1 to bypass the "must run as root" check.

add/remove must be run as root: runner services are installed under root via svc.sh.
EOF
}

require_root() {
	[[ "${RUNNER_STACK_SKIP_ROOT_CHECK:-}" == "1" ]] && return 0
	[[ "${EUID}" -eq 0 ]] || die "must be run as root (manages systemd services as root)"
}

detect_base() {
	if [[ -n "${BASE_OVERRIDE}" ]]; then
		printf '%s\n' "${BASE_OVERRIDE%/}"
		return 0
	fi
	local script_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	if [[ -f "${script_dir}/config.sh" ]]; then
		printf '%s\n' "${script_dir}"
	elif [[ -f /opt/actions-runner/config.sh ]]; then
		printf '%s\n' /opt/actions-runner
	elif [[ -f /home/ubuntu/actions-runner/config.sh ]]; then
		printf '%s\n' /home/ubuntu/actions-runner
	else
		die "could not detect a base runner install; pass --base <dir>"
	fi
}

# jq if present; else a two-field-only grep+expansion fallback (no sed on JSON).
runner_field() {
	local file="$1" field="$2" raw value
	[[ -f "${file}" ]] || return 0
	if command -v jq >/dev/null 2>&1; then
		jq -r --arg f "${field}" '.[$f] // empty' "${file}"
	else
		raw=$(grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "${file}" | head -n1) || true
		value=${raw#*:}
		value=${value#*\"}
		value=${value%\"}
		printf '%s\n' "${value}"
	fi
}

# Highest existing "<base>-N" index; returns 1 if only the base install exists.
highest_index() {
	local base="$1" i=2 last=1
	while [[ -d "${base}-${i}" ]]; do
		last=${i}
		i=$((i + 1))
	done
	printf '%s\n' "${last}"
}

next_index() {
	local base="$1" i=2
	while [[ -d "${base}-${i}" ]]; do
		i=$((i + 1))
	done
	printf '%s\n' "${i}"
}

list_instance_dirs() {
	local base="$1" i=2
	printf '%s\n' "${base}"
	while [[ -d "${base}-${i}" ]]; do
		printf '%s\n' "${base}-${i}"
		i=$((i + 1))
	done
}

# Run a command inside $1 as a directory, honoring --dry-run.
run_step() {
	local dir="$1"
	shift
	if ((DRY_RUN)); then
		printf '+ (cd %q && %s)\n' "${dir}" "$(printf '%q ' "$@")"
	else
		(cd "${dir}" && "$@")
	fi
}

copy_instance() {
	local src="$1" dst="$2" entry name ex skip target
	if ((DRY_RUN)); then
		printf '+ mkdir -p %q\n' "${dst}"
		printf '+ cp -a %q/* %q/  (excluding: %s, bin.*, externals.*, *.tar.gz; bin/externals symlinks dereferenced)\n' "${src}" "${dst}" "${EXCLUDES[*]}"
		return 0
	fi
	mkdir -p "${dst}"
	shopt -s dotglob nullglob
	for entry in "${src}"/*; do
		name="$(basename "${entry}")"
		case "${name}" in bin.* | externals.* | *.tar.gz) continue ;; esac
		skip=0
		for ex in "${EXCLUDES[@]}"; do
			[[ "${name}" == "${ex}" ]] && {
				skip=1
				break
			}
		done
		((skip)) && continue
		if [[ ("${name}" == "bin" || "${name}" == "externals") && -L "${entry}" ]]; then
			target=$(readlink -f "${entry}") # self-update leaves bin/externals as symlinks into the base; each instance needs its own copy
			cp -a "${target}" "${dst}/${name}"
		else
			cp -a "${entry}" "${dst}/"
		fi
	done
	shopt -u dotglob nullglob
}

# orgs/<org>/... for an org URL, repos/<owner>/<repo>/... for a repo URL.
gh_api_path() {
	local gh_url="$1" kind="$2" path segs owner repo
	path="${gh_url#*://}"
	path="${path#*/}"
	path="${path%/}"
	IFS='/' read -r -a segs <<<"${path}"
	case "${#segs[@]}" in
	1) printf 'orgs/%s/actions/runners/%s-token\n' "${segs[0]}" "${kind}" ;;
	2)
		owner=${segs[0]}
		repo=${segs[1]}
		printf 'repos/%s/%s/actions/runners/%s-token\n' "${owner}" "${repo}" "${kind}"
		;;
	*) die "cannot derive org/repo from gitHubUrl '${gh_url}'" ;;
	esac
}

print_token_snippet() {
	local action="$1" gh_url="$2" kind api_path
	kind="registration"
	[[ "${action}" == "remove" ]] && kind="remove"
	api_path=$(gh_api_path "${gh_url}" "${kind}")
	cat <<EOF
No token given (--token / \$RUNNER_TOKEN). Mint a short-lived one on your own
workstation, with gh authenticated as a user who has the org "Self-hosted
runners" permission, then re-run here:

  gh api -X POST ${api_path} --jq .token

Note: needs the admin:org scope, or a fine-grained PAT with org permission
"Self-hosted runners: Read and write" (pass it as GH_TOKEN=<pat> gh api ...).
The token is valid for one hour.

Then:

  sudo ./${PROG} ${action} --token <paste>
EOF
}

cmd_status() {
	local base dir name work svc active
	base=$(detect_base)
	echo "Stack base: ${base}"
	printf '%-30s %-25s %-10s %s\n' "INSTANCE" "NAME" "SERVICE" "WORK DIR"
	while IFS= read -r dir; do
		name=$(runner_field "${dir}/.runner" agentName)
		[[ -n "${name}" ]] || name="(not configured)"
		work=$(runner_field "${dir}/.runner" workFolder)
		[[ -n "${work}" ]] || work="_work"
		[[ "${work}" == /* ]] || work="${dir}/${work}"
		if [[ -f "${dir}/.service" ]]; then
			svc=$(cat "${dir}/.service")
			active=$(systemctl is-active "${svc}" 2>/dev/null || true)
			[[ -n "${active}" ]] || active="unknown"
		else
			active="not-installed"
		fi
		printf '%-30s %-25s %-10s %s\n' "${dir}" "${name}" "${active}" "${work}"
	done < <(list_instance_dirs "${base}")
}

cmd_add() {
	require_root
	local base gh_url base_name labels token new_idx new_dir new_name

	base=$(detect_base)
	[[ -f "${base}/.runner" ]] || die "no ${base}/.runner — is ${base} a configured runner install?"
	gh_url=$(runner_field "${base}/.runner" gitHubUrl)
	base_name=$(runner_field "${base}/.runner" agentName)
	[[ -n "${gh_url}" && -n "${base_name}" ]] || die "could not read agentName/gitHubUrl from ${base}/.runner"

	labels="${LABELS}"
	if [[ -z "${labels}" ]]; then
		[[ -f "${base}/.runner-stack-labels" ]] || die "--labels is required (no ${base}/.runner-stack-labels yet)"
		labels=$(cat "${base}/.runner-stack-labels")
	fi

	token="${TOKEN:-${RUNNER_TOKEN:-}}"
	if [[ -z "${token}" ]]; then
		print_token_snippet add "${gh_url}"
		exit 2
	fi

	new_idx=$(next_index "${base}")
	new_dir="${base}-${new_idx}"
	new_name="${base_name}-${new_idx}"

	echo "Adding instance ${new_idx}: ${new_dir} (name=${new_name}, labels=${labels})"
	copy_instance "${base}" "${new_dir}"

	if [[ -n "${LABELS}" ]]; then
		if ((DRY_RUN)); then
			printf '+ printf %%s %q > %q\n' "${labels}" "${base}/.runner-stack-labels"
		else
			printf '%s' "${labels}" >"${base}/.runner-stack-labels"
		fi
	fi

	run_step "${new_dir}" env RUNNER_ALLOW_RUNASROOT=1 ./config.sh --unattended \
		--url "${gh_url}" --token "${token}" --name "${new_name}" --labels "${labels}" --replace
	run_step "${new_dir}" ./svc.sh install root
	run_step "${new_dir}" ./svc.sh start

	echo "Instance ${new_idx} ready: ${new_dir} (${new_name})"
}

cmd_remove() {
	require_root
	local base idx dir token

	base=$(detect_base)
	idx=$(highest_index "${base}")
	((idx > 1)) || die "refusing to remove the base instance (${base}) — it is the last remaining instance"
	dir="${base}-${idx}"

	token="${TOKEN:-${RUNNER_TOKEN:-}}"
	if [[ -z "${token}" ]]; then
		local gh_url
		gh_url=$(runner_field "${base}/.runner" gitHubUrl)
		print_token_snippet remove "${gh_url}"
		exit 2
	fi

	if [[ -f "${dir}/.service" ]]; then
		run_step "${dir}" ./svc.sh stop
		run_step "${dir}" ./svc.sh uninstall
	else
		echo "note: ${dir}/.service not found, skipping stop/uninstall"
	fi

	if [[ -f "${dir}/.runner" ]]; then
		run_step "${dir}" ./config.sh remove --token "${token}"
	else
		echo "note: ${dir}/.runner not found, skipping config.sh remove"
	fi

	if ((DRY_RUN)); then
		printf '+ rm -rf %q\n' "${dir}"
	else
		rm -rf "${dir}"
	fi
	echo "Removed instance ${idx}: ${dir}"
}

main() {
	local sub=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			usage
			exit 0
			;;
		--base)
			[[ $# -ge 2 ]] || die "--base requires a value"
			BASE_OVERRIDE="$2"
			shift 2
			;;
		--base=*) BASE_OVERRIDE="${1#*=}"; shift ;;
		--labels)
			[[ $# -ge 2 ]] || die "--labels requires a value"
			LABELS="$2"
			shift 2
			;;
		--labels=*) LABELS="${1#*=}"; shift ;;
		--token)
			[[ $# -ge 2 ]] || die "--token requires a value"
			TOKEN="$2"
			shift 2
			;;
		--token=*) TOKEN="${1#*=}"; shift ;;
		--dry-run)
			DRY_RUN=1
			shift
			;;
		status | add | remove)
			sub="$1"
			shift
			;;
		*) die "unknown argument: $1 (see --help)" ;;
		esac
	done
	if [[ -z "${sub}" ]]; then
		usage >&2
		exit 1
	fi
	case "${sub}" in
	status) cmd_status ;;
	add) cmd_add ;;
	remove) cmd_remove ;;
	esac
}

main "$@"

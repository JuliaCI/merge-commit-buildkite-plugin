#!/bin/bash
# Tests for hooks/post-checkout against a local origin that plays GitHub's role.
# `sleep` is replaced by a stub that records the delay and can update the origin's
# pull request refs, to simulate GitHub creating the merge ref asynchronously.

# The checks are single-quoted on purpose: `check` evaluates them.
# shellcheck disable=SC2016

set -Eeu -o pipefail

hook="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks/post-checkout"

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

failures=0

setup() {
    T="$(mktemp -d)"
    export T
    git init -q --bare -b main "${T}/origin.git"
    git init -q -b main "${T}/work"
    cd "${T}/work"
    git commit -q --allow-empty -m base
    git push -q "${T}/origin.git" main
    git checkout -q -b pr
    git commit -q --allow-empty -m v1
    v1="$(git rev-parse HEAD)"
    git commit -q --allow-empty -m v2
    v2="$(git rev-parse HEAD)"
    git push -q "${T}/origin.git" "${v1}:refs/pull/1/head" "${v2}:refs/heads/pr"
    git clone -q "${T}/origin.git" "${T}/checkout"
    git -C "${T}/checkout" checkout -q --detach "${v1}"

    mkdir "${T}/bin"
    cat > "${T}/bin/sleep" <<'EOF'
#!/bin/bash
echo "$1" >> "${T}/sleeps"
n="$(wc -l < "${T}/sleeps" | tr -d ' ')"
if [[ -f "${T}/on_sleep_${n}" ]]; then bash "${T}/on_sleep_${n}"; fi
EOF
    chmod +x "${T}/bin/sleep"
    : > "${T}/sleeps"
}

teardown() {
    cd /
    rm -rf "${T}"
}

# Push $1 to the pull request and check it out, like the agent does for a new build.
github_push() {
    git -C "${T}/work" push -q -f "${T}/origin.git" "$1:refs/pull/1/head"
    git -C "${T}/checkout" fetch -q origin
    git -C "${T}/checkout" checkout -q --detach "$1"
}

# Push a GitHub-style merge commit of $1 into main as refs/pull/1/merge.
github_merge() {
    git -C "${T}/work" checkout -q --detach main
    git -C "${T}/work" merge -q --no-ff --no-edit "$1"
    git -C "${T}/work" push -q -f "${T}/origin.git" HEAD:refs/pull/1/merge
}

# Write a script for the stub to run during the Nth sleep.
on_sleep() {
    printf '%s\n' "$2" > "${T}/on_sleep_$1"
}

run_hook() {
    status=0
    # shellcheck disable=SC2034 # read by the checks
    output="$(cd "${T}/checkout" && PATH="${T}/bin:${PATH}" BUILDKITE_PULL_REQUEST="$1" "${BASH}" "${hook}" 2>&1)" || status=$?
}

check() {
    if ! eval "$1"; then
        echo "  FAILED: $1"
        while IFS= read -r line; do echo "    | ${line}"; done <<< "${output-}"
        failures=$((failures + 1))
    fi
}

checked_out() { git -C "${T}/checkout" rev-parse -q --verify "${1:-HEAD}"; }
sleeps() { paste -sd ' ' - < "${T}/sleeps"; }

test_not_a_pull_request() {
    run_hook false
    check '[[ ${status} == 0 ]]'
    check '[[ $(checked_out) == "${v1}" ]]'
    check '[[ -z $(sleeps) ]]'
}

test_merge_ref_ready() {
    github_merge "${v1}"
    run_hook 1
    check '[[ ${status} == 0 ]]'
    check '[[ $(checked_out HEAD^2) == "${v1}" ]]'
    check '[[ -z $(sleeps) ]]'
}

test_merge_ref_appears_later() {
    on_sleep 2 "$(declare -f github_merge); github_merge ${v1}"
    run_hook 1
    check '[[ ${status} == 0 ]]'
    check '[[ $(checked_out HEAD^2) == "${v1}" ]]'
    check '[[ $(sleeps) == "1 2" ]]'
}

test_merge_ref_appears_during_last_wait() {
    on_sleep 6 "$(declare -f github_merge); github_merge ${v1}"
    run_hook 1
    check '[[ ${status} == 0 ]]'
    check '[[ $(checked_out HEAD^2) == "${v1}" ]]'
    check '[[ $(sleeps) == "1 2 4 8 15 15" ]]'
}

test_merge_ref_lags_behind_head() {
    github_merge "${v1}"
    github_push "${v2}"
    on_sleep 1 "$(declare -f github_merge); github_merge ${v2}"
    run_hook 1
    check '[[ ${status} == 0 ]]'
    check '[[ $(checked_out HEAD^2) == "${v2}" ]]'
    check '[[ $(sleeps) == "1" ]]'
}

test_merge_ref_never_appears() {
    run_hook 1
    check '[[ ${status} != 0 ]]'
    check '[[ $(checked_out) == "${v1}" ]]'
    check '[[ $(sleeps) == "1 2 4 8 15 15" ]]'
    check '[[ ${output} == *"refs/pull/1/merge does not exist"* ]]'
    check '[[ ${output} == *"closed or merged"* ]]'
    check '[[ ${output} == *"merge conflicts"* ]]'
}

test_merge_ref_never_catches_up() {
    github_merge "${v1}"
    github_push "${v2}"
    run_hook 1
    check '[[ ${status} != 0 ]]'
    check '[[ $(checked_out) == "${v2}" ]]'
    check '[[ $(sleeps) == "1 2 4 8 15 15" ]]'
    check '[[ ${output} == *"does not merge ${v2}"* ]]'
}

test_origin_unavailable_for_a_while() {
    github_merge "${v1}"
    mv "${T}/origin.git" "${T}/origin.git.away"
    on_sleep 2 'mv "${T}/origin.git.away" "${T}/origin.git"'
    run_hook 1
    check '[[ ${status} == 0 ]]'
    check '[[ $(checked_out HEAD^2) == "${v1}" ]]'
    check '[[ $(sleeps) == "1 2" ]]'
}

test_merge_ref_not_fetchable_for_a_while() {
    github_merge "${v1}"
    merge="$(git -C "${T}/work" rev-parse HEAD)"
    object="${T}/origin.git/objects/${merge:0:2}/${merge:2}"
    mv "${object}" "${T}/object.away"
    on_sleep 1 "mv '${T}/object.away' '${object}'"
    run_hook 1
    check '[[ ${status} == 0 ]]'
    check '[[ $(checked_out) == "${merge}" ]]'
    check '[[ $(sleeps) == "1" ]]'
    check '[[ ${output} == *"could not fetch refs/pull/1/merge"* ]]'
}

test_pull_request_head_moved() {
    github_merge "${v1}"
    git -C "${T}/work" push -q -f "${T}/origin.git" "${v2}:refs/pull/1/head"
    run_hook 1
    check '[[ ${status} == 0 ]]'
    check '[[ $(checked_out HEAD^2) == "${v1}" ]]'
    check '[[ -z $(sleeps) ]]'
}

test_pull_request_head_and_merge_moved() {
    git -C "${T}/work" push -q -f "${T}/origin.git" "${v2}:refs/pull/1/head"
    github_merge "${v2}"
    run_hook 1
    check '[[ ${status} != 0 ]]'
    check '[[ $(checked_out) == "${v1}" ]]'
    check '[[ -z $(sleeps) ]]'
    check '[[ ${output} == *"out of date"* ]]'
}

test_merge_commit_already_checked_out() {
    github_merge "${v1}"
    merge="$(git -C "${T}/work" rev-parse HEAD)"
    git -C "${T}/checkout" fetch -q origin refs/pull/1/merge
    git -C "${T}/checkout" checkout -q --detach "${merge}"
    run_hook 1
    check '[[ ${status} == 0 ]]'
    check '[[ $(checked_out) == "${merge}" ]]'
    check '[[ -z $(sleeps) ]]'
}

for t in $(declare -F | awk '$3 ~ /^test_/ { print $3 }'); do
    echo "${t}"
    setup
    "${t}"
    teardown
done

if (( failures > 0 )); then
    echo "${failures} check(s) failed"
    exit 1
fi
echo "All tests passed"

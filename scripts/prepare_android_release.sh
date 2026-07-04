#!/bin/bash

set -euo pipefail

force=false
while [[ $# -gt 0 ]]; do
	case "$1" in
		--force)
			force=true
			shift
			;;
		*)
			echo "unknown argument: $1" >&2
			exit 1
			;;
	esac
done

origin_remote="${ORIGIN_REMOTE:-origin}"
upstream_remote="${UPSTREAM_REMOTE:-upstream}"
origin_main_branch="${ORIGIN_MAIN_BRANCH:-main}"
overlay_branch="${OVERLAY_BRANCH:-overlay}"
upstream_branch="${UPSTREAM_BRANCH:-main}"
tmp_branch="ci/android-release"
version_file="version.properties"

write_output() {
	local key="$1"
	local value="$2"
	if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
		printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
	fi
	printf '%s=%s\n' "$key" "$value"
}

read_prop() {
	local ref="$1"
	local key="$2"
	git show "$ref:$version_file" | awk -F= -v key="$key" '$1 == key { print $2; exit }'
}

read_worktree_prop() {
	local key="$1"
	awk -F= -v key="$key" '$1 == key { print $2; exit }' "$version_file"
}

is_prerelease() {
	local version="$1"
	if [[ "$version" == *"-"* ]]; then
		printf true
	else
		printf false
	fi
}

git fetch "$origin_remote" "refs/heads/$origin_main_branch:refs/remotes/$origin_remote/$origin_main_branch" --prune
git fetch "$origin_remote" "refs/heads/$overlay_branch:refs/remotes/$origin_remote/$overlay_branch" --prune
git fetch "$upstream_remote" "refs/heads/$upstream_branch:refs/remotes/$upstream_remote/$upstream_branch" --prune
git fetch "$origin_remote" "refs/tags/*:refs/tags/*" --force --prune

if ! git config user.name >/dev/null; then
	git config user.name "${GIT_AUTHOR_NAME:-github-actions[bot]}"
fi
if ! git config user.email >/dev/null; then
	git config user.email "${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
fi

origin_main_ref="$origin_remote/$origin_main_branch"
origin_overlay_ref="$origin_remote/$overlay_branch"
upstream_ref="$upstream_remote/$upstream_branch"
current_main_sha="$(git rev-parse "$origin_main_ref")"
current_overlay_sha="$(git rev-parse "$origin_overlay_ref")"
upstream_sha="$(git rev-parse "$upstream_ref")"

current_version="$(read_prop "$origin_main_ref" VERSION_NAME)"
current_version_code="$(read_prop "$origin_main_ref" VERSION_CODE)"
current_go_version="$(read_prop "$origin_main_ref" GO_VERSION)"
upstream_version="$(read_prop "$upstream_ref" VERSION_NAME)"
upstream_version_code="$(read_prop "$upstream_ref" VERSION_CODE)"
upstream_go_version="$(read_prop "$upstream_ref" GO_VERSION)"
version_ceiling="$(awk -F= '$1 == "VERSION_NAME" { print $2; exit }' version-ceiling.properties)"
release_tag="v$upstream_version"

if ! python3 - "$upstream_version" "$version_ceiling" <<'PY'
import sys

def version(value):
    core = value.split("-", 1)[0]
    return tuple(int(part) for part in core.split("."))

raise SystemExit(0 if version(sys.argv[1]) <= version(sys.argv[2]) else 1)
PY
then
	echo "upstream version $upstream_version exceeds overlay ceiling $version_ceiling; skipping" >&2
	write_output upstream_version "$upstream_version"
	write_output version_ceiling "$version_ceiling"
	write_output should_release false
	write_output should_push false
	exit 0
fi

overlay_commit_count="$(git rev-list --count "$origin_main_ref..$origin_overlay_ref")"
upstream_changed=false
version_changed=false
release_exists=false
should_release=false
should_push=false

if [[ "$upstream_sha" != "$current_main_sha" ]]; then
	upstream_changed=true
	should_push=true
fi

if [[ "$upstream_version" != "$current_version" || "$upstream_version_code" != "$current_version_code" ]]; then
	version_changed=true
fi

if git rev-parse -q --verify "refs/tags/$release_tag" >/dev/null; then
	release_exists=true
fi

if [[ "$force" == true || "$release_exists" != true ]]; then
	should_release=true
fi

write_output current_main_sha "$current_main_sha"
write_output current_overlay_sha "$current_overlay_sha"
write_output upstream_sha "$upstream_sha"
write_output overlay_commit_count "$overlay_commit_count"
write_output current_version "$current_version"
write_output current_version_code "$current_version_code"
write_output current_go_version "$current_go_version"
write_output upstream_version "$upstream_version"
write_output upstream_version_code "$upstream_version_code"
write_output upstream_go_version "$upstream_go_version"
write_output new_version "$upstream_version"
write_output new_version_code "$upstream_version_code"
write_output new_go_version "$upstream_go_version"
write_output new_go_setup_version "${upstream_go_version#go}"
write_output release_tag "$release_tag"
write_output prerelease "$(is_prerelease "$upstream_version")"
write_output version_changed "$version_changed"
write_output upstream_changed "$upstream_changed"
write_output release_exists "$release_exists"
write_output should_release "$should_release"
write_output should_push "$should_push"

if [[ "$should_release" != "true" ]]; then
	exit 0
fi

if [[ "$upstream_changed" == true ]]; then
	git checkout -B "$tmp_branch" "$upstream_ref" >/dev/null
	while IFS= read -r overlay_commit; do
		[[ -n "$overlay_commit" ]] || continue
		if ! git cherry-pick --no-edit "$overlay_commit"; then
			git cherry-pick --abort >/dev/null 2>&1 || true
			echo "failed to cherry-pick overlay commit $overlay_commit" >&2
			exit 1
		fi
	done < <(git rev-list --reverse "$origin_main_ref..$origin_overlay_ref")
else
	git checkout -B "$tmp_branch" "$origin_overlay_ref" >/dev/null
fi

new_overlay_sha="$(git rev-parse HEAD)"
new_version="$(read_worktree_prop VERSION_NAME)"
new_version_code="$(read_worktree_prop VERSION_CODE)"
new_go_version="$(read_worktree_prop GO_VERSION)"
new_go_setup_version="${new_go_version#go}"
new_release_tag="v$new_version"

write_output release_branch "$tmp_branch"
write_output new_overlay_sha "$new_overlay_sha"
write_output new_version "$new_version"
write_output new_version_code "$new_version_code"
write_output new_go_version "$new_go_version"
write_output new_go_setup_version "$new_go_setup_version"
write_output release_tag "$new_release_tag"
write_output prerelease "$(is_prerelease "$new_version")"

#!/usr/bin/env bash

set -euo pipefail

android_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${RUNNER_TEMP:-$android_root/build}/lx-apk-build"

core_repo="${SING_BOX_REPO:-}"
core_url="${SING_BOX_REPO_URL:-https://github.com/vl-bbnn/sing-box.git}"
core_ref="${SING_BOX_REPO_REF:-lx/overlay}"
gradle_tasks="${ANDROID_GRADLE_TASKS:-:app:assembleOtherDebug :app:assembleOtherLegacyDebug}"

if [[ -n "$core_repo" ]]; then
	core_repo="$(cd "$core_repo" && pwd)"
	if ! git -C "$core_repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		echo "SING_BOX_REPO is not a git working tree: $core_repo" >&2
		exit 1
	fi
	echo "using local sing-box source $core_repo"
else
	core_repo="$build_root/sing-box"
	rm -rf "$core_repo"
	mkdir -p "$build_root"
	git clone --filter=blob:none "$core_url" "$core_repo"
	git -C "$core_repo" fetch --tags --force
	git -C "$core_repo" fetch origin "$core_ref" --depth=1
	git -C "$core_repo" checkout -q FETCH_HEAD
	echo "using sing-box source $core_url@$core_ref ($(git -C "$core_repo" rev-parse --short HEAD))"
fi

mkdir -p "$android_root/app/libs"

(
	cd "$core_repo"
	make lib_install
	export PATH="$PATH:$(go env GOPATH)/bin"
	make lib_android
	cp libbox.aar "$android_root/app/libs/libbox.aar"
	cp libbox-legacy.aar "$android_root/app/libs/libbox-legacy.aar"
)

(
	cd "$android_root"
	# shellcheck disable=SC2086
	./gradlew $gradle_tasks
	./gradlew --stop
)

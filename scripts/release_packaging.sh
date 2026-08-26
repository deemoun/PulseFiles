#!/usr/bin/env bash
# Copyright (c) 2026 Dmitry Yarygin
# SPDX-License-Identifier: GPL-3.0-or-later


# Shared release-bundle assembly helpers. Callers are expected to enable their
# preferred shell safety options before sourcing this file.

assemble_release_bundle() {
    local app_bundle="$1"
    local app_name="$2"
    local executable_path="$3"
    local info_plist_path="$4"
    local app_resources_dir="$5"
    local build_path="$6"
    local configuration="$7"
    local repository_root="$8"
    local contents_dir="${app_bundle}/Contents"
    local macos_dir="${contents_dir}/MacOS"
    local resources_dir="${contents_dir}/Resources"
    local resource_bundle_path

    # Assembly destinations are always new staging paths. Refuse an existing
    # directory so this helper can never turn into incremental packaging.
    if [[ -e "${app_bundle}" ]]; then
        echo "Release bundle staging path already exists: ${app_bundle}" >&2
        return 1
    fi

    mkdir -p "${macos_dir}" "${resources_dir}"
    cp "${executable_path}" "${macos_dir}/${app_name}"
    cp "${info_plist_path}" "${contents_dir}/Info.plist"
    if [[ -d "${app_resources_dir}" ]]; then
        cp -R "${app_resources_dir}/." "${resources_dir}/"
    fi
    cp "${repository_root}/LICENSE" "${resources_dir}/LICENSE"
    cp "${repository_root}/NOTICE" "${resources_dir}/NOTICE"

    for resource_bundle_path in \
        "${build_path}/${configuration}/${app_name}_${app_name}.bundle" \
        "${build_path}/${configuration}/${app_name}_${app_name}.resources"
    do
        if [[ -d "${resource_bundle_path}" ]]; then
            cp -R "${resource_bundle_path}" "${resources_dir}/"
        fi
    done
    chmod +x "${macos_dir}/${app_name}"
}

publish_release_bundle() {
    local staged_bundle="$1"
    local published_bundle="$2"

    # The completed staging bundle is moved into a vacant destination. Removing
    # the complete prior bundle first guarantees no path can survive a rebuild.
    rm -rf "${published_bundle}"
    mv "${staged_bundle}" "${published_bundle}"
}

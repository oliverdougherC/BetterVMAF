#!/bin/bash

verify_developer_id() {
    local team="${1:?Missing expected Developer ID team}"
    shift
    [[ "$team" =~ ^[A-Z0-9]{10}$ ]] || { echo "Invalid Apple Team ID" >&2; return 1; }
    # codesign treats a requirement argument without '=' as a filename.
    local requirement="=anchor apple generic and certificate leaf[subject.OU] = \"$team\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    codesign --verify --strict -R "$requirement" "$@"
}

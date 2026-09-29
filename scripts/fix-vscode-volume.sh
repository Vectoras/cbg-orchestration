#!/bin/sh
# Makes the shared `vscode` Docker volume writable by any user.
#
# The Dev Containers extension uses one `vscode` volume (not project-scoped)
# across every dev container on this machine to cache the VS Code Server and
# installed extensions. Docker seeds a brand-new empty volume with the
# ownership of whichever user's container first mounts it — since projects
# here use different base images/languages (Node, Go, ...) with different
# default users, that first-writer ownership doesn't generalize, and anyone
# other than that first user hits permission errors (extensions silently
# failing to install being the usual symptom).
#
# Run this whenever that happens, or any time after the `vscode` volume has
# been deleted and recreated (e.g. `docker volume rm vscode`) — a fresh
# volume reverts to the seeding user's restrictive default ownership. Safe to
# re-run any time; it doesn't require any dev container to be running.
#
# See orchestration/human/dev_containers.md for the fuller writeup.

set -eu

docker run --rm -v vscode:/vscode alpine chmod -R a+rwX /vscode

echo "vscode volume is now writable by any user."

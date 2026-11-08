#!/bin/sh
# Runs one command of the SDK's build in a container of one of the images below, each pinned by its
# digest, with the repository at /work:
#
#   scripts/docker.sh fetch|offline <image> <command> [<argument>...]
#
# fetch: the container reaches the network, and Docker pulls the image if this machine lacks it.
# offline: the container has no network, and Docker never pulls.
# Each container goes when its command ends (--rm), and takes 4 CPUs and 4 GB of memory at most.
#
# Docker Desktop: a run that finds it stopped starts it, and once its command ends quits it again,
# but only if no container runs then, another session's among them. A run that finds it running
# leaves it running.
#
# The C#, PHP and Ruby SDKs' repositories share this file, all but its two settings below.
set -eu
cd "$(dirname "$0")/.."

# This SDK's settings: its images, each name=image@digest, and the variables its tools are given,
# each NAME=value.
images='ruby=docker.io/library/ruby:3.4@sha256:3acb7705baee45c4815270dbedf953e95c34e25d5440babadf5ae451a706d012'
environment='BUNDLE_PATH=vendor/bundle'

usage='usage: scripts/docker.sh fetch|offline <image> <command> [<argument>...]'
case "${1:-}" in
  fetch) network=bridge pull=missing ;;
  offline) network=none pull=never ;;
  *)
    echo "$usage" >&2
    exit 2
    ;;
esac
image=''
for entry in $images; do
  case "$entry" in
    "${2:-}="*) image=${entry#*=} ;;
  esac
done
if [ -z "$image" ] || [ "$#" -lt 3 ]; then
  echo "$usage" >&2
  echo "The images: $images" >&2
  exit 2
fi
shift 2

started=no
finish() {
  status=$?
  if [ "$started" = yes ]; then
    if [ -n "$(docker ps --quiet)" ]; then
      echo "Docker Desktop stays running: this run started it, but a container runs now." >&2
    else
      osascript -e 'quit app "Docker"' >/dev/null
      echo "Docker Desktop quit: this run started it, and no container runs now." >&2
    fi
  fi
  exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if ! docker info >/dev/null 2>&1; then
  echo "Docker Desktop isn't running: this run starts it." >&2
  open -a Docker
  started=yes
  waited=0
  until docker info >/dev/null 2>&1; do
    if [ "$waited" -ge 180 ]; then
      echo "Docker Desktop didn't answer in 180 s." >&2
      exit 1
    fi
    sleep 3
    waited=$((waited + 3))
  done
fi

variables=''
for variable in $environment; do
  variables="$variables --env $variable"
done
# $variables is split into its words on purpose: --env, then one NAME=value, in turn.
# shellcheck disable=SC2086
docker run --rm --cpus 4 --memory 4g --network "$network" --pull "$pull" \
  --volume "$PWD:/work" --workdir /work $variables "$image" "$@"

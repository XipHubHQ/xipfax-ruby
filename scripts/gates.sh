#!/bin/sh
# The repository's gate, run before every pull request: the SDK as openapi.json generates it, its
# version as the settings name it, and the build, which reads every Ruby file of the SDK, its specs
# and its example, builds the gem as RubyGems would publish it, under the name and the version the
# settings give, and loads every file of the SDK by `require 'xipfax-sdk'`. The specs run once
# before each release, by scripts/test.sh, not here. Ruby runs in its image with no network, under
# Bundler, on what scripts/fetch.sh fetched: a gem vendor/bundle lacks stops the gate, named.
set -eu
cd "$(dirname "$0")/.."

sh scripts/generate.sh

# What the generator writes, by the list it wrote now and the one the commit holds, and
# api_version.rb: a generated file that differs from the commit, is new to it or is gone from it
# fails the gate.
gem=$(sed -n 's/^gemName: //p' openapi-generator.yaml)
generated=$({
  cat .openapi-generator/FILES
  git show HEAD:.openapi-generator/FILES 2>/dev/null || true
} | grep -E '^lib/.+\.rb$' | sort -u)
# $generated is split into its paths on purpose, one a line.
# shellcheck disable=SC2086
changed=$(git status --porcelain --untracked-files=all -- "lib/$gem/api_version.rb" .openapi-generator $generated)
if [ -n "$changed" ]; then
  echo "The SDK differs from what openapi.json generates: run scripts/generate.sh and commit it." >&2
  echo "$changed" >&2
  exit 1
fi

# The release the generator writes into the user agent, held to the one the settings name.
version=$(sed -n 's/^gemVersion: //p' openapi-generator.yaml)
agent=$(sed -n 's/^httpUserAgent: //p' openapi-generator.yaml)
if [ -z "$version" ] || [ "$agent" != "xipfax-ruby/$version" ]; then
  echo "openapi-generator.yaml's httpUserAgent, $agent, isn't xipfax-ruby/ and its gemVersion, $version: name the release in both." >&2
  exit 1
fi

sh scripts/docker.sh offline ruby bundle exec ruby scripts/build.rb
echo "Gates: GREEN"

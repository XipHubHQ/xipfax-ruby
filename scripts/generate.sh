#!/bin/sh
# Makes the SDK from openapi.json, the API's document: scripts/sdk-document.jq writes the document
# it is generated from, openapi-generator 7.17.0 generates the client from that with
# openapi-generator.yaml, and this script writes api_version.rb from the document's info.version and
# adds to the entry the generator wrote the lines that require it and the client. Nothing it writes
# is edited by hand. It fetches nothing.
set -eu
cd "$(dirname "$0")/.."

generator=$(openapi-generator version)
if [ "$generator" != "7.17.0" ]; then
  echo "scripts/generate.sh takes openapi-generator 7.17.0, and this machine has $generator." >&2
  exit 1
fi

if ! version=$(jq -er '.info.version | select(test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))' openapi.json); then
  echo "openapi.json's info.version is not a day, as 2026-11-03 is." >&2
  exit 1
fi

# The gem's name and the SDK's module, which openapi-generator.yaml names alone.
if ! gem=$(sed -n 's/^gemName: //p' openapi-generator.yaml | grep -E -x '[a-z][a-z0-9]*([_-][a-z0-9]+)*'); then
  echo "openapi-generator.yaml's gemName is not one gem's name, as xipfax-sdk is." >&2
  exit 1
fi
if ! module=$(sed -n 's/^moduleName: //p' openapi-generator.yaml | grep -E -x '[A-Z][A-Za-z0-9]*'); then
  echo "openapi-generator.yaml's moduleName is not one Ruby module's name, as XipFax is." >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
jq -f scripts/sdk-document.jq openapi.json > "$work/openapi.json"

# The Ruby files the last run wrote go first, so that one the document no longer makes doesn't stay,
# and api_version.rb, this script's.
if [ -f .openapi-generator/FILES ]; then
  grep -E '^lib/.+\.rb$' .openapi-generator/FILES | while IFS= read -r file; do
    rm -f "./$file"
  done
fi
rm -f "lib/$gem/api_version.rb"

openapi-generator generate -g ruby -i "$work/openapi.json" -o . -c openapi-generator.yaml

cat > "lib/$gem/api_version.rb" <<EOF
# frozen_string_literal: true

# Written by scripts/generate.sh from openapi.json's info.version. Do not edit.

module $module
  # The version of XipFax's API this SDK is generated from, the day the API's document names it by,
  # which every request names in its Xip-Version header.
  API_VERSION = '$version'
end
EOF

cat >> "lib/$gem.rb" <<EOF

# Added by scripts/generate.sh to the entry the generator wrote: the version of the API the SDK is
# generated from, and the client your API key makes.
require '$gem/api_version'
require '$gem/client'
EOF

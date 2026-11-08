#!/bin/sh
# Fetches what the SDK's build and specs need and this machine lacks: Ruby's image, by the digest
# scripts/docker.sh names, and the gems the Gemfile requires, from RubyGems.org, into vendor/bundle,
# at the versions Gemfile.lock holds. With no Gemfile.lock, Bundler takes the latest versions the
# Gemfile and the gemspec allow and writes Gemfile.lock, which the repository keeps. It runs no spec,
# so that the gate and scripts/test.sh run offline after it. Run it again whenever the Gemfile, the
# gemspec's requirements or Gemfile.lock change.
set -eu
cd "$(dirname "$0")/.."

sh scripts/docker.sh fetch ruby bundle install

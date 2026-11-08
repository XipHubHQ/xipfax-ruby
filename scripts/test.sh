#!/bin/sh
# The SDK's specs, run once before each release, as the TypeScript SDK's are: minitest runs every
# spec under test/ in Ruby's image, with no network, under Bundler, on what scripts/fetch.sh
# fetched, with Ruby's warnings on. The container holds none of the variables of the shell that runs
# this, so no credential in it reaches a spec, and test/test_helper.rb, loaded first, strips any
# variable shaped like one before a spec loads, which a spec asserts. No spec reaches XipFax: each is
# answered by a stand-in in its own process.
set -eu
cd "$(dirname "$0")/.."

sh scripts/docker.sh offline ruby bundle exec ruby -w -Ilib -Itest \
  -e 'require "test_helper"; Dir.glob("test/**/*_test.rb").sort.each { |spec| require File.expand_path(spec) }'

# frozen_string_literal: true

# What every spec loads first, as scripts/test.sh requires it before them: the environment stripped
# of every variable shaped like a credential, before anything else loads, so that no spec has one to
# send, which CredentialsTest asserts; then minitest, the SDK and what the specs share.
require_relative 'support/credentials'
XipFaxSpecs::Credentials.strip

require 'json'
require 'uri'
require 'minitest/autorun'
require 'xipfax-sdk'
require_relative 'support/request'
require_relative 'support/answers'
require_relative 'support/document'
require_relative 'support/stand_in'

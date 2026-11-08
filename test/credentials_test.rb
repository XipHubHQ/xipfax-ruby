# frozen_string_literal: true

require_relative 'test_helper'

# No credential reaches a spec: test/test_helper.rb strips each before any spec loads.
class CredentialsTest < Minitest::Test
  # The variables the strip is given, each with its value.
  GIVEN = {
    'XIPFAX_API_KEY' => 'stand-in',
    'XIPFAX_TO' => '+1 202 555 0143',
    'GITHUB_TOKEN' => 'stand-in',
    'PLAIN_SETTING' => 'kept'
  }.freeze

  def test_the_environment_holds_no_credential
    assert_equal [], XipFaxSpecs::Credentials.left, 'the specs run with these in their environment'
  end

  def test_strip_takes_a_key_a_token_and_the_xipfax_variables_and_keeps_the_rest
    GIVEN.each { |name, value| ENV[name] = value }

    assert_equal %w[GITHUB_TOKEN XIPFAX_API_KEY XIPFAX_TO], XipFaxSpecs::Credentials.strip
    %w[GITHUB_TOKEN XIPFAX_API_KEY XIPFAX_TO].each do |name|
      refute ENV.key?(name), "#{name} is still in the environment"
    end
    assert_equal 'kept', ENV.fetch('PLAIN_SETTING', nil), 'the strip took PLAIN_SETTING too'
  ensure
    GIVEN.each_key { |name| ENV.delete(name) }
  end
end

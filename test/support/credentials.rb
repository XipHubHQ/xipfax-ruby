# frozen_string_literal: true

module XipFaxSpecs
  # Keeps every credential out of the specs. test/test_helper.rb calls strip before any spec loads:
  # anything in the environment shaped like a credential, or named for XipFax, goes. The day a real
  # key sits in a developer's shell, a spec that could reach the API still has nothing to reach it
  # with, and the specs keep saying so.
  module Credentials
    # A variable that is a secret in itself, in any case, its \z the name's very end.
    SECRET = /(TOKEN|SECRET|PASSWORD|CREDENTIAL|AUTH|APIKEY|API_KEY|_KEY\z|_KEYS\z|COOKIE|PRIVATE)/i.freeze

    # The variables XipFax's own examples read, such as XIPFAX_API_KEY.
    XIPFAX = /\AXIPFAX_/i.freeze

    # Whether a spec's process has no business carrying the variable name.
    def self.shaped?(name)
      SECRET.match?(name) || XIPFAX.match?(name)
    end

    # The name of each such variable in the process's environment, sorted.
    def self.left
      ENV.keys.select { |name| shaped?(name) }.sort
    end

    # Removes each such variable from the process's environment, answering the names it removed,
    # sorted.
    def self.strip
      left.each { |name| ENV.delete(name) }
    end
  end
end

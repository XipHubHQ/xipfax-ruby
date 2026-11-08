# frozen_string_literal: true

# What RubyGems publishes: the gem xipfax-sdk at the version openapi-generator.yaml gives
# XipFax::VERSION, its author and contact, its license and links, the SDK's files, and the gems the
# generated client requires, at the versions it takes. scripts/build.rb holds its name and its
# version to the settings, and builds it.
require_relative 'lib/xipfax-sdk/version'

Gem::Specification.new do |spec|
  spec.name = 'xipfax-sdk'
  spec.version = XipFax::VERSION
  spec.summary = "XipFax's API for Ruby, generated from its OpenAPI document."
  spec.description = 'Send faxes from your code with XipFax: quote a fax, add your PDFs, send them ' \
                     'to a number or a government office, and follow each fax until it is delivered.'
  spec.authors = ['XipFax']
  spec.email = ['help@xipfax.com']
  spec.homepage = 'https://xipfax.com'
  spec.license = 'MIT'
  spec.metadata = {
    'documentation_uri' => 'https://developer.xipfax.com/docs/',
    'source_code_uri' => 'https://github.com/XipHubHQ/xipfax-ruby'
  }
  spec.required_ruby_version = '>= 2.7'
  spec.files = Dir['lib/**/*.rb'] + %w[LICENSE README.md]
  spec.require_paths = ['lib']

  spec.add_dependency 'faraday', '>= 1.0.1', '< 3.0'
  spec.add_dependency 'faraday-multipart', '~> 1.0'
  spec.add_dependency 'marcel', '~> 1.0'
end

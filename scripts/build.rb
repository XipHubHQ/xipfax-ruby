# frozen_string_literal: true

# The gate's build, which scripts/gates.sh runs in Ruby's image under Bundler: every Ruby file of the
# SDK, its specs, its example and its scripts read by this Ruby without a fault; the gem built from
# its gemspec as RubyGems would publish it, strictly, under the settings' gemName and gemVersion; and
# every file of the SDK loaded by requiring the gem's entry. Each fault is named, and any fails the
# build.

require 'open3'
require 'rbconfig'
require 'rubygems/package'
require 'tmpdir'
require 'yaml'

root = File.expand_path('..', __dir__)
faults = []

files = Dir.glob(%w[lib/**/*.rb test/**/*.rb examples/**/*.rb scripts/**/*.rb], base: root).sort
files.each do |file|
  read, status = Open3.capture2e(RbConfig.ruby, '-c', File.join(root, file))
  faults << read unless status.success?
end

settings = YAML.safe_load_file(File.join(root, 'openapi-generator.yaml'))
gem = settings.fetch('gemName')
version = settings.fetch('gemVersion').to_s
spec = Gem::Specification.load(File.join(root, "#{gem}.gemspec"))
if spec.nil?
  faults << "#{gem}.gemspec doesn't load."
else
  faults << "#{gem}.gemspec publishes #{spec.name}, not the settings' gemName, #{gem}." unless spec.name == gem
  unless spec.version.to_s == version
    faults << "#{gem}.gemspec publishes #{spec.version}, not the settings' gemVersion, #{version}."
  end
  Dir.mktmpdir do |dir|
    Dir.chdir(root) { Gem::Package.build(spec, false, true, File.join(dir, spec.file_name)) }
  rescue Gem::InvalidSpecificationException, Gem::Package::Error => e
    faults << "The gem doesn't build: #{e.message}"
  end
end

$LOAD_PATH.unshift(File.join(root, 'lib'))
require gem
loaded = $LOADED_FEATURES.map { |feature| File.expand_path(feature) }
sources = Dir.glob('lib/**/*.rb', base: root).sort
sources.each do |file|
  faults << "#{file} isn't loaded by require '#{gem}'." unless loaded.include?(File.join(root, file))
end

abort(faults.join("\n")) unless faults.empty?
puts "Read #{files.size} files, built #{spec.file_name} and loaded #{sources.size}."

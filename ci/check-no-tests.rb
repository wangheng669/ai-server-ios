#!/usr/bin/env ruby
# Static policy check only. Never execute the source being inspected.
require 'yaml'
require 'rexml/document'
require 'shellwords'

root = File.expand_path('..', __dir__)
errors = []
Dir.chdir(root) do
  project = YAML.load_file('project.yml')
  project.fetch('targets').each do |name, target|
    errors << "project.yml: test target #{name}" if target.fetch('type').include?('test')
  end
  Dir.glob('**/project.pbxproj').each do |path|
    if File.read(path).match?(/com\.apple\.product-type\.bundle\.(?:unit-test|ui-testing)/)
      errors << "#{path}: XCTest product type"
    end
  end
  Dir.glob('**/*.xcscheme').each do |path|
    scheme = REXML::Document.new(File.read(path))
    if REXML::XPath.first(scheme, '//TestAction | //TestableReference | //TestPlanReference | //BuildActionEntry[@buildForTesting="YES"]')
      errors << "#{path}: scheme enables testing"
    end
  end
  Dir.glob('**/*.{xctestplan,xctest}').each { |path| errors << "#{path}: test bundle or plan" }
  Dir.glob('AIClient*Tests').each { |path| errors << "#{path}: test sources" }

  # Check literal Xcode actions, including options before the action and shell
  # continuations. Ordinary shell `test -f/-d/...` checks are not Xcode actions.
  sources = Dir.glob('ci/*.{sh,py,rb}').reject { |path| path == 'ci/check-no-tests.rb' }
               .map { |path| [path, File.read(path)] }
  Dir.glob('.github/workflows/*.{yml,yaml}').each do |path|
    workflow = YAML.load_file(path)
    workflow.fetch('jobs').each_value do |job|
      job.fetch('steps', []).each do |step|
        sources << ["#{path}: #{step['name'] || 'run'}", step['run']] if step['run']
      end
    end
  end
  sources.each do |path, source|
    source.gsub(/\\\r?\n/, ' ').each_line do |line|
      next if line.lstrip.start_with?('#')
      line.split(/[;&|]/).each do |command|
        next unless command.match?(/\bxcodebuild\b/)
        # Ignore quoted messages and process-detection patterns; inspect literal
        # xcodebuild invocations without evaluating shell substitutions.
        next unless command.match?(/(?:\A|\s)(?:[\w\/.$"{}-]*\/)?xcodebuild\s/)
        tokens = Shellwords.shellsplit(command) rescue command.split
        index = tokens.index { |token| File.basename(token) == 'xcodebuild' }
        next unless index
        arguments = tokens.drop(index + 1)
        if arguments.first.to_s.include?('$')
          errors << "#{path}: dynamic Xcode action cannot be verified statically"
        end
        forbidden = arguments & %w[test test-without-building build-for-testing]
        errors << "#{path}: forbidden Xcode action #{forbidden.join(', ')}" unless forbidden.empty?
      end
    end
  end
end
abort errors.join("\n") unless errors.empty?
puts 'No-test policy passed: project, schemes, CI scripts and workflow commands inspected.'

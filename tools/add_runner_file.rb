# Adds Swift files under app/ios/Runner to the Runner target (idempotent).
# Usage: tools/xcodeproj-env.sh tools/add_runner_file.rb WalletSecrets.swift [More.swift ...]
require 'xcodeproj'

project_path = File.expand_path('../app/ios/Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' } or abort 'no Runner target'
group = project.main_group.find_subpath('Runner', false) or abort 'no Runner group'

ARGV.each do |name|
  if group.files.any? { |f| f.path == name }
    puts "already there: #{name}"
    next
  end
  ref = group.new_reference(name)
  target.source_build_phase.add_file_reference(ref)
  puts "added: #{name}"
end
project.save

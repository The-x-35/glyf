# Bundles the typing engine's data into the GlyfKeyboard extension:
#   app/dict/en.glyd             — base dictionary (tools/build_dictionary.py)
#   app/assets/vocab/packs.json  — vocabulary packs (shared with the Flutter app)
# Idempotent; run via tools/xcodeproj-env.sh after adding a resource.
require 'xcodeproj'

PROJECT_PATH = File.expand_path('../app/ios/Runner.xcodeproj', __dir__)
RESOURCES = {
  'en.glyd' => '../dict/en.glyd',
  'packs.json' => '../assets/vocab/packs.json',
}.freeze

project = Xcodeproj::Project.open(PROJECT_PATH)
kb = project.targets.find { |t| t.name == 'GlyfKeyboard' }
abort 'GlyfKeyboard target missing' unless kb
group = project.main_group['GlyfKeyboard']
data_group = group['TypingData'] || group.new_group('TypingData')

added = []
# Resources that were renamed or dropped leave stale references behind.
STALE = %w[en_US.glyd].freeze
data_group.files.select { |f| STALE.include?(f.display_name) }.each do |ref|
  kb.resources_build_phase.remove_file_reference(ref)
  ref.remove_from_project
  added << "removed #{ref.display_name}"
end
RESOURCES.each do |name, rel|
  ref = data_group.files.find { |f| f.display_name == name }
  unless ref
    ref = data_group.new_reference(File.expand_path(rel, File.dirname(PROJECT_PATH)))
    ref.source_tree = 'SOURCE_ROOT'
    ref.path = rel
    ref.name = name
  end
  unless kb.resources_build_phase.files_references.include?(ref)
    kb.resources_build_phase.add_file_reference(ref, true)
    added << name
  end
end
project.save
puts added.empty? ? 'nothing to add' : "bundled: #{added.join(', ')}"

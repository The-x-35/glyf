# Takes GlyfVoiceWidget out of Runner's build (no dependency, not embedded)
# while keeping the target and its files, so the app builds and signs without
# a profile for com.arpit.glyf.voicewidget. Arpit, 2026-11-04: "We'll do the
# widget later." tools/add_voice_widget_target.rb puts it back.
require 'xcodeproj'
project = Xcodeproj::Project.open(File.expand_path('../app/ios/Runner.xcodeproj', __dir__))
runner = project.targets.find { |t| t.name == 'Runner' }
widget = project.targets.find { |t| t.name == 'GlyfVoiceWidget' }
abort 'GlyfVoiceWidget: no target' unless widget
notes = []
runner.dependencies.select { |d| d.target == widget }.each { |d| d.remove_from_project; notes << 'dependency' }
runner.copy_files_build_phases.each do |phase|
  phase.files.select { |bf| bf.file_ref == widget.product_reference }.each { |bf| bf.remove_from_project; notes << 'embed' }
end
project.save
puts notes.empty? ? 'GlyfVoiceWidget: already detached' : "GlyfVoiceWidget: removed #{notes.join(', ')}"

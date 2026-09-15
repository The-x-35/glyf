# Xcode's build system reports "Cycle inside Runner" when the appex embed
# phase runs after Flutter's "Thin Binary" script (Thin Binary declares the
# built bundle's Info.plist as an input, so embedding afterwards loops the
# graph). Fix: embed extensions before Thin Binary. Idempotent.
require 'xcodeproj'

project = Xcodeproj::Project.open(File.expand_path('../app/ios/Runner.xcodeproj', __dir__))
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' unless runner

embed = runner.copy_files_build_phases.find { |p| p.dst_subfolder_spec == '13' }
abort 'embed extensions phase not found' unless embed

thin = runner.shell_script_build_phases.find { |p| (p.name || '') =~ /Thin Binary/i }
abort 'Thin Binary phase not found' unless thin

phases = runner.build_phases
embed_idx = phases.index(embed)
thin_idx = phases.index(thin)

if embed_idx > thin_idx
  phases.move(embed, thin_idx)
  project.save
  puts "moved 'Embed Foundation Extensions' from index #{embed_idx} to #{thin_idx} (before Thin Binary)"
else
  puts 'phase order already correct'
end

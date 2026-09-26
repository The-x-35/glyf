# Signs the app and the keyboard with Arpit's team, bundles each target's
# privacy manifest (App Store Connect refuses builds that use required-reason
# APIs without one) and ties the keyboard's version to the app's.
# Idempotent; run via tools/xcodeproj-env.sh.
require 'xcodeproj'

PROJECT_PATH = File.expand_path('../app/ios/Runner.xcodeproj', __dir__)
TEAM = 'YNABR226PF' # Arpit Singh Bhatia (Individual)
MANIFESTS = { 'Runner' => 'Runner', 'GlyfKeyboard' => 'GlyfKeyboard' }.freeze

project = Xcodeproj::Project.open(PROJECT_PATH)
done = []
MANIFESTS.each do |target_name, group_name|
  target = project.targets.find { |t| t.name == target_name }
  abort "#{target_name} target missing" unless target
  target.build_configurations.each do |config|
    next if config.build_settings['DEVELOPMENT_TEAM'] == TEAM
    config.build_settings['DEVELOPMENT_TEAM'] = TEAM
    done << "#{target_name}/#{config.name} team"
  end
  group = project.main_group[group_name]
  abort "#{group_name} group missing" unless group
  ref = group.files.find { |f| f.display_name == 'PrivacyInfo.xcprivacy' } ||
        group.new_reference('PrivacyInfo.xcprivacy')
  unless target.resources_build_phase.files_references.include?(ref)
    target.resources_build_phase.add_file_reference(ref, true)
    done << "#{target_name} PrivacyInfo.xcprivacy"
  end
end
# The keyboard's version and build follow the app's (pubspec.yaml), so an
# extension/app mismatch can't reach App Store Connect.
kb = project.targets.find { |t| t.name == 'GlyfKeyboard' }
kb_group = project.main_group['GlyfKeyboard']
version_ref = kb_group.files.find { |f| f.display_name == 'Version.xcconfig' } ||
              kb_group.new_reference('Version.xcconfig')
kb.build_configurations.each do |config|
  unless config.base_configuration_reference == version_ref
    config.base_configuration_reference = version_ref
    done << "GlyfKeyboard/#{config.name} Version.xcconfig"
  end
  { 'CURRENT_PROJECT_VERSION' => '$(FLUTTER_BUILD_NUMBER)', 'MARKETING_VERSION' => '$(FLUTTER_BUILD_NAME)' }.each do |key, value|
    next if config.build_settings[key] == value
    config.build_settings[key] = value
    done << "GlyfKeyboard/#{config.name} #{key}"
  end
end

project.save
puts done.empty? ? 'nothing to do' : done.join("\n")

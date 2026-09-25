# Wires the GlyfKeyboard extension target into app/ios/Runner.xcodeproj.
# Idempotent: safe to re-run; exits early if the target already exists.
#
# Run via CocoaPods' bundled Ruby environment (see tools/xcodeproj-env.sh):
#   GEM_HOME=/opt/homebrew/Cellar/cocoapods/<v>/libexec /opt/homebrew/opt/ruby/bin/ruby tools/add_keyboard_target.rb
#
# Why a script and not Xcode: this repo is built milestone-by-milestone by
# agents/CI; project mutations must be reproducible from a clean checkout.

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../app/ios/Runner.xcodeproj', __dir__)
GROUP_ID = 'group.com.arpit.glyf'
APP_BUNDLE_ID = 'com.arpit.glyf'
KB_BUNDLE_ID = 'com.arpit.glyf.keyboard'

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' unless runner

if project.targets.any? { |t| t.name == 'GlyfKeyboard' }
  puts 'GlyfKeyboard target already exists — nothing to do'
  exit 0
end

deployment = runner.build_configurations
                   .map { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] }
                   .compact.first
deployment ||= project.build_configurations
                      .map { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] }
                      .compact.first
deployment ||= '13.0'

kb = project.new_target(:app_extension, 'GlyfKeyboard', :ios, deployment, nil, :swift)

# Flutter projects carry a third "Profile" configuration; mirror any project
# configuration the new target is missing so every flutter build mode works.
project.build_configurations.map(&:name).each do |name|
  next if kb.build_configurations.any? { |c| c.name == name }
  base = kb.build_configurations.find { |c| c.name == 'Release' } || kb.build_configurations.first
  config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  config.name = name
  config.build_settings = base.build_settings.dup
  kb.build_configuration_list.build_configurations << config
end

# --- File references -------------------------------------------------------
kb_group = project.main_group.new_group('GlyfKeyboard', 'GlyfKeyboard')
bridge_group = kb_group.new_group('Bridge', 'Bridge')

vc_ref     = kb_group.new_reference('GlyfKeyboardViewController.swift')
mem_ref    = kb_group.new_reference('MemoryLogger.swift')
info_ref   = kb_group.new_reference('Info.plist')
ent_ref    = kb_group.new_reference('GlyfKeyboard.entitlements')
store_ref  = bridge_group.new_reference('AppGroupStore.swift')
opener_ref = bridge_group.new_reference('HostAppOpener.swift')
_ = info_ref
_ = ent_ref

[vc_ref, mem_ref, store_ref, opener_ref].each do |ref|
  kb.source_build_phase.add_file_reference(ref, true)
end

runner_group = project.main_group['Runner']
abort 'Runner group not found' unless runner_group
glyf_bridge_ref = runner_group.new_reference('GlyfBridge.swift')
runner_group.new_reference('Runner.entitlements')
runner.source_build_phase.add_file_reference(glyf_bridge_ref, true)
# AppGroupStore.swift is the single shared implementation — compiled into BOTH targets.
runner.source_build_phase.add_file_reference(store_ref, true)

# --- Keyboard target build settings ---------------------------------------
kb.build_configurations.each do |config|
  bs = config.build_settings
  bs['INFOPLIST_FILE'] = 'GlyfKeyboard/Info.plist'
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = KB_BUNDLE_ID
  bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bs['SWIFT_VERSION'] = '5.0'
  bs['CODE_SIGN_ENTITLEMENTS'] = 'GlyfKeyboard/GlyfKeyboard.entitlements'
  bs['CODE_SIGN_STYLE'] = 'Automatic'
  # Keyboard extensions must be extension-API-only; this also fails the build
  # if anyone tries to use UIApplication.shared in the keyboard (SPEC §1).
  bs['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  bs['TARGETED_DEVICE_FAMILY'] = '1,2'
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = deployment
  bs['CURRENT_PROJECT_VERSION'] = '1'
  bs['MARKETING_VERSION'] = '1.0.0'
  bs['SKIP_INSTALL'] = 'YES'
  bs['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
  bs['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks',
                                   '@executable_path/../../Frameworks']
  bs['SWIFT_OPTIMIZATION_LEVEL'] = config.name == 'Debug' ? '-Onone' : '-O'
  bs['DEBUG_INFORMATION_FORMAT'] = config.name == 'Debug' ? 'dwarf' : 'dwarf-with-dsym'
end

# --- Embed into Runner ------------------------------------------------------
runner.add_dependency(kb)
embed = runner.copy_files_build_phases.find { |p| p.dst_subfolder_spec == '13' }
unless embed
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.dst_subfolder_spec = '13'
end
build_file = embed.add_file_reference(kb.product_reference, true)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# --- Runner settings --------------------------------------------------------
runner.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = APP_BUNDLE_ID
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

# --- CI guard: keyboard must stay Flutter-free (SPEC §1.1) ------------------
unless runner.shell_script_build_phases.any? { |p| p.name == 'Glyf CI Guard' }
  phase = runner.new_shell_script_build_phase('Glyf CI Guard')
  phase.shell_script = 'bash "$SRCROOT/../../ci/check_keyboard_clean.sh"'
  phase.show_env_vars_in_log = '0'
  phase.always_out_of_date = '1'
end

project.save
puts "GlyfKeyboard target added (deployment #{deployment}); Runner bundle id → #{APP_BUNDLE_ID}"

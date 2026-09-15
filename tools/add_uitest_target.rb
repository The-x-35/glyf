# Adds the GlyfM0UITests UI-testing bundle to Runner.xcodeproj and registers
# it in the shared Runner scheme's Test action. Idempotent.
#
# Why UI tests: the milestone gates (SPEC §9/§10) need reproducible on-device
# interaction — enable the keyboard, type on it, fire Spike A — and XCUITest
# is the only Apple-supported touch-injection path available headlessly.
require 'xcodeproj'

PROJECT_PATH = File.expand_path('../app/ios/Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' unless runner

if project.targets.any? { |t| t.name == 'GlyfM0UITests' }
  puts 'GlyfM0UITests target already exists — nothing to do'
  exit 0
end

deployment = runner.build_configurations
                   .map { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] }
                   .compact.first || '15.0'

ui = project.new_target(:ui_test_bundle, 'GlyfM0UITests', :ios, deployment, nil, :swift)

project.build_configurations.map(&:name).each do |name|
  next if ui.build_configurations.any? { |c| c.name == name }
  base = ui.build_configurations.find { |c| c.name == 'Release' } || ui.build_configurations.first
  config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  config.name = name
  config.build_settings = base.build_settings.dup
  ui.build_configuration_list.build_configurations << config
end

group = project.main_group.new_group('GlyfM0UITests', 'GlyfM0UITests')
test_ref = group.new_reference('GlyfM0UITests.swift')
ui.source_build_phase.add_file_reference(test_ref, true)

ui.build_configurations.each do |config|
  bs = config.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = 'so.glyf.app.m0uitests'
  bs['GENERATE_INFOPLIST_FILE'] = 'YES'
  bs['SWIFT_VERSION'] = '5.0'
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = deployment
  bs['TEST_TARGET_NAME'] = 'Runner'
  bs['CODE_SIGN_STYLE'] = 'Automatic'
  bs['CURRENT_PROJECT_VERSION'] = '1'
  bs['MARKETING_VERSION'] = '1.0.0'
end

ui.add_dependency(runner)

scheme_dir = Xcodeproj::XCScheme.shared_data_dir(PROJECT_PATH)
scheme_path = File.join(scheme_dir, 'Runner.xcscheme')
abort "shared scheme not found at #{scheme_path}" unless File.exist?(scheme_path)
scheme = Xcodeproj::XCScheme.new(scheme_path)
testable = Xcodeproj::XCScheme::TestAction::TestableReference.new(ui)
scheme.test_action.add_testable(testable)
scheme.save!

project.save
puts 'GlyfM0UITests target added and registered in the Runner scheme'

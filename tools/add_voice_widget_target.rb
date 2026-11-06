# Wires the GlyfVoiceWidget extension (the Glyf Voice Control Center control
# and its Live Activity, docs/APPS.md 5.17) into app/ios/Runner.xcodeproj,
# embeds it in Runner, and compiles the shared intent and Live Activity
# files into both. Idempotent: re-running only adds what is missing.
#
#   tools/xcodeproj-env.sh tools/add_voice_widget_target.rb
require 'xcodeproj'

PROJECT_PATH = File.expand_path('../app/ios/Runner.xcodeproj', __dir__)
TARGET = 'GlyfVoiceWidget'
BUNDLE_ID = 'com.arpit.glyf.voicewidget'
TEAM = 'YNABR226PF'
DEPLOYMENT = '18.0' # ControlWidget is iOS 18; the app itself stays 17.0
SHARED = %w[Shared/VoiceIntents.swift Shared/VoiceActivityAttributes.swift
            Shared/GlyfTradeAttributes.swift Shared/TradeIntents.swift Shared/GlyfIntents.swift
            Shared/GlyfIntentParsing.swift Shared/GlyfWidgetData.swift Shared/GlyfMeetingAttributes.swift].freeze
WIDGET_ONLY = %w[GlyfVoiceWidget.swift GlyfWidgetStyle.swift GlyfTradeLiveActivity.swift GlyfHomeWidgets.swift
                 GlyfMeetingLiveActivity.swift].freeze
# Runner's own: the trade activity's host, the intents' server and Google
# calls, and the one AppShortcutsProvider.
RUNNER_ONLY = %w[TradeActivityHost.swift MeetingActivityHost.swift GlyfIntentAPI.swift GlyfShortcuts.swift].freeze
# Keyboard files the widget draws or fetches with: the mark, Jupiter prices.
FROM_KEYBOARD = %w[Design/GlyfMark.swift Engine/TokenLookup.swift].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |t| t.name == 'Runner' }
kb = project.targets.find { |t| t.name == 'GlyfKeyboard' }
abort 'Runner/GlyfKeyboard targets missing' unless runner && kb
notes = []

widget = project.targets.find { |t| t.name == TARGET }
unless widget
  widget = project.new_target(:app_extension, TARGET, :ios, DEPLOYMENT, nil, :swift)
  # Flutter's third configuration (Profile), like the keyboard has.
  project.build_configurations.map(&:name).each do |name|
    next if widget.build_configurations.any? { |c| c.name == name }
    base = widget.build_configurations.find { |c| c.name == 'Release' }
    config = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
    config.name = name
    config.build_settings = base.build_settings.dup
    widget.build_configuration_list.build_configurations << config
  end
  notes << 'target'
end

# The keyboard's Version.xcconfig: version and build from pubspec.yaml, so
# App Store Connect sees the same numbers as the app's.
version_xcconfig = kb.build_configurations.first.base_configuration_reference

widget.build_configurations.each do |config|
  bs = config.build_settings
  debug = config.name == 'Debug'
  config.base_configuration_reference = version_xcconfig if version_xcconfig
  bs['INFOPLIST_FILE'] = 'GlyfVoiceWidget/Info.plist'
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bs['SWIFT_VERSION'] = '5.0'
  bs['CODE_SIGN_ENTITLEMENTS'] = 'GlyfVoiceWidget/GlyfVoiceWidget.entitlements'
  bs['CODE_SIGN_STYLE'] = 'Automatic'
  bs['DEVELOPMENT_TEAM'] = TEAM
  bs['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  bs['TARGETED_DEVICE_FAMILY'] = '1,2'
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT
  bs['SDKROOT'] = 'iphoneos'
  bs['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  bs['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  bs['SKIP_INSTALL'] = 'YES'
  bs['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
  bs['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks',
                                   '@executable_path/../../Frameworks']
  # GLYF_WIDGET: the shared intents' perform() does nothing here (the app
  # runs them, VoiceIntents.swift).
  bs['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = debug ? '$(inherited) DEBUG GLYF_WIDGET' : '$(inherited) GLYF_WIDGET'
  bs['SWIFT_OPTIMIZATION_LEVEL'] = debug ? '-Onone' : '-O'
  bs['DEBUG_INFORMATION_FORMAT'] = debug ? 'dwarf' : 'dwarf-with-dsym'
  bs['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = nil
  bs['ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME'] = nil
end

# --- Files -----------------------------------------------------------------
group = project.main_group[TARGET] || project.main_group.new_group(TARGET, TARGET)
shared_group = group['Shared'] || group.new_group('Shared', 'Shared')
%w[Info.plist GlyfVoiceWidget.entitlements].each do |name|
  group.files.find { |f| f.path == name } || group.new_reference(name)
end

def ref_for(group, shared_group, rel)
  g = rel.start_with?('Shared/') ? shared_group : group
  name = File.basename(rel)
  g.files.find { |f| f.path == name } || g.new_reference(name)
end

(WIDGET_ONLY + SHARED).each do |rel|
  ref = ref_for(group, shared_group, rel)
  unless widget.source_build_phase.files_references.include?(ref)
    widget.source_build_phase.add_file_reference(ref, true)
    notes << "widget:#{rel}"
  end
  next unless SHARED.include?(rel)
  unless runner.source_build_phase.files_references.include?(ref)
    runner.source_build_phase.add_file_reference(ref, true)
    notes << "runner:#{rel}"
  end
end

# The unit tests, Runner's own files, and the keyboard's files the widget uses.
tests = project.targets.find { |t| t.name == 'RunnerTests' }
if tests
  # GlyfWidgetDataTests.swift (the shared files' pure parts, through
  # @testable import Runner) and GlyfWidgetSnapshots.swift (the widgets
  # drawn in every size) sit beside the other tests; the snapshots compile
  # the widget's views and style into the tests.
  tg = project.main_group['RunnerTests']
  %w[GlyfWidgetDataTests.swift GlyfWidgetSnapshots.swift].each do |name|
    next unless tg && File.exist?(File.expand_path("../app/ios/RunnerTests/#{name}", __dir__))
    tref = tg.files.find { |f| f.path == name } || tg.new_reference(name)
    next if tests.source_build_phase.files_references.include?(tref)
    tests.source_build_phase.add_file_reference(tref, true)
    notes << "tests:#{name}"
  end
  %w[GlyfHomeWidgets.swift GlyfWidgetStyle.swift].each do |rel|
    ref = ref_for(group, shared_group, rel)
    next if tests.source_build_phase.files_references.include?(ref)
    tests.source_build_phase.add_file_reference(ref, true)
    notes << "tests:#{rel}"
  end
end
rgroup = project.main_group['Runner']
RUNNER_ONLY.each do |name|
  ref = rgroup.files.find { |f| f.path == name } || rgroup.new_reference(name)
  next if runner.source_build_phase.files_references.include?(ref)
  runner.source_build_phase.add_file_reference(ref, true)
  notes << "runner:#{name}"
end
FROM_KEYBOARD.each do |rel|
  ref = kb.source_build_phase.files_references.find { |f| f.real_path.to_s.end_with?("GlyfKeyboard/#{rel}") }
  abort "GlyfKeyboard/#{rel} missing from the keyboard" unless ref
  next if widget.source_build_phase.files_references.include?(ref)
  widget.source_build_phase.add_file_reference(ref, true)
  notes << "widget:#{rel}"
end

# --- Embed in Runner ---------------------------------------------------------
runner.add_dependency(widget) unless runner.dependencies.any? { |d| d.target == widget }
embed = runner.copy_files_build_phases.find { |p| p.dst_subfolder_spec == '13' }
abort 'Embed Foundation Extensions phase missing (run add_keyboard_target.rb first)' unless embed
unless embed.files_references.include?(widget.product_reference)
  bf = embed.add_file_reference(widget.product_reference, true)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  notes << 'embed'
end

project.save
puts notes.empty? ? 'GlyfVoiceWidget: nothing to do' : "GlyfVoiceWidget: added #{notes.join(', ')}"

# Syncs app/ios/GlyfKeyboard/**/*.swift into the GlyfKeyboard target and
# keeps the shared/pure-logic files compiled into RunnerTests for unit
# testing. Idempotent; run after adding any Swift file.
require 'xcodeproj'

PROJECT_PATH = File.expand_path('../app/ios/Runner.xcodeproj', __dir__)
KB_DIR = File.expand_path('../app/ios/GlyfKeyboard', __dir__)

# Files whose logic is pure enough to unit-test from RunnerTests (host-app bundle).
TEST_SHARED = %w[
  Engine/SecretScanner.swift
  Engine/ClipboardStore.swift
  Engine/Autocorrect.swift
  Engine/SettingsStore.swift
  Engine/VaultStore.swift
  Engine/ToneProfile.swift
  Engine/NotesStore.swift
  Layout/KeyboardLayout.swift
  Design/GlassTokens.swift
  Design/KeyboardTheme.swift
  Design/KeyboardThemes.swift
  Design/KeyFaces.swift
  Design/GlyfMark.swift
  Design/ChainLogo.swift
  Design/EmojiData.swift
  Engine/Games.swift
  Engine/SpaceGesture.swift
  Engine/Smart.swift
  Engine/StripPolicy.swift
  Engine/TradeIntent.swift
  Engine/TradeEdit.swift
  Engine/TradeRecurring.swift
  Engine/AIAction.swift
  Engine/SponsorMenu.swift
  Engine/EmojiWords.swift
  Engine/PhraseMemory.swift
  Engine/WeatherStore.swift
  Engine/CalendarText.swift
  Engine/EventParse.swift
  Engine/GoogleEvent.swift
  Engine/TempMail.swift
  Engine/NotoStickers.swift
  Engine/NotoCatalogue.generated.swift
  Engine/TokenLookup.swift
  Engine/CalBooking.swift
  Engine/Typing/TypingText.swift
  Engine/Typing/GlydTrie.swift
  Engine/Typing/Decoder.swift
  Engine/Typing/PersonalLexicon.swift
  Engine/Typing/TypingEngine.swift
  Engine/Typing/GlideDecoder.swift
  Engine/Typing/GlideTyping.swift
  Bridge/AppGroupStore.swift
  Bridge/IntentStore.swift
  Bridge/VoiceLink.swift
  Bridge/Contracts.generated.swift
].freeze

# Shared implementations compiled into the Runner APP as well (§4 bridge).
RUNNER_SHARED = %w[
  Bridge/AppGroupStore.swift
  Bridge/GoogleAccess.swift
  Bridge/IntentStore.swift
  Bridge/VoiceLink.swift
  Surfaces/VoiceRibbon.swift
  Engine/SecretScanner.swift
  Engine/VaultStore.swift
  Engine/SettingsStore.swift
  Engine/ToneProfile.swift
  Engine/NotesStore.swift
  Bridge/Contracts.generated.swift
].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)
kb = project.targets.find { |t| t.name == 'GlyfKeyboard' }
tests = project.targets.find { |t| t.name == 'RunnerTests' }
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'targets missing' unless kb && tests && runner

kb_group = project.main_group['GlyfKeyboard']
abort 'GlyfKeyboard group missing' unless kb_group

def ensure_group(parent, name)
  parent[name] || parent.new_group(name, name)
end

added = []
Dir.glob(File.join(KB_DIR, '**/*.swift')).sort.each do |abs|
  rel = abs.sub("#{KB_DIR}/", '')
  parts = rel.split('/')
  group = kb_group
  parts[0..-2].each { |dir| group = ensure_group(group, dir) }
  ref = group.files.find { |f| f.path == parts.last }
  ref ||= group.new_reference(parts.last)
  unless kb.source_build_phase.files_references.include?(ref)
    kb.source_build_phase.add_file_reference(ref, true)
    added << "kb:#{rel}"
  end
  if TEST_SHARED.include?(rel) && !tests.source_build_phase.files_references.include?(ref)
    tests.source_build_phase.add_file_reference(ref, true)
    added << "tests:#{rel}"
  end
  if RUNNER_SHARED.include?(rel) &&
     !runner.source_build_phase.files_references.include?(ref)
    runner.source_build_phase.add_file_reference(ref, true)
    added << "runner:#{rel}"
  end
end

# Brand artwork travels in the appex's own bundle — an extension cannot read
# the host app's asset catalogue, so the keyboard needs its own copy of the
# mark. These are resources, not sources, so they go on the copy phase. So do
# the keyboard themes' fonts with their licences (Fonts/) and their key
# sounds (Sounds/) and their key textures (Textures/): docs/THEMES.md §4.
Dir.glob(File.join(KB_DIR, '**/*.{png,ttf,caf}')).concat(Dir.glob(File.join(KB_DIR, 'Fonts/*.txt'))).sort.each do |abs|
  rel = abs.sub("#{KB_DIR}/", '')
  parts = rel.split('/')
  group = kb_group
  parts[0..-2].each { |dir| group = ensure_group(group, dir) }
  ref = group.files.find { |f| f.path == parts.last }
  ref ||= group.new_reference(parts.last)
  next if kb.resources_build_phase.files_references.include?(ref)

  kb.resources_build_phase.add_file_reference(ref, true)
  added << "kb-res:#{rel}"
end

# ...and drop the ones that are gone. A resource reference outliving its file
# fails the build outright ("Build input file cannot be found"), so deleting
# artwork has to be as easy as adding it.
kb.resources_build_phase.files.dup.each do |bf|
  path = bf.file_ref&.real_path.to_s
  next unless path.start_with?("#{KB_DIR}/")
  next if File.exist?(path)

  added << "kb-res-gone:#{path.sub("#{KB_DIR}/", '')}"
  bf.file_ref.remove_from_project
end

# New Swift files under app/ios/Runner/ go into the Runner target.
runner_group = project.main_group['Runner']
Dir.glob(File.expand_path('../app/ios/Runner/*.swift', __dir__)).sort.each do |abs|
  name = File.basename(abs)
  ref = runner_group.files.find { |f| f.path == name } || runner_group.new_reference(name)
  unless runner.source_build_phase.files_references.include?(ref)
    runner.source_build_phase.add_file_reference(ref, true)
    added << "runner:#{name}"
  end
end

# Test files live under RunnerTests/.
tests_group = project.main_group['RunnerTests']
Dir.glob(File.expand_path('../app/ios/RunnerTests/*.swift', __dir__)).sort.each do |abs|
  name = File.basename(abs)
  ref = tests_group.files.find { |f| f.path == name } || tests_group.new_reference(name)
  unless tests.source_build_phase.files_references.include?(ref)
    tests.source_build_phase.add_file_reference(ref, true)
    added << "tests:#{name}"
  end
end

project.save
puts added.empty? ? 'nothing to sync' : "synced: #{added.join(', ')}"

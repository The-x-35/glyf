#!/usr/bin/env ruby
# One source of truth for versions: pubspec.yaml. Every target's
# CURRENT_PROJECT_VERSION / MARKETING_VERSION become Flutter's
# $(FLUTTER_BUILD_NUMBER) / $(FLUTTER_BUILD_NAME), and the keyboard and
# test targets get Generated.xcconfig as their base configuration so those
# variables resolve there too (only Runner had it). Without this the appex
# shipped as build 7 whatever pubspec said.
require "xcodeproj"

project = Xcodeproj::Project.open(File.expand_path("../app/ios/Runner.xcodeproj", __dir__))
generated = project.files.find { |f| f.path.to_s.end_with?("Generated.xcconfig") }
abort "Generated.xcconfig not in project" unless generated

project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings["CURRENT_PROJECT_VERSION"] = "$(FLUTTER_BUILD_NUMBER)"
    config.build_settings["MARKETING_VERSION"] = "$(FLUTTER_BUILD_NAME)"
    if target.name != "Runner" && config.base_configuration_reference.nil?
      config.base_configuration_reference = generated
    end
    puts "#{target.name} #{config.name}: versions from pubspec#{config.base_configuration_reference ? '' : ' (no base config)'}"
  end
end
project.save

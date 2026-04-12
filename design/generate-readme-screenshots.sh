#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$repo_root/docs/images"
result_root="$(mktemp -d /tmp/octowatch-readme-result.XXXXXX)"
result_bundle="$result_root/ReadmeScreenshots.xcresult"
attachments_dir="$(mktemp -d /tmp/octowatch-readme-attachments.XXXXXX)"

cleanup() {
  rm -rf "$result_root" "$attachments_dir"
}

trap cleanup EXIT

mkdir -p "$output_dir"
rm -f "$output_dir/readme-main-window.png" "$output_dir/readme-onboarding.png"

xcodebuild \
  -project "$repo_root/Octowatch.xcodeproj" \
  -scheme OctowatchUI \
  -configuration Debug \
  -destination 'platform=macOS' \
  -resultBundlePath "$result_bundle" \
  -only-testing:OctowatchUITests/ReadmeScreenshotUITests/testCaptureReadmeMainWindow \
  -only-testing:OctowatchUITests/ReadmeScreenshotUITests/testCaptureReadmeOnboardingWindow \
  test

xcrun xcresulttool export attachments \
  --path "$result_bundle" \
  --output-path "$attachments_dir" \
  >/dev/null

ruby - "$attachments_dir/manifest.json" "$attachments_dir" "$output_dir" <<'RUBY'
require "fileutils"
require "json"

manifest_path, attachments_dir, output_dir = ARGV
manifest = JSON.parse(File.read(manifest_path))

targets = {
  "readme-main-window" => File.join(output_dir, "readme-main-window.png"),
  "readme-onboarding" => File.join(output_dir, "readme-onboarding.png")
}

manifest.each do |test_entry|
  Array(test_entry["attachments"]).each do |attachment|
    suggested_name = attachment.fetch("suggestedHumanReadableName", "")

    targets.each do |prefix, output_path|
      next unless suggested_name.start_with?("#{prefix}_") || suggested_name == "#{prefix}.png"

      exported_name = attachment.fetch("exportedFileName")
      FileUtils.cp(
        File.join(attachments_dir, exported_name),
        output_path
      )
    end
  end
end

missing = targets.values.reject { |path| File.exist?(path) }
abort("Missing README screenshots: #{missing.join(', ')}") unless missing.empty?
RUBY

ls -lh "$output_dir"/readme-*.png

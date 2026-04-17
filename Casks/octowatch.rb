cask "octowatch" do
  version :latest
  sha256 :no_check

  url "https://github.com/fiam/octowatch/releases/latest/download/Octowatch.dmg",
      verified: "github.com/fiam/octowatch/"
  name "Octowatch"
  desc "Native macOS triage inbox for GitHub work"
  homepage "https://octowatch.app"

  auto_updates true

  app "Octowatch.app"

  zap trash: [
    "~/Library/Application Support/Octowatch",
    "~/Library/Caches/app.octowatch.macos",
    "~/Library/HTTPStorages/app.octowatch.macos",
    "~/Library/Preferences/app.octowatch.macos.plist",
    "~/Library/Saved Application State/app.octowatch.macos.savedState"
  ]
end

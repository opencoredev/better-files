cask "better-files" do
  version :latest
  sha256 :no_check

  url "https://github.com/opencoredev/better-files/releases/latest/download/better-files-macos-universal.dmg"
  name "better-files"
  desc "Experimental native file manager"
  homepage "https://github.com/opencoredev/better-files"

  depends_on macos: :sonoma

  app "better-files.app"

  uninstall quit: "dev.leo.better-files"

  zap trash: [
    "~/Library/Application Support/better-files",
    "~/Library/Caches/dev.leo.better-files",
    "~/Library/Preferences/dev.leo.better-files.plist",
    "~/Library/Saved Application State/dev.leo.better-files.savedState",
  ]

  caveats <<~EOS
    better-files is experimental and is not currently Apple Developer ID signed or notarized.

    If macOS blocks launch, remove quarantine after installing:
      xattr -dr com.apple.quarantine /Applications/better-files.app
      open /Applications/better-files.app
  EOS
end

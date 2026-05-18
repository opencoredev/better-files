# better-files

better-files is an experimental native macOS file manager built with SwiftUI. It is trying to feel closer to Windows File Explorer while still behaving like a real macOS app: top tabs, direct path entry, sidebar navigation, Finder-style file actions, file icons, multiple layouts, drag and drop, and fast folder switching.

## Read this first

This app is early beta software. It can browse, create, rename, move, copy, delete, trash, and permanently delete files. It is not guaranteed to be bug-free, it may behave differently from Finder, and it can affect real files on disk. Keep backups and do not use it as your only file manager yet.

Release builds are currently not signed or notarized by Apple. macOS may show a warning that the app is from an unidentified developer. That is expected for now.

## Install

### Homebrew

After the first GitHub release exists, install from this repo's tap:

```sh
brew install --cask opencoredev/better-files/better-files
```

If macOS blocks the app because it is not notarized, remove the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/better-files.app
open /Applications/better-files.app
```

### GitHub Releases

Download the latest DMG:

```sh
curl -L -o better-files-macos-universal.dmg \
  https://github.com/opencoredev/better-files/releases/latest/download/better-files-macos-universal.dmg
open better-files-macos-universal.dmg
```

Drag `better-files.app` into `/Applications`, then use the `xattr` command above if macOS blocks launch.

## Updates

better-files includes Sparkle for in-app updates. Release builds check:

```text
https://github.com/opencoredev/better-files/releases/latest/download/appcast.xml
```

The app shows a normal "Check for Updates..." menu item. Automatic checks are enabled by default, but automatic installation is not: users should see an update prompt and choose whether to install.

Updater signing uses Sparkle EdDSA keys. The appcast and update zip are signed by Sparkle, but the macOS app itself is still not Apple Developer ID signed or notarized yet.

## Release a Version

The release workflow runs when a `v*` tag is pushed. It builds the app, packages a zip for Sparkle, creates a DMG for humans, generates and signs `appcast.xml`, uploads checksums, and publishes a GitHub release.

Before releasing, add these GitHub repository secrets:

```text
SPARKLE_PUBLIC_ED_KEY
SPARKLE_PRIVATE_ED_KEY
```

Generate keys with Sparkle's tools:

```sh
curl -L -o /tmp/Sparkle-for-SPM.zip \
  https://github.com/sparkle-project/Sparkle/releases/download/2.9.2/Sparkle-for-Swift-Package-Manager.zip
rm -rf /tmp/Sparkle-for-SPM
unzip -q /tmp/Sparkle-for-SPM.zip -d /tmp/Sparkle-for-SPM
/tmp/Sparkle-for-SPM/bin/generate_keys
/tmp/Sparkle-for-SPM/bin/generate_keys -x /tmp/better-files-sparkle-private-key
```

Use the printed public key as `SPARKLE_PUBLIC_ED_KEY`. Use the contents of `/tmp/better-files-sparkle-private-key` as `SPARKLE_PRIVATE_ED_KEY`, then delete that local file after saving the secret.

Create a release:

```sh
git tag v0.1.0
git push origin v0.1.0
```

## Development

Open in Xcode:

```sh
open better-files.xcodeproj
```

Regenerate the Xcode project:

```sh
xcodegen generate
```

Run tests:

```sh
xcodebuild test \
  -scheme BetterFiles \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derived-test \
  CODE_SIGNING_ALLOWED=NO
```

The updater is disabled in local development unless a Sparkle public key is provided through `SPARKLE_PUBLIC_ED_KEY`.

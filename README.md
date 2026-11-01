<p align="center">
  <img src="docs/banner.svg" alt="Profile Picker" width="100%">
</p>

A native macOS menu bar app that sends incoming web links to the Chromium browser profile you choose. Pick a profile for each link, or set a default until you switch back.

macOS 13+ · Apple silicon and Intel · Swift and AppKit · MIT

## Browsers

Every installed browser in this table appears in one list. Its profiles are found in the folder shown, under `~/Library/Application Support/`.

| Browser | Folder |
| --- | --- |
| Google Chrome, Beta, Dev, Canary | `Google/Chrome`, `Google/Chrome Beta`, `Google/Chrome Dev`, `Google/Chrome Canary` |
| Chromium | `Chromium` |
| Brave, Beta, Nightly | `BraveSoftware/Brave-Browser`, `-Beta`, `-Nightly` |
| Microsoft Edge, Beta, Dev, Canary | `Microsoft Edge`, `Microsoft Edge Beta`, `Microsoft Edge Dev`, `Microsoft Edge Canary` |
| Vivaldi | `Vivaldi` |
| Arc, Dia | `Arc/User Data`, `Dia/User Data` |
| Comet, Helium | `Comet`, `net.imput.helium` |

To add a browser, add a line to `Browser.known` in `Sources/ProfileStore.swift`. It needs Chromium's profile layout (`Default` and `Profile N` folders, names in `Local State`) and must honor `--profile-directory`.

Google Chrome is the only browser launched for real so far. See [Current limits](#current-limits).

## Get started

Building requires Xcode Command Line Tools with Swift 6 and `swift-format`. There is no published download yet.

```sh
./check.sh
open "build/Profile Picker.app"
```

Copy the built app to **Applications** before enabling web links. Then click its menu bar icon:

1. Open the gear menu, choose **Use for web links…**, and accept the macOS confirmation.
2. If a browser appears under **Allow … profile access…**, click it and select the folder it opens.
3. Choose a default profile, or keep **Ask every time**.

To start the app at login, add it under **System Settings → General → Login Items → Open at Login**.

## Behavior

- Links come from apps that honor the macOS default browser. Links clicked inside a browser normally stay there, and some apps choose a browser themselves.
- Only HTTP and HTTPS links are accepted.
- Several links are handled in order. A failed launch keeps its link for retry. Closing the picker cancels its waiting links.
- A default profile persists across restarts until you switch back. If it is unavailable, links go to the picker and the default is kept.

## Privacy

The app reads each installed browser's `Local State` file for profile display names, and checks that profile folders and their `Preferences` files exist. It does not read the contents of `Preferences`, browsing history, cookies or saved passwords. It has no network client or analytics. The browser receives the URLs you open.

macOS preferences hold the selected profile and any security-scoped folder bookmarks you grant.

## Build, check and package

```sh
./check.sh    # format, shell syntax, plist, behavior tests, universal build, signature
./build.sh    # build/Profile Picker.app
./package.sh  # dist/Profile-Picker-<version>.dmg plus SHA-256 checksum
xcrun swift-format format --in-place Sources/*.swift Tests/*.swift
```

## Current limits

- Runtime checks ran on Apple silicon with macOS 27.2. Intel and older macOS versions are untested.
- Browsers other than Chrome are listed from commonly reported bundle identifiers and folders, and have not been launched by this app. A wrong entry shows no profiles. A browser that ignores `--profile-directory` opens the link in its last-used profile.
- The **Allow … profile access…** step is confirmed for Google Chrome only.
- Browsers missing from the table do not appear until a line is added.
- Opera is left out because it does not appear to use the `Default` and `Profile N` layout.
- Builds are ad hoc signed, not Developer ID signed or notarized, so another Mac may block a downloaded copy. Do not disable Gatekeeper to install it.

## Contributing

Describe the behavior you want to change and run `./check.sh` before submitting a pull request. In reports, use synthetic examples. Do not attach `Local State`, profile folders, access bookmarks or private URLs.

## Upgrading from Chrome Profile Picker

The bundle identifier is unchanged, so preferences and web-link handling carry over. Quit the old app and move it to the Trash before installing this one, so macOS does not keep two copies under one identifier.

## Uninstall

Choose another default browser in macOS settings, remove the Open at Login entry, quit the app from the gear menu, then move it to the Trash. App preferences remain unless removed separately.

## License

[MIT](LICENSE). Third-party artwork keeps its notices in [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt), which is bundled with the app. This project is independent of and not endorsed by Google or any other browser vendor.

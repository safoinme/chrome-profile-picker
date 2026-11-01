import Foundation

struct Browser: Equatable {
  let id: String
  let name: String
  let root: URL

  static let chromeID = "com.google.Chrome"

  /// Browsers using Chromium's profile layout: `Default` and `Profile N` folders,
  /// display names in `Local State`, selected with `--profile-directory`.
  static let known: [Browser] = {
    let support = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support")
    return [
      (chromeID, "Google Chrome", "Google/Chrome"),
      ("com.google.Chrome.beta", "Chrome Beta", "Google/Chrome Beta"),
      ("com.google.Chrome.dev", "Chrome Dev", "Google/Chrome Dev"),
      ("com.google.Chrome.canary", "Chrome Canary", "Google/Chrome Canary"),
      ("org.chromium.Chromium", "Chromium", "Chromium"),
      ("com.brave.Browser", "Brave", "BraveSoftware/Brave-Browser"),
      ("com.brave.Browser.beta", "Brave Beta", "BraveSoftware/Brave-Browser-Beta"),
      ("com.brave.Browser.nightly", "Brave Nightly", "BraveSoftware/Brave-Browser-Nightly"),
      ("com.microsoft.edgemac", "Microsoft Edge", "Microsoft Edge"),
      ("com.microsoft.edgemac.Beta", "Edge Beta", "Microsoft Edge Beta"),
      ("com.microsoft.edgemac.Dev", "Edge Dev", "Microsoft Edge Dev"),
      ("com.microsoft.edgemac.Canary", "Edge Canary", "Microsoft Edge Canary"),
      ("com.vivaldi.Vivaldi", "Vivaldi", "Vivaldi"),
      ("company.thebrowser.Browser", "Arc", "Arc/User Data"),
      ("company.thebrowser.dia", "Dia", "Dia/User Data"),
      ("ai.perplexity.comet", "Comet", "Comet"),
      ("net.imput.helium", "Helium", "net.imput.helium"),
    ].map { Browser(id: $0.0, name: $0.1, root: support.appendingPathComponent($0.2)) }
  }()
}

struct BrowserProfile: Equatable {
  let browser: Browser
  let directory: String
  let name: String

  var id: String { "\(browser.id)/\(directory)" }
}

struct ProfileDiscovery {
  private(set) var profiles: [BrowserProfile] = []
  private(set) var denied: [Browser] = []

  init(of browsers: [Browser] = []) {
    for browser in browsers {
      do {
        profiles += try Self.profiles(of: browser)
      } catch CocoaError.fileReadNoPermission {
        denied.append(browser)
      } catch {
        // A missing folder means the browser has no profiles to offer yet.
      }
    }
  }

  private static func profiles(of browser: Browser) throws -> [BrowserProfile] {
    let folders = try FileManager.default.contentsOfDirectory(
      at: browser.root, includingPropertiesForKeys: [.isDirectoryKey])
    let names = displayNames(in: browser.root.appendingPathComponent("Local State"))
    return folders.compactMap { folder in
      let directory = folder.lastPathComponent
      guard
        directory == "Default"
          || directory.range(of: #"^Profile [0-9]+$"#, options: .regularExpression) != nil,
        (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("Preferences").path)
      else { return nil }
      return BrowserProfile(
        browser: browser, directory: directory, name: names[directory] ?? directory)
    }.sorted { $0.directory.localizedStandardCompare($1.directory) == .orderedAscending }
  }

  private static func displayNames(in localState: URL) -> [String: String] {
    let metadata = (try? Data(contentsOf: localState))
      .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let cache =
      (metadata?["profile"] as? [String: Any])?["info_cache"] as? [String: [String: Any]] ?? [:]
    return cache.compactMapValues {
      guard let name = ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !name.isEmpty
      else { return nil }
      return name
    }
  }
}

enum WebLink {
  static func parse(_ text: String) -> URL? {
    guard let url = URL(string: text),
      let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host, !host.isEmpty
    else { return nil }
    return url
  }

  static func arguments(profile: BrowserProfile, url: URL) -> [String] {
    [
      "--profile-directory=\(profile.directory)",
      "--ignore-profile-directory-if-not-exists", url.absoluteString,
    ]
  }
}

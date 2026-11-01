import Foundation

struct LinkQueue {
  private(set) var links: [URL] = []
  private(set) var opening: URL?

  mutating func append(_ urls: [URL]) { links.append(contentsOf: urls) }

  mutating func beginOpening() -> URL? {
    guard opening == nil, let first = links.first else { return nil }
    opening = first
    return first
  }

  mutating func finishOpening(success: Bool) {
    guard let opening else { return }
    if success && links.first == opening { links.removeFirst() }
    self.opening = nil
  }

  mutating func skip() {
    guard opening == nil, !links.isEmpty else { return }
    links.removeFirst()
  }

  mutating func cancel() {
    guard opening == nil else { return }
    links.removeAll()
  }
}

struct ProfileSelection {
  let defaults: UserDefaults

  var directory: String? { defaults.string(forKey: "defaultProfileDirectory") }
  // Selections saved before multi-browser support have no browser key and mean Chrome.
  private var browserID: String {
    defaults.string(forKey: "defaultProfileBrowser") ?? Browser.chromeID
  }

  func choose(_ profile: BrowserProfile?) {
    defaults.set(profile?.directory, forKey: "defaultProfileDirectory")
    defaults.set(profile?.browser.id, forKey: "defaultProfileBrowser")
  }

  func profile(in profiles: [BrowserProfile]) -> BrowserProfile? {
    profiles.first { $0.directory == directory && $0.browser.id == browserID }
  }
}

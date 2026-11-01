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

  func choose(_ profile: ChromeProfile?) {
    if let profile {
      defaults.set(profile.directory, forKey: "defaultProfileDirectory")
    } else {
      defaults.removeObject(forKey: "defaultProfileDirectory")
    }
  }

  func profile(in profiles: [ChromeProfile]) -> ChromeProfile? {
    profiles.first { $0.directory == directory }
  }
}

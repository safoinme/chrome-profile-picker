import Foundation

struct ChromeProfile: Equatable {
  let directory: String
  let name: String
}

final class ProfileStore {
  let root: URL
  private var metadataStamp: MetadataStamp?
  private var names: [String: String] = [:]

  private struct MetadataStamp: Equatable {
    let modified: Date?
    let size: UInt64?
    let inode: UInt64?
  }

  init(root: URL) { self.root = root }

  private func profileNames(refresh: Bool) -> [String: String] {
    let file = root.appendingPathComponent("Local State")
    let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
    let stamp = MetadataStamp(
      modified: attributes?[.modificationDate] as? Date,
      size: attributes?[.size] as? UInt64, inode: attributes?[.systemFileNumber] as? UInt64)
    if !refresh, metadataStamp == stamp { return names }
    // Retain only display names; never retain the rest of Chrome's Local State.
    let metadata = (try? Data(contentsOf: file))
      .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let cache =
      (metadata?["profile"] as? [String: Any])?["info_cache"] as? [String: [String: Any]] ?? [:]
    names = cache.compactMapValues {
      guard let name = ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !name.isEmpty
      else { return nil }
      return name
    }
    metadataStamp = metadata == nil ? nil : stamp
    return names
  }

  func profiles(refresh: Bool = false) throws -> [ChromeProfile] {
    let folders = try FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.isDirectoryKey])
    let names = profileNames(refresh: refresh)
    return folders.compactMap { folder in
      let directory = folder.lastPathComponent
      guard
        directory == "Default"
          || directory.range(of: #"^Profile [0-9]+$"#, options: .regularExpression) != nil,
        (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("Preferences").path)
      else { return nil }
      return ChromeProfile(directory: directory, name: names[directory] ?? directory)
    }.sorted { $0.directory.localizedStandardCompare($1.directory) == .orderedAscending }
  }
}

enum ChromeLink {
  static func parse(_ text: String) -> URL? {
    guard let url = URL(string: text),
      let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host, !host.isEmpty
    else { return nil }
    return url
  }

  static func arguments(profile: ChromeProfile, url: URL) -> [String] {
    [
      "--profile-directory=\(profile.directory)",
      "--ignore-profile-directory-if-not-exists", url.absoluteString,
    ]
  }
}

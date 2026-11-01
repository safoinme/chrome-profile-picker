import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() { fatalError(message) }
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
for name in [
  "Default", "Profile 1", "Profile 5", "Guest Profile", "System Profile", "Profile broken",
  "Profile 9",
] {
  let path = root.appendingPathComponent(name)
  try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
  if name != "Profile 9" {
    try Data("{}".utf8).write(to: path.appendingPathComponent("Preferences"))
  }
}
let metadata =
  #"{"profile":{"info_cache":{"Default":{"name":"Personal"},"Profile 1":{"name":"Work"},"Profile 5":{"name":"  "},"Profile 8":{"name":"Deleted"}}}}"#
try Data(metadata.utf8).write(to: root.appendingPathComponent("Local State"))
let store = ProfileStore(root: root)
let profiles = try store.profiles()
expect(
  profiles.map(\.directory) == ["Default", "Profile 1", "Profile 5"],
  "Include only existing Chrome profiles; exclude stale metadata and guest/system directories")
expect(
  profiles.map(\.name) == ["Personal", "Work", "Profile 5"],
  "Use real names and fall back for blank names")
try Data("invalid metadata".utf8).write(to: root.appendingPathComponent("Local State"))
let fallback = try store.profiles()
expect(
  fallback.map(\.name) == ["Default", "Profile 1", "Profile 5"],
  "Corrupt metadata should preserve folder fallback")
for invalid in [
  "javascript:alert(1)", "file:///etc/passwd", "mailto:a@example.com", "https://", "--incognito",
  "relative/path",
] {
  expect(ChromeLink.parse(invalid) == nil, "Reject unsupported input: \(invalid)")
}
let url = ChromeLink.parse("https://example.com/path?q=a%20b&next=--incognito#fragment")!
let args = ChromeLink.arguments(profile: profiles[1], url: url)
expect(
  args == [
    "--profile-directory=Profile 1", "--ignore-profile-directory-if-not-exists", url.absoluteString,
  ], "Keep the complete URL and profile as separate arguments, bypass the default handler")
// Existing folders gain or lose eligibility without restarting the app.
try Data("{}".utf8).write(to: root.appendingPathComponent("Profile 9/Preferences"))
expect(
  try! store.profiles().contains { $0.directory == "Profile 9" },
  "Discover a newly initialized profile")
try FileManager.default.removeItem(at: root.appendingPathComponent("Profile 1/Preferences"))
expect(
  try! !store.profiles().contains { $0.directory == "Profile 1" }, "Never offer a removed profile")
// Chrome may replace Local State atomically, even when its size and date are unchanged.
let localState = root.appendingPathComponent("Local State")
let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
for name in ["First", "Other"] {
  let data = try JSONSerialization.data(withJSONObject: [
    "profile": ["info_cache": ["Default": ["name": name]]]
  ])
  try data.write(to: localState, options: .atomic)
  try FileManager.default.setAttributes(
    [.modificationDate: fixedDate], ofItemAtPath: localState.path)
  expect(
    try! store.profiles().first?.name == name, "Profile renames become visible on the next lookup")
}
try FileManager.default.removeItem(at: localState)
expect(try! store.profiles().first?.name == "Default", "Missing metadata clears old names")
try FileManager.default.removeItem(at: root)
do {
  _ = try store.profiles()
  fatalError("An unavailable Chrome folder must not serve stale profiles")
} catch {}
print(
  "TESTS OK: profile discovery, metadata fallback, URL filtering, exact Chrome launch arguments")

let a = URL(string: "https://example.com/a")!
let b = URL(string: "https://example.com/b")!
let c = URL(string: "https://example.com/c")!
var queue = LinkQueue()
queue.append([a, b])
expect(queue.beginOpening() == a, "First incoming URL starts first")
expect(queue.beginOpening() == nil, "Only one launch can own the pending URL")
queue.skip()
queue.cancel()
queue.append([c])
expect(queue.links == [a, b, c], "Arrival, cancel, and skip cannot discard an in-flight link")
queue.finishOpening(success: false)
expect(
  queue.opening == nil && queue.links == [a, b, c], "Launch failure retains every URL for retry")
expect(queue.beginOpening() == a, "Retry still opens the original first link")
queue.finishOpening(success: true)
expect(queue.links == [b, c], "Success removes only the dispatched URL")
queue.finishOpening(success: true)
expect(queue.links == [b, c], "A duplicate completion cannot remove a waiting URL")
queue.skip()
expect(queue.links == [c], "Skip affects only the current waiting URL")
queue.cancel()
expect(queue.links.isEmpty, "Explicit close discards waiting links")
let suite = "local.profile-picker.tests." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let selection = ProfileSelection(defaults: defaults)
let original = ChromeProfile(directory: "Profile 1", name: "Work")
expect(selection.directory == nil, "New installations ask every time")
selection.choose(original)
let restored = ProfileSelection(defaults: defaults)
let renamed = ChromeProfile(directory: "Profile 1", name: "Renamed Work")
expect(
  restored.profile(in: [renamed]) == renamed,
  "Saved defaults survive a new owner and profile renames")
expect(restored.profile(in: []) == nil, "Missing profiles never resolve to a different profile")
expect(
  restored.directory == "Profile 1",
  "A failed lookup alone does not erase the choice during a permission failure")
restored.choose(nil)
expect(selection.directory == nil, "Ask every time persists the reset")
print(
  "ROUTING TESTS OK: FIFO, concurrent arrivals, retry retention, guarded cancellation, persistent profile selection, and manual reset"
)

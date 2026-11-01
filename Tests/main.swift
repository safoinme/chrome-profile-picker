import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() { fatalError(message) }
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let chrome = Browser(id: Browser.chromeID, name: "Chrome", root: root.appendingPathComponent("c"))
let brave = Browser(id: "com.brave.Browser", name: "Brave", root: root.appendingPathComponent("b"))
let absent = Browser(
  id: "org.example.absent", name: "Absent", root: root.appendingPathComponent("x"))
defer {
  try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: brave.root.path)
  try? FileManager.default.removeItem(at: root)
}
func makeProfiles(_ browser: Browser, _ folders: [String]) throws {
  for name in folders {
    let path = browser.root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    if name != "Profile 9" {
      try Data("{}".utf8).write(to: path.appendingPathComponent("Preferences"))
    }
  }
}
try makeProfiles(
  chrome,
  [
    "Default", "Profile 1", "Profile 5", "Guest Profile", "System Profile", "Profile broken",
    "Profile 9",
  ])
try makeProfiles(brave, ["Default"])
let localState = chrome.root.appendingPathComponent("Local State")
let metadata =
  #"{"profile":{"info_cache":{"Default":{"name":"Personal"},"Profile 1":{"name":"Work"},"Profile 5":{"name":"  "},"Profile 8":{"name":"Deleted"}}}}"#
try Data(metadata.utf8).write(to: localState)
func chromeProfiles() -> [BrowserProfile] { ProfileDiscovery(of: [chrome]).profiles }
let profiles = chromeProfiles()
expect(
  profiles.map(\.directory) == ["Default", "Profile 1", "Profile 5"],
  "Include only existing profiles; exclude stale metadata and guest/system directories")
expect(
  profiles.map(\.name) == ["Personal", "Work", "Profile 5"],
  "Use real names and fall back for blank names")
let both = ProfileDiscovery(of: [chrome, brave, absent])
expect(
  both.profiles.map(\.id) == [
    "\(chrome.id)/Default", "\(chrome.id)/Profile 1", "\(chrome.id)/Profile 5",
    "\(brave.id)/Default",
  ], "Same-named folders stay distinct per browser; an unused browser adds nothing")
expect(both.denied.isEmpty, "A missing folder is not a permission problem")
try Data("invalid metadata".utf8).write(to: localState)
expect(
  chromeProfiles().map(\.name) == ["Default", "Profile 1", "Profile 5"],
  "Corrupt metadata should preserve folder fallback")
for invalid in [
  "javascript:alert(1)", "file:///etc/passwd", "mailto:a@example.com", "https://", "--incognito",
  "relative/path",
] {
  expect(WebLink.parse(invalid) == nil, "Reject unsupported input: \(invalid)")
}
let url = WebLink.parse("https://example.com/path?q=a%20b&next=--incognito#fragment")!
expect(
  WebLink.arguments(profile: profiles[1], url: url) == [
    "--profile-directory=Profile 1", "--ignore-profile-directory-if-not-exists", url.absoluteString,
  ], "Keep the complete URL and profile as separate arguments, bypass the default handler")
try Data("{}".utf8).write(to: chrome.root.appendingPathComponent("Profile 9/Preferences"))
expect(
  chromeProfiles().contains { $0.directory == "Profile 9" }, "Discover a newly initialized profile")
try FileManager.default.removeItem(at: chrome.root.appendingPathComponent("Profile 1/Preferences"))
expect(!chromeProfiles().contains { $0.directory == "Profile 1" }, "Never offer a removed profile")
try Data(#"{"profile":{"info_cache":{"Default":{"name":"Renamed"}}}}"#.utf8).write(to: localState)
expect(
  chromeProfiles().first?.name == "Renamed", "Profile renames become visible on the next lookup")

let suite = "local.profile-picker.tests." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let selection = ProfileSelection(defaults: defaults)
expect(selection.directory == nil, "New installations ask every time")
defaults.set("Default", forKey: "defaultProfileDirectory")
expect(
  selection.profile(in: both.profiles)?.browser == chrome,
  "A selection saved before multi-browser support means Chrome")
let braveDefault = both.profiles.last!
selection.choose(braveDefault)
expect(
  ProfileSelection(defaults: defaults).profile(in: both.profiles) == braveDefault,
  "A saved default survives restart and tells browsers with the same folder name apart")
try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: brave.root.path)
let denied = ProfileDiscovery(of: [chrome, brave])
expect(denied.denied == [brave], "An unreadable folder is reported against its browser")
expect(!denied.profiles.isEmpty, "One denied browser leaves the others usable")
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: brave.root.path)
try FileManager.default.removeItem(at: brave.root)
expect(
  selection.profile(in: ProfileDiscovery(of: [chrome, brave]).profiles) == nil
    && selection.directory == "Default",
  "An unavailable default is not offered and is kept until the user changes it")
print(
  "TESTS OK: multi-browser discovery, denied folders, metadata fallback, URL filtering, launch arguments, selection"
)

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
print("ROUTING TESTS OK: FIFO, concurrent arrivals, retry retention, guarded cancellation")

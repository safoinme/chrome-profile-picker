import AppKit

@MainActor
final class PickerDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private let store = ProfileStore(
    root: FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Google/Chrome"))
  private let selection = ProfileSelection(defaults: .standard)
  private var queue = LinkQueue()
  private var profiles: [ChromeProfile] = []
  private var window: NSWindow?
  private let popover = NSPopover()
  private var statusItem: NSStatusItem?
  private var testField: NSTextField?
  private var message: String?
  private var needsFolderAccess = false
  private var accessedFolder: URL?
  private var configuringDefaults = false
  private var automaticRoutingPaused = false
  private var started = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    if let bookmark = UserDefaults.standard.data(forKey: "chromeFolderBookmark") {
      var stale = false
      if let folder = try? URL(
        resolvingBookmarkData: bookmark, options: [.withSecurityScope],
        relativeTo: nil, bookmarkDataIsStale: &stale),
        folder.standardizedFileURL == store.root.standardizedFileURL,
        folder.startAccessingSecurityScopedResource()
      {
        accessedFolder = folder
      }
    }
    let menu = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "Quit Chrome Profile Picker", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    appItem.submenu = appMenu
    menu.addItem(appItem)
    let editItem = NSMenuItem()
    editItem.title = "Edit"
    let editMenu = NSMenu(title: "Edit")
    for (name, action, key) in [
      ("Cut", #selector(NSText.cut(_:)), "x"),
      ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"),
      ("Select All", #selector(NSText.selectAll(_:)), "a"),
    ] {
      editMenu.addItem(withTitle: name, action: action, keyEquivalent: key)
    }
    editItem.submenu = editMenu
    menu.addItem(editItem)
    NSApp.mainMenu = menu
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let image = PickerUI.image("user-0", size: 14).copy() as! NSImage
    image.isTemplate = true
    item.button?.image = image
    item.button?.imagePosition = .imageLeading
    item.button?.font = .systemFont(ofSize: 12, weight: .medium)
    item.button?.target = self
    item.button?.action = #selector(togglePopover)
    statusItem = item
    popover.behavior = .transient
    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    popover.appearance = NSAppearance(named: .aqua)
    started = true
    refreshProfiles()
    updateStatus()
    if !queue.links.isEmpty { routeNext() }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    let valid = urls.compactMap { ChromeLink.parse($0.absoluteString) }
    queue.append(valid)
    if valid.count != urls.count { message = "Only http and https web links are supported." }
    if started { routeNext() }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if started {
      if queue.links.isEmpty { showPopover() } else { showPicker() }
    }
    return true
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard queue.opening == nil else { return false }
    queue.cancel()
    message = nil
    return true
  }

  @discardableResult private func refreshProfiles(force: Bool = false) -> Bool {
    do {
      profiles = try store.profiles(refresh: force)
      needsFolderAccess = false
      if selection.directory != nil && selection.profile(in: profiles) == nil {
        selection.choose(nil)
        message = "Your default profile is no longer available. Choose a profile for this link."
      }
      return true
    } catch {
      profiles = []
      needsFolderAccess = true
      message = "Chrome profiles could not be read. Allow profile access to continue."
      return false
    }
  }

  private func updateStatus() {
    let selected = selection.profile(in: profiles)
    let title = selection.directory == nil ? "" : " " + (selected?.name ?? "Profile unavailable")
    statusItem?.button?.title = title
    let description =
      selection.directory == nil
      ? "Profile Picker: Ask every time"
      : "Profile Picker: \(selected?.name ?? "Saved profile unavailable") · until you switch back"
    statusItem?.button?.toolTip = description
    statusItem?.button?.setAccessibilityLabel(description)
  }

  private func routeNext() {
    guard started, queue.opening == nil else { return }
    guard !queue.links.isEmpty else {
      updateVisibleViews()
      return
    }
    guard refreshProfiles() else {
      updateStatus()
      showPicker()
      return
    }
    updateStatus()
    if let profile = selection.profile(in: profiles), !automaticRoutingPaused {
      open(profile)
    } else {
      showPicker()
    }
  }

  private func rows(width: CGFloat, choosingDefault: Bool) -> NSView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    let nameCounts = Dictionary(grouping: profiles, by: \.name).mapValues(\.count)
    for (index, profile) in profiles.enumerated() {
      let duplicate = nameCounts[profile.name, default: 0] > 1
      let name = duplicate ? "\(profile.name) (\(profile.directory))" : profile.name
      let button = ProfileButton(
        name: name, index: index, shortcut: !choosingDefault,
        selected: choosingDefault && selection.directory == profile.directory, target: self,
        action: choosingDefault ? #selector(chooseDefault(_:)) : #selector(chooseOnce(_:)))
      button.identifier = NSUserInterfaceItemIdentifier(profile.directory)
      button.toolTip = "\(profile.name) · \(profile.directory)"
      button.isEnabled = choosingDefault || (!queue.links.isEmpty && queue.opening == nil)
      stack.addArrangedSubview(button)
      button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    if profiles.isEmpty {
      stack.addArrangedSubview(
        PickerUI.text(
          "No Chrome profiles found. Open Chrome, then refresh profiles from Settings.", size: 12))
    }
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.documentView = stack
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      scroll.widthAnchor.constraint(equalToConstant: width),
      scroll.heightAnchor.constraint(
        equalToConstant: min(264, max(48, CGFloat(profiles.count) * 54 - 6))),
      stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
      stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
    ])
    return scroll
  }

  private func pickerView() -> (NSView, NSSize) {
    let (view, stack) = PickerUI.surface(width: 472, gap: 12)
    stack.addArrangedSubview(
      PickerUI.text(
        queue.links.isEmpty ? "Ready when you are." : "Where to?",
        size: 25, weight: .semibold, color: PickerUI.ink))
    if let url = queue.links.first {
      let strip = NSStackView()
      strip.spacing = 10
      strip.wantsLayer = true
      strip.layer?.backgroundColor = PickerUI.destination.cgColor
      strip.layer?.cornerRadius = 11
      strip.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
      strip.heightAnchor.constraint(equalToConstant: 42).isActive = true
      strip.addArrangedSubview(
        PickerUI.glyph(url.scheme?.lowercased() == "https" ? "lock" : "external", size: 14))
      let host = PickerUI.text(url.host ?? "Web link", size: 13, weight: .medium)
      host.maximumNumberOfLines = 1
      host.lineBreakMode = .byTruncatingMiddle
      host.setAccessibilityLabel(url.absoluteString)
      strip.addArrangedSubview(host)
      strip.addArrangedSubview(PickerUI.spacer())
      strip.addArrangedSubview(PickerUI.glyph("external", size: 14))
      strip.toolTip = url.absoluteString
      stack.addArrangedSubview(strip)
      if queue.links.count > 1 {
        stack.addArrangedSubview(PickerUI.text("\(queue.links.count) links waiting", size: 11))
      }
    } else {
      let field = NSTextField(string: testField?.stringValue ?? "")
      field.placeholderString = "Paste a web link"
      field.font = .systemFont(ofSize: 13)
      field.setAccessibilityLabel("Web link")
      testField = field
      stack.addArrangedSubview(field)
      stack.addArrangedSubview(
        PickerUI.action("Choose a profile", target: self, action: #selector(tryLink)))
    }
    stack.addArrangedSubview(rows(width: 432, choosingDefault: false))
    addMessages(to: stack)
    let footer = NSStackView()
    footer.alignment = .centerY
    footer.spacing = 8
    if !queue.links.isEmpty {
      let cancel = PickerUI.action(
        queue.links.count > 1 ? "Skip this link" : "Cancel", target: self,
        action: #selector(cancelLink))
      cancel.isBordered = false
      cancel.contentTintColor = PickerUI.secondary
      cancel.keyEquivalent = "\u{1b}"
      cancel.isEnabled = queue.opening == nil
      footer.addArrangedSubview(cancel)
      footer.addArrangedSubview(PickerUI.text("esc", size: 10, color: PickerUI.muted))
    } else {
      footer.addArrangedSubview(
        PickerUI.text(
          selection.directory == nil ? "Ask every time" : "A default profile is active", size: 11))
    }
    footer.addArrangedSubview(PickerUI.spacer())
    footer.addArrangedSubview(PickerUI.settings(target: self, action: #selector(showSettings(_:))))
    stack.addArrangedSubview(footer)
    return (view, PickerUI.fit(view, stack: stack, width: 472))
  }

  private func menuView() -> (NSView, NSSize) {
    let (view, stack) = PickerUI.surface(width: 352, gap: 16)
    let header = NSStackView()
    header.alignment = .centerY
    header.spacing = 12
    header.addArrangedSubview(
      PickerUI.text("Profile Picker", size: 15, weight: .semibold, color: PickerUI.ink))
    header.addArrangedSubview(PickerUI.spacer())
    header.addArrangedSubview(PickerUI.settings(target: self, action: #selector(showSettings(_:))))
    stack.addArrangedSubview(header)
    let ask = ProfileButton(
      name: "Ask every time", index: nil, shortcut: false,
      selected: selection.directory == nil, subtitle: "Choose a profile for each link",
      target: self, action: #selector(chooseAskEveryTime))
    stack.addArrangedSubview(ask)
    let choices = NSStackView()
    choices.orientation = .vertical
    choices.alignment = .leading
    choices.spacing = 6
    choices.addArrangedSubview(
      PickerUI.text("Use a default profile", size: 11, color: PickerUI.muted))
    choices.addArrangedSubview(rows(width: 312, choosingDefault: true))
    stack.addArrangedSubview(choices)
    let separator = NSView()
    separator.wantsLayer = true
    separator.layer?.backgroundColor = PickerUI.color(0xE3DDD3).cgColor
    separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
    stack.addArrangedSubview(separator)
    if let profile = selection.profile(in: profiles) {
      let mode = NSStackView()
      mode.orientation = .vertical
      mode.alignment = .leading
      mode.spacing = 6
      mode.addArrangedSubview(
        PickerUI.text(
          "Links open in \(profile.name)", size: 12, weight: .medium, color: PickerUI.sage))
      mode.addArrangedSubview(PickerUI.text("Until you switch back", size: 11))
      stack.addArrangedSubview(mode)
    } else {
      stack.addArrangedSubview(
        PickerUI.text("Pick a default when you want to stay focused.", size: 11))
    }
    addMessages(to: stack)
    return (view, PickerUI.fit(view, stack: stack, width: 352))
  }

  private func addMessages(to stack: NSStackView) {
    if needsFolderAccess {
      stack.addArrangedSubview(
        PickerUI.action(
          "Allow Chrome profile access…", target: self, action: #selector(allowFolderAccess)))
    }
    if let message { stack.addArrangedSubview(PickerUI.text(message, size: 12, color: .systemRed)) }
    if queue.opening != nil {
      stack.addArrangedSubview(PickerUI.text("Opening in Chrome…", size: 12))
    }
  }

  private struct ViewState: Equatable {
    let profiles: [ChromeProfile]
    let selected: String?
    let firstLink: URL?
    let linkCount: Int
    let opening: URL?
    let message: String?
    let needsFolderAccess: Bool
  }

  private var pickerState: ViewState?
  private var menuState: ViewState?
  private var viewState: ViewState {
    ViewState(
      profiles: profiles, selected: selection.directory, firstLink: queue.links.first,
      linkCount: queue.links.count, opening: queue.opening, message: message,
      needsFolderAccess: needsFolderAccess)
  }

  private func renderPicker() {
    guard pickerState != viewState else { return }
    let (view, size) = pickerView()
    window?.contentView = view
    window?.setContentSize(size)
    pickerState = viewState
  }

  private func renderMenu() {
    guard menuState != viewState else { return }
    let (view, size) = menuView()
    let controller = NSViewController()
    controller.view = view
    popover.contentViewController = controller
    popover.contentSize = size
    menuState = viewState
  }

  private func showPicker() {
    popover.performClose(nil)
    if window == nil {
      let created = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 472, height: 360),
        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
      created.title = "Chrome Profile Picker"
      created.titleVisibility = .hidden
      created.titlebarAppearsTransparent = true
      created.backgroundColor = PickerUI.surface
      created.appearance = NSAppearance(named: .aqua)
      created.isMovableByWindowBackground = true
      created.isReleasedWhenClosed = false
      created.delegate = self
      created.center()
      window = created
    }
    renderPicker()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func showPopover() {
    guard let button = statusItem?.button else { return }
    refreshProfiles()
    updateStatus()
    renderMenu()
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func updateVisibleViews() {
    updateStatus()
    if popover.isShown { renderMenu() }
    if window?.isVisible == true {
      if queue.links.isEmpty { window?.orderOut(nil) } else { renderPicker() }
    }
  }

  @objc private func togglePopover() {
    if popover.isShown { popover.performClose(nil) } else { showPopover() }
  }

  @objc private func showSettings(_ sender: NSButton) {
    let menu = NSMenu()
    let actions: [(String, Selector)] = [
      ("Open a link…", #selector(openLink)),
      ("Refresh profiles", #selector(refresh)),
      ("Use for web links…", #selector(setDefaultHandler)),
      ("Allow Chrome profile access…", #selector(allowFolderAccess)),
      ("Browser settings…", #selector(openSettings)),
    ]
    for (title, action) in actions {
      let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
      item.target = self
    }
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit Profile Picker", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 6), in: sender)
  }

  @objc private func openLink() {
    refreshProfiles()
    showPicker()
  }
  @objc private func refresh() {
    message = nil
    refreshProfiles(force: true)
    updateVisibleViews()
    routeNext()
  }

  @objc private func chooseDefault(_ sender: NSButton) {
    guard let directory = sender.identifier?.rawValue else { return }
    guard refreshProfiles(), let profile = profiles.first(where: { $0.directory == directory })
    else {
      message = "That profile is no longer available. Please choose again."
      updateVisibleViews()
      return
    }
    selection.choose(profile)
    automaticRoutingPaused = false
    message = nil
    updateVisibleViews()
    routeNext()
  }

  @objc private func chooseAskEveryTime() {
    selection.choose(nil)
    automaticRoutingPaused = false
    message = nil
    updateVisibleViews()
    routeNext()
  }

  @objc private func chooseOnce(_ sender: NSButton) {
    guard let directory = sender.identifier?.rawValue, refreshProfiles(),
      let profile = profiles.first(where: { $0.directory == directory })
    else {
      message = "That profile changed or was removed. Please choose again."
      showPicker()
      return
    }
    open(profile)
  }

  private func open(_ profile: ChromeProfile) {
    guard queue.opening == nil else { return }
    guard
      let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")
    else {
      message = "Google Chrome could not be found. The link is still waiting."
      automaticRoutingPaused = true
      showPicker()
      return
    }
    guard let url = queue.beginOpening() else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    configuration.arguments = ChromeLink.arguments(profile: profile, url: url)
    updateVisibleViews()
    NSWorkspace.shared.openApplication(at: chrome, configuration: configuration) {
      [weak self] _, error in
      let success = error == nil
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.queue.finishOpening(success: success)
        self.automaticRoutingPaused = !success
        self.message =
          success
          ? nil : "Chrome could not be opened. Your link is still here; choose a profile to retry."
        if success {
          if self.queue.links.isEmpty {
            self.window?.orderOut(nil)
            self.updateVisibleViews()
          } else {
            self.routeNext()
          }
        } else {
          self.showPicker()
        }
      }
    }
  }

  @objc private func tryLink() {
    guard
      let url = ChromeLink.parse(
        testField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    else {
      message = "Enter a full address beginning with http:// or https://."
      showPicker()
      return
    }
    queue.append([url])
    message = nil
    showPicker()
  }

  @objc private func cancelLink() {
    queue.skip()
    message = nil
    if queue.links.isEmpty { window?.orderOut(nil) } else { showPicker() }
  }

  @objc private func allowFolderAccess() {
    showPicker()
    guard let window else { return }
    let panel = NSOpenPanel()
    panel.title = "Allow access to Chrome profiles"
    panel.message =
      "Select the Chrome folder. Profile Picker reads profile names from Local State and checks profile folders."
    panel.prompt = "Allow access"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = store.root
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self, response == .OK, let folder = panel.url else { return }
      guard folder.standardizedFileURL == self.store.root.standardizedFileURL else {
        self.message =
          "Please select Library/Application Support/Google/Chrome in your home folder."
        self.showPicker()
        return
      }
      self.accessedFolder?.stopAccessingSecurityScopedResource()
      self.accessedFolder = folder.startAccessingSecurityScopedResource() ? folder : nil
      if let bookmark = try? folder.bookmarkData(
        options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
      {
        UserDefaults.standard.set(bookmark, forKey: "chromeFolderBookmark")
      }
      self.message = nil
      self.refreshProfiles()
      self.updateVisibleViews()
      self.routeNext()
    }
  }

  @objc private func openSettings() {
    if let url = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: "com.apple.systempreferences")
    {
      NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }
  }

  @objc private func setDefaultHandler() {
    guard !configuringDefaults else { return }
    configuringDefaults = true
    Task {
      defer {
        configuringDefaults = false
        updateVisibleViews()
      }
      do {
        for scheme in ["http", "https"] {
          try await NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
        }
        message = nil
      } catch { message = "Web-link setup did not finish: \(error.localizedDescription)" }
    }
  }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = PickerDelegate()
application.delegate = delegate
application.run()

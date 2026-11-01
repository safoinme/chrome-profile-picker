import AppKit

@MainActor
enum PickerUI {
  static let surface = color(0xF8F5EF)
  static let row = color(0xFFFDF9)
  static let ink = color(0x34332D)
  static let secondary = color(0x6D665B)
  static let muted = color(0x777167)
  static let destination = color(0xEEE9E0)
  static let sage = color(0x596F52)
  static let selected = color(0xE8EEE3)
  static let avatars = [color(0xEADCCC), color(0xE2EADC), color(0xE8DFD9)]

  static func color(_ hex: UInt32) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 255) / 255,
      green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
  }

  private static var images: [String: [CGFloat: NSImage]] = [:]

  static func image(_ name: String, size: CGFloat) -> NSImage {
    if let image = images[name]?[size] { return image }
    guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
      let image = NSImage(contentsOf: url)
    else { preconditionFailure("Missing bundled artwork: \(name)") }
    image.size = NSSize(width: size, height: size)
    images[name, default: [:]][size] = image
    return image
  }

  static func glyph(_ name: String, size: CGFloat = 16) -> NSImageView {
    let view = NSImageView(image: image(name, size: size))
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      view.widthAnchor.constraint(equalToConstant: size),
      view.heightAnchor.constraint(equalToConstant: size),
    ])
    return view
  }

  static func text(
    _ value: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
    color: NSColor = secondary
  ) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: value)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    return field
  }

  static func spacer() -> NSView {
    let view = NSView()
    view.setContentHuggingPriority(.init(1), for: .horizontal)
    return view
  }

  static func surface(width: CGFloat, gap: CGFloat, padding: CGFloat = 20) -> (NSView, NSStackView)
  {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
    view.wantsLayer = true
    view.layer?.backgroundColor = surface.cgColor
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = gap
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      view.widthAnchor.constraint(equalToConstant: width),
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
      stack.topAnchor.constraint(equalTo: view.topAnchor, constant: padding),
      stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -padding),
    ])
    return (view, stack)
  }

  static func fit(_ view: NSView, stack: NSStackView, width: CGFloat) -> NSSize {
    for child in stack.arrangedSubviews {
      child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    view.layoutSubtreeIfNeeded()
    return NSSize(width: width, height: view.fittingSize.height)
  }

  static func action(_ title: String, target: AnyObject, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .rounded
    button.font = .systemFont(ofSize: 12)
    return button
  }

  static func settings(target: AnyObject, action: Selector) -> NSButton {
    let button = NSButton(image: image("gear", size: 16), target: target, action: action)
    button.isBordered = false
    button.toolTip = "Settings"
    button.setAccessibilityLabel("Settings")
    button.widthAnchor.constraint(equalToConstant: 24).isActive = true
    button.heightAnchor.constraint(equalToConstant: 24).isActive = true
    return button
  }
}

@MainActor
final class ProfileButton: NSButton {
  private let chosen: Bool
  private var hovering = false
  private var tracking: NSTrackingArea?

  init(
    name: String, index: Int?, shortcut: Bool, selected: Bool, subtitle: String? = nil,
    target: AnyObject, action: Selector
  ) {
    chosen = selected
    super.init(frame: .zero)
    self.target = target
    self.action = action
    title = ""
    isBordered = false
    setButtonType(.momentaryPushIn)
    focusRingType = .exterior
    setAccessibilityLabel(subtitle.map { "\(name). \($0)" } ?? name)
    let content = NSStackView()
    content.spacing = 12
    content.alignment = .centerY
    content.translatesAutoresizingMaskIntoConstraints = false
    if let index {
      let avatar = NSView()
      avatar.wantsLayer = true
      avatar.layer?.backgroundColor = PickerUI.avatars[index % 3].cgColor
      avatar.layer?.cornerRadius = 14
      avatar.widthAnchor.constraint(equalToConstant: 28).isActive = true
      avatar.heightAnchor.constraint(equalToConstant: 28).isActive = true
      let person = PickerUI.glyph("user-\(index % 3)")
      avatar.addSubview(person)
      NSLayoutConstraint.activate([
        person.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
        person.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
      ])
      content.addArrangedSubview(avatar)
    }
    let label = PickerUI.text(
      name, size: subtitle == nil ? 14 : 13, weight: .medium, color: PickerUI.ink)
    label.maximumNumberOfLines = 1
    label.lineBreakMode = .byTruncatingMiddle
    let words = NSStackView(views: [label])
    words.orientation = .vertical
    words.alignment = .leading
    words.spacing = 3
    if let subtitle { words.addArrangedSubview(PickerUI.text(subtitle, size: 11)) }
    content.addArrangedSubview(words)
    content.addArrangedSubview(PickerUI.spacer())
    if shortcut, let index, index < 9 {
      let key = PickerUI.text("⌘\(index + 1)", size: 11, color: PickerUI.muted)
      key.alignment = .center
      key.wantsLayer = true
      key.layer?.backgroundColor = PickerUI.destination.cgColor
      key.layer?.cornerRadius = 5
      key.widthAnchor.constraint(equalToConstant: 32).isActive = true
      key.heightAnchor.constraint(equalToConstant: 21).isActive = true
      content.addArrangedSubview(key)
      keyEquivalent = "\(index + 1)"
      keyEquivalentModifierMask = .command
    } else if selected {
      content.addArrangedSubview(PickerUI.glyph("check"))
    }
    addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      content.centerYAnchor.constraint(equalTo: centerYAnchor),
      heightAnchor.constraint(equalToConstant: subtitle == nil ? 48 : 58),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func hitTest(_ point: NSPoint) -> NSView? {
    super.hitTest(point) == nil ? nil : self
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseEntered(with event: NSEvent) {
    hovering = true
    needsDisplay = true
  }
  override func mouseExited(with event: NSEvent) {
    hovering = false
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let active = isEnabled && (hovering || cell?.isHighlighted == true)
    (chosen || active ? PickerUI.selected : PickerUI.row).setFill()
    NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
  }

  override func drawFocusRingMask() {
    NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
  }

  override var focusRingMaskBounds: NSRect { bounds }
}

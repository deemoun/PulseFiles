import AppKit

@MainActor
package protocol SettingsPageController: AnyObject {
    var rootView: NSView { get }
    var onChange: (() -> Void)? { get set }
    func reloadFromSettings()
}

@MainActor
package class SettingsPageControllerBase: NSObject, SettingsPageController {
    package let rootView: NSView = FlippedSettingsView()
    package var onChange: (() -> Void)?

    package override init() {
        super.init()
        rootView.translatesAutoresizingMaskIntoConstraints = false
    }

    package func reloadFromSettings() {}

    package func install(sections: [NSView]) {
        rootView.subviews.forEach { $0.removeFromSuperview() }
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(stack)
        sections.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: rootView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
    }

    package func section(title: String, views: [NSView]) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .preferredFont(forTextStyle: .headline)
        let stack = NSStackView(views: [label] + views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        views.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    package func labeledPopup(_ title: String, popup: NSPopUpButton) -> NSView {
        let row = NSStackView(views: [NSTextField(labelWithString: title), popup])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillProportionally
        return row
    }
}

private final class FlippedSettingsView: NSView {
    package override var isFlipped: Bool { true }
}

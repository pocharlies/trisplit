// Transient top-center HUD (hs.alert equivalent).
import AppKit

final class HUD {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var hideItem: DispatchWorkItem?

    func show(_ text: String, duration: TimeInterval = 1.2) {
        let p = panel ?? build()
        guard let label else { return }
        label.stringValue = text
        let pad: CGFloat = 18
        let size = label.intrinsicContentSize
        let w = min(size.width + pad * 2, 900), h = size.height + pad
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            p.setFrame(NSRect(x: vf.midX - w / 2, y: vf.maxY - h - 60, width: w, height: h), display: false)
        }
        label.frame = NSRect(x: pad, y: (h - size.height) / 2, width: w - pad * 2, height: size.height)
        hideItem?.cancel()
        p.alphaValue = 1
        p.orderFrontRegardless()
        let item = DispatchWorkItem { [weak p] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                p?.animator().alphaValue = 0
            }, completionHandler: { p?.orderOut(nil) })
        }
        hideItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func build() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 44),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 14
        bg.layer?.masksToBounds = true
        bg.autoresizingMask = [.width, .height]
        p.contentView = bg
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 15, weight: .semibold)
        l.textColor = .labelColor
        l.alignment = .center
        l.lineBreakMode = .byTruncatingTail
        bg.addSubview(l)
        panel = p
        label = l
        return p
    }
}

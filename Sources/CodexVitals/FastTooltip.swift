import AppKit
import SwiftUI

/// A per-label hover tip that does not wait for the system's help delay or take focus.
struct FastTooltip: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> HoverTipView {
        HoverTipView()
    }

    func updateNSView(_ view: HoverTipView, context: Context) {
        if view.text != text {
            view.dismiss()
            view.text = text
        }
    }

    static func dismantleNSView(_ view: HoverTipView, coordinator: ()) {
        view.dismiss()
    }

    final class HoverTipView: NSView {
        var text = ""
        private var hoverArea: NSTrackingArea?
        private var pending: DispatchWorkItem?
        private var panel: NSPanel?

        // Keep account-row clicks and dragging available underneath the hover target.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            hoverArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            dismiss()
            let work = DispatchWorkItem { [weak self] in self?.showTip() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        override func mouseExited(with event: NSEvent) { dismiss() }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            dismiss()
            super.viewWillMove(toWindow: newWindow)
        }

        func dismiss() {
            pending?.cancel()
            pending = nil
            if let panel {
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
            panel = nil
        }

        private func showTip() {
            guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor, !text.isEmpty else { return }
            let anchor = window.convertToScreen(convert(visibleRect, to: nil))
            guard anchor.contains(NSEvent.mouseLocation) else { return }

            let label = NSHostingView(rootView:
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            )
            label.appearance = effectiveAppearance
            let size = label.fittingSize
            let tip = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            tip.isOpaque = false
            tip.backgroundColor = .clear
            tip.hasShadow = true
            tip.ignoresMouseEvents = true
            tip.hidesOnDeactivate = true
            tip.contentView = label
            let screen = window.screen?.visibleFrame ?? anchor
            let x = max(screen.minX + 6, min(anchor.minX, screen.maxX - size.width - 6))
            let y = anchor.minY - size.height - 5
            tip.setFrameOrigin(NSPoint(x: x, y: y < screen.minY + 6 ? anchor.maxY + 5 : y))
            window.addChildWindow(tip, ordered: .above)
            tip.orderFront(nil)
            panel = tip
        }
    }
}

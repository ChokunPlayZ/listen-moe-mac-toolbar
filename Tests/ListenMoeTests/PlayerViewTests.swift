import AppKit
import SwiftUI
import Testing
@testable import ListenMoe

@MainActor
struct PlayerViewTests {
    @Test func fitsMenuBarPopoverWithoutScrolling() {
        let host = NSHostingView(rootView: PlayerView(radio: RadioModel.shared))
        let size = host.fittingSize
        #expect(size.width == 356)
        #expect(size.height >= 340)
        #expect(size.height <= 480)
        host.frame.size = size
        host.layoutSubtreeIfNeeded()
        #expect(scrollViews(in: host).isEmpty)
    }

    @Test(arguments: [PlayerView.Shelf.recent, .saved])
    func libraryExpandsSeparatelyFromPlayer(shelf: PlayerView.Shelf) {
        let collapsed = NSHostingView(rootView: PlayerView(radio: RadioModel.shared))
        let expanded = NSHostingView(rootView: PlayerView(
            radio: RadioModel.shared, maximumHeight: 560, initialShelf: shelf
        ))
        let size = expanded.fittingSize
        #expect(size.width == 356)
        #expect(size.height > collapsed.fittingSize.height)
        #expect(size.height <= min(collapsed.fittingSize.height + 184, 560))
        expanded.frame.size = size
        expanded.layoutSubtreeIfNeeded()
        #expect(scrollViews(in: expanded).count == 1)
    }

    @Test func libraryShrinksToAvailableScreenSpace() throws {
        let collapsed = NSHostingView(rootView: PlayerView(radio: RadioModel.shared))
        let maximumHeight = collapsed.fittingSize.height + 24
        let host = NSHostingView(rootView: PlayerView(
            radio: RadioModel.shared, maximumHeight: maximumHeight, initialShelf: .recent
        ))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height <= maximumHeight)
        let scrollView = try #require(scrollViews(in: host).first)
        #expect(scrollView.frame.height > 0)
        #expect(scrollView.frame.height <= 24)
    }

    @Test func popoverResizesWhenLibraryExpands() {
        let popover = NSPopover()
        let resize: (CGSize) -> Void = { [weak popover] size in popover?.contentSize = size }
        let host = NSHostingController(rootView: PlayerView(
            radio: RadioModel.shared, onSizeChange: resize
        ).id(false))
        host.sizingOptions = []
        popover.contentViewController = host
        popover.contentSize = host.view.fittingSize
        host.view.layoutSubtreeIfNeeded()
        let collapsedHeight = popover.contentSize.height
        host.rootView = PlayerView(
            radio: RadioModel.shared, initialShelf: .recent, onSizeChange: resize
        ).id(true)
        host.view.layoutSubtreeIfNeeded()
        #expect(popover.contentSize.height > collapsedHeight)
        #expect(popover.contentSize.height <= collapsedHeight + 184)
    }

    @Test func playerKeepsNaturalContentSizeDuringHostingViewResize() {
        var reportedSize = CGSize.zero
        let host = NSHostingView(rootView: PlayerView(radio: RadioModel.shared) { reportedSize = $0 })
        let size = host.fittingSize
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: 200, y: 200), size: size),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        #expect(reportedSize.width == size.width)
        #expect(abs(reportedSize.height - size.height) < 1)

        // During collapse the host can still be taller than its new SwiftUI content.
        var frame = window.frame
        frame.origin.y -= 100
        frame.size.height += 100
        window.setFrame(frame, display: false, animate: false)
        host.layoutSubtreeIfNeeded()
        #expect(reportedSize.width == size.width)
        #expect(abs(reportedSize.height - size.height) < 1)
        #expect(abs(host.fittingSize.height - size.height) < 1)
    }

    @Test func shownPopoverStaysAnchoredWhenSwitchingShelves() throws {
        let screen = try #require(NSScreen.main)
        let anchorWindow = NSWindow(
            contentRect: CGRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 30, width: 30, height: 30),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        anchorWindow.isReleasedWhenClosed = false
        let anchor = NSView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        anchorWindow.contentView = anchor
        anchorWindow.orderFront(nil)
        let popover = NSPopover()
        popover.animates = false
        defer {
            popover.close()
            anchorWindow.close()
        }
        let resize: (CGSize) -> Void = { [weak popover] size in
            if popover?.contentSize != size { popover?.contentSize = size }
        }
        let host = NSHostingController(rootView: PlayerView(
            radio: RadioModel.shared, onSizeChange: resize
        ).id("collapsed"))
        host.sizingOptions = []
        popover.contentViewController = host
        popover.contentSize = host.view.fittingSize
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        host.view.layoutSubtreeIfNeeded()
        let window = try #require(host.view.window)
        let originalFrame = window.frame

        for shelf in [PlayerView.Shelf.recent, .saved, nil] as [PlayerView.Shelf?] {
            host.rootView = PlayerView(
                radio: RadioModel.shared, initialShelf: shelf, onSizeChange: resize
            ).id(shelf?.rawValue ?? "collapsed")
            host.view.layoutSubtreeIfNeeded()
            #expect(abs(window.frame.minX - originalFrame.minX) < 1)
            #expect(abs(window.frame.maxY - originalFrame.maxY) < 1)
        }
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        let current = (view as? NSScrollView).map { [$0] } ?? []
        return current + view.subviews.flatMap { scrollViews(in: $0) }
    }

    @Test func chevronExpandsAndCollapsesRecentListByDefault() {
        var selection = PlayerView.ShelfSelection()
        selection.toggleExpansion()
        #expect(selection.selected == .recent)
        selection.toggleExpansion()
        #expect(selection.selected == nil)
    }

    @Test func chevronReopensLastUsedShelf() {
        var selection = PlayerView.ShelfSelection()
        selection.toggle(.saved)
        #expect(selection.selected == .saved)
        selection.toggleExpansion()
        #expect(selection.selected == nil)
        selection.toggleExpansion()
        #expect(selection.selected == .saved)
        selection.toggle(.recent)
        #expect(selection.selected == .recent)
        selection.toggle(.recent)
        #expect(selection.selected == nil)
        selection.toggleExpansion()
        #expect(selection.selected == .recent)
    }
}

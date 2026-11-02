import AppKit
import SwiftUI
import Testing
@testable import ListenMoe

@MainActor
struct FuriganaTextTests {
    @Test func addsRubyAboveJapaneseTextOnlyWhenEnabled() {
        let plain = NSHostingView(rootView: FuriganaText("進撃の巨人", enabled: false).font(.system(size: 16)))
        let ruby = NSHostingView(rootView: FuriganaText("進撃の巨人", enabled: true).font(.system(size: 16)))
        #expect(ruby.fittingSize.height > plain.fittingSize.height)
        #expect(ruby.fittingSize.width > 0)
    }

    @Test func nonJapaneseTextKeepsTheSameLayout() {
        let plain = NSHostingView(rootView: FuriganaText("DAY6", enabled: false))
        let enabled = NSHostingView(rootView: FuriganaText("DAY6", enabled: true))
        #expect(plain.fittingSize == enabled.fittingSize)
    }

    @Test(arguments: [1, 2])
    func rubyWrapsWithinTheRequestedLineLimit(lines: Int) {
        let host = NSHostingView(rootView: FuriganaText(
            "進撃の巨人 東京物語 赤いリボン 小倉唯 進撃の巨人", enabled: true
        ).font(.system(size: 16)).lineLimit(lines).frame(width: 140))
        let size = host.fittingSize
        #expect(size.width == 140)
        #expect(size.height > 0)
        #expect(size.height <= CGFloat(lines) * 34)
        host.frame.size = size
        host.layoutSubtreeIfNeeded()
    }

    @Test func firstBaselineTracksMainTextRatherThanFurigana() {
        let plainBaseline = BaselineMeasurement()
        let rubyBaseline = BaselineMeasurement()
        let plain = NSHostingView(rootView: BaselineProbe(measured: { plainBaseline.record($0) }).callAsFunction {
            FuriganaText("進撃の巨人", enabled: false)
        }.font(.system(size: 10)))
        let ruby = NSHostingView(rootView: BaselineProbe(measured: { rubyBaseline.record($0) }).callAsFunction {
            FuriganaText("進撃の巨人", enabled: true, readingSize: 7)
        }.font(.system(size: 10)))
        _ = plain.fittingSize
        _ = ruby.fittingSize
        #expect(plainBaseline.value > 0)
        #expect(abs(rubyBaseline.value - plainBaseline.value - 9) < 1)
    }
}

private struct BaselineProbe: Layout {
    let measured: @Sendable (CGFloat) -> Void

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let dimensions = subviews[0].dimensions(in: proposal)
        measured(dimensions[.firstTextBaseline])
        return CGSize(width: dimensions.width, height: dimensions.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
    }
}

private final class BaselineMeasurement: @unchecked Sendable {
    private let lock = NSLock()
    private var baseline: CGFloat = 0

    var value: CGFloat { lock.withLock { baseline } }

    func record(_ value: CGFloat) { lock.withLock { baseline = value } }
}

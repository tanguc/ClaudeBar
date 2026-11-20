import Testing
import Foundation
import SwiftUI
import Domain
@testable import ClaudeBar

/// The popover's text scale is the whole feature: every popover font goes
/// through `popoverFont`, so these assertions are what make the secondary text
/// (7–10pt labels, countdowns and comparison lines) readable again.
@Suite
struct PopoverTextScaleTests {

    /// Point sizes are compared with a tolerance: `8 * 1.2` is not exactly
    /// 9.6 in binary floating point, and the policy is about proportions.
    private func isClose(_ actual: CGFloat, _ expected: CGFloat) -> Bool {
        abs(actual - expected) < 0.001
    }

    // MARK: - Scale Factors

    @Test
    func `default renders today's sizes unchanged`() {
        // Medium is today's design, so the popover must not move for anyone
        // who has not chosen a size.
        #expect(PopoverTextSize.medium.textScale == 1.0)
        #expect(isClose(PopoverTextSize.medium.scaled(8), 8))
        #expect(isClose(PopoverTextSize.medium.scaled(26), 26))
    }

    @Test
    func `every size scales monotonically`() {
        let scales = PopoverTextSize.allCases.map(\.textScale)
        #expect(zip(scales, scales.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test
    func `extra large lifts the smallest popover text above 9 points`() {
        // The complaint (#364): the 7pt clock glyph and 8pt SESSION / WEEKLY
        // labels are unreadable on a hi-DPI display.
        #expect(isClose(PopoverTextSize.extraLarge.scaled(7), 9.8))
        #expect(isClose(PopoverTextSize.extraLarge.scaled(8), 11.2))
    }

    @Test
    func `large lifts the smallest popover text too`() {
        #expect(PopoverTextSize.large.scaled(7) > PopoverTextSize.medium.scaled(7))
        #expect(PopoverTextSize.large.scaled(8) > PopoverTextSize.medium.scaled(8))
    }

    @Test
    func `no size renders text smaller than today`() {
        // #364 asked for more readable text, so every offered size is at least
        // the current design: there is no step that shrinks the 7pt glyphs and
        // 8pt card labels.
        #expect(PopoverTextSize.allCases.allSatisfy { $0.textScale >= 1.0 })
        #expect(PopoverTextSize.allCases.allSatisfy { $0.scaled(7) >= 7 })
    }

    @Test
    func `scaling is proportional, not clamped`() {
        // A number twice as big must render twice as big, or the popover stops
        // looking like one design at the larger sizes.
        #expect(isClose(
            PopoverTextSize.extraLarge.scaled(16),
            2 * PopoverTextSize.extraLarge.scaled(8)
        ))
    }

    // MARK: - The Width Follows The Text

    @Test
    func `each size widens the popover in step with its text`() {
        // Text and width move together so nothing that fits today truncates at
        // a larger size.
        #expect(PopoverTextSize.medium.popoverWidth == 400)
        #expect(PopoverTextSize.large.popoverWidth == 480)
        #expect(PopoverTextSize.extraLarge.popoverWidth == 560)
    }

    @Test
    func `every size above Default is wider than the old fixed 400 points`() {
        // The popover used to hardcode `.frame(width: 400)`. If the width ever
        // stops following the policy again, the two larger sizes draw their
        // 1.2x / 1.4x text inside a window sized for 1.0x and everything
        // truncates.
        #expect(PopoverContentWidth.base == 400)
        #expect(PopoverTextSize.large.popoverWidth != PopoverContentWidth.base)
        #expect(PopoverTextSize.extraLarge.popoverWidth != PopoverContentWidth.base)
    }

    // MARK: - The Environment Value

    @Test
    func `views read the default size until the popover injects a choice`() {
        // A view rendered outside the popover (a preview, a snapshot) must not
        // need the environment set up to draw.
        #expect(EnvironmentValues().popoverTextSize == .default)
        var injected = EnvironmentValues()
        injected.popoverTextSize = .large
        #expect(injected.popoverTextSize == .large)
    }

    // MARK: - The Font The Modifier Actually Resolves

    @Test
    func `the modifier lifts the 8pt card label onto the reading ramp at Default`() {
        // fork: 8pt was unreadable even at Default, so the ramp lifts it to
        // 11.5pt before the text size scale applies.
        let modifier = PopoverFontModifier(size: 8, weight: .medium, design: .default)
        #expect(isClose(modifier.pointSize(at: .medium), 11.5))
    }

    @Test
    func `the modifier scales the lifted card label with the text size`() {
        let modifier = PopoverFontModifier(size: 8, weight: .medium, design: .default)
        #expect(isClose(modifier.pointSize(at: .large), 11.5 * 1.2))
        #expect(isClose(modifier.pointSize(at: .extraLarge), 11.5 * 1.4))
    }

    @Test
    func `no popover text renders below the reading floor`() {
        let sizes: [CGFloat] = [7, 7.5, 8, 8.5, 9, 9.5, 10, 10.5, 11, 12]
        for size in sizes {
            #expect(PopoverFontModifier(size: size, weight: nil, design: nil).pointSize(at: .medium) >= 11)
        }
    }

    @Test
    func `the ramp keeps the order between designed sizes`() {
        let sizes: [CGFloat] = [7, 8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 26, 28, 36]
        let lifted = sizes.map(PopoverReadingRamp.lift)
        #expect(zip(lifted, lifted.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test
    func `large sizes only move by a point`() {
        #expect(isClose(PopoverReadingRamp.lift(13), 14))
        #expect(isClose(PopoverReadingRamp.lift(28), 29))
    }

    // MARK: - What The Popover Actually Draws

    @Test @MainActor
    func `the rendered card label grows with the popover text size`() throws {
        // The two assertions above are arithmetic on the Domain type; this one
        // renders the real modifier. If `body` stopped reading the environment
        // — the bug #364 reports, shipped as `size` instead of
        // `pointSize(at:)` — both renders come out identical and this fails.
        let normal = try #require(renderedSize(of: SessionLabelProbe(textSize: .medium)))
        let large = try #require(renderedSize(of: SessionLabelProbe(textSize: .large)))
        let extraLarge = try #require(renderedSize(of: SessionLabelProbe(textSize: .extraLarge)))

        #expect(large.width > normal.width)
        #expect(extraLarge.width > large.width)
        #expect(extraLarge.height >= normal.height)
        // 1.4x is the claim; glyph advances quantise, so ask for a quarter more
        // rather than the exact factor. Unscaled text scores 1.0 here.
        #expect(Double(extraLarge.width) > 1.25 * Double(normal.width))
    }
}

// MARK: - Rendering Probe

/// The reporter's own example, rendered the way the popover renders it: the
/// 8pt SESSION card label with the popover's text size in the environment.
private struct SessionLabelProbe: View {
    let textSize: PopoverTextSize

    var body: some View {
        Text("SESSION")
            .popoverFont(8, weight: .medium, design: .default)
            .environment(\.popoverTextSize, textSize)
    }
}

/// The drawn size of a view, in points at a 1:1 scale so the numbers do not
/// depend on the machine's backing scale.
@MainActor
private func renderedSize<V: View>(of view: V) -> CGSize? {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let image = renderer.cgImage else { return nil }
    return CGSize(width: image.width, height: image.height)
}

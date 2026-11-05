import Foundation
import Testing
@testable import ExtraMouse

@MainActor
struct GestureEngineTests {
    typealias E = GestureEngine.Effect

    private func engine(_ mutate: (inout AppConfig) -> Void = { _ in }) -> GestureEngine {
        var c = AppConfig()
        mutate(&c)
        return GestureEngine(config: c)
    }

    @Test func unboundButtonPassesThrough() {
        let g = engine()
        #expect(g.buttonDown(7, at: 0) == .pass)
        #expect(g.buttonUp(7, at: 0.1) == .pass)
    }

    @Test func clickFiresActionOnRelease() {
        let g = engine()
        let down = g.buttonDown(3, at: 0)
        #expect(down.consume)
        #expect(!down.effects.contains(.perform(.volumeDown)))
        let up = g.buttonUp(3, at: 0.1)
        #expect(up.consume)
        #expect(up.effects == [.perform(.volumeDown)])
    }

    @Test func smallJitterStillCountsAsClick() {
        let g = engine()
        _ = g.buttonDown(3, at: 0)
        _ = g.dragged(3, dx: 2, dy: 1)
        #expect(g.buttonUp(3, at: 0.1).effects == [.perform(.volumeDown)])
    }

    @Test func horizontalDragBecomesDockSwipe() {
        let g = engine()
        _ = g.buttonDown(3, at: 0)
        let r = g.dragged(3, dx: 20, dy: 2)
        #expect(r.consume)
        #expect(r.effects.contains(.freezeCursor(true)))
        #expect(r.effects.contains { if case .dockSwipe(.horizontal, .began, _) = $0 { true } else { false } })
        let more = g.dragged(3, dx: 10, dy: 30) // axis stays locked
        #expect(more.effects.contains { if case .dockSwipe(.horizontal, .changed, _) = $0 { true } else { false } })
        let up = g.buttonUp(3, at: 0.5)
        #expect(up.effects == [.dockSwipe(.horizontal, .ended, delta: 0), .freezeCursor(false)])
        #expect(!up.effects.contains(.perform(.volumeDown)))
    }

    @Test func verticalDragUsesVerticalAxis() {
        let g = engine()
        _ = g.buttonDown(3, at: 0)
        let r = g.dragged(3, dx: 1, dy: -20)
        #expect(r.effects.contains { if case .dockSwipe(.vertical, .began, let d) = $0 { d < 0 } else { false } })
    }

    @Test func discreteSwipeWhenFluidGesturesOff() {
        let g = engine { $0.fluidGestures = false }
        _ = g.buttonDown(3, at: 0)
        _ = g.dragged(3, dx: 10, dy: 0)
        let r = g.dragged(3, dx: 40, dy: 0)
        #expect(r.effects.contains(.perform(.spaceLeft))) // drag right → Space on the left
        let again = g.dragged(3, dx: 80, dy: 0)
        #expect(!again.effects.contains { if case .perform = $0 { true } else { false } }) // fires once
        _ = g.buttonUp(3, at: 1)
    }

    @Test func dragToScroll() {
        let g = engine()
        _ = g.buttonDown(4, at: 0)
        let r = g.dragged(4, dx: 0, dy: 10)
        #expect(r.effects.contains(.dragScroll(.began, dx: 0, dy: 10)))
        #expect(g.dragged(4, dx: 1, dy: 2).effects == [.dragScroll(.changed, dx: 1, dy: 2)])
        #expect(g.buttonUp(4, at: 1).effects == [.dragScroll(.ended, dx: 0, dy: 0), .freezeCursor(false)])
    }

    @Test func scrollWhileHeldZoomsAndSuppressesClick() {
        let g = engine()
        _ = g.buttonDown(4, at: 0)
        let r = g.scrolled(.init(dy: 1), at: 0.1)
        #expect(r.consume)
        #expect(r.effects.contains(.magnify(.began, amount: 0)))
        #expect(r.effects.contains { if case .magnify(.changed, let a) = $0 { a > 0 } else { false } })
        let up = g.buttonUp(4, at: 0.3)
        #expect(!up.effects.contains(.perform(.volumeUp)))
        #expect(g.timerFired(.zoomEnd) == [.magnify(.ended, amount: 0)])
    }

    @Test func scrollSwitchesSpacesWithCooldown() {
        let g = engine()
        _ = g.buttonDown(3, at: 0)
        #expect(g.scrolled(.init(dy: 1), at: 1.0).effects == [.perform(.spaceRight)])
        #expect(g.scrolled(.init(dy: 1), at: 1.1).effects.isEmpty)
        #expect(g.scrolled(.init(dy: -1), at: 1.5).effects == [.perform(.spaceLeft)])
    }

    @Test func plainScrollPassesThrough() {
        let g = engine()
        #expect(g.scrolled(.init(dy: 1), at: 0) == .pass)
    }

    @Test func commandScrollZoomsWhenEnabled() {
        let g = engine { $0.commandScrollZooms = true }
        #expect(g.scrolled(.init(dy: 1, command: true), at: 0).consume)
        let off = engine()
        #expect(off.scrolled(.init(dy: 1, command: true), at: 0) == .pass)
    }

    @Test func doubleClickWaitsThenFiresSingle() {
        let g = engine { $0.bindings = [ButtonBinding(button: 3, click: .volumeDown, doubleClick: .missionControl)] }
        _ = g.buttonDown(3, at: 0)
        let up = g.buttonUp(3, at: 0.05)
        #expect(up.effects == [.schedule(.doubleClick, after: GestureEngine.doubleClickWindow)])
        #expect(g.timerFired(.doubleClick) == [.perform(.volumeDown)])
    }

    @Test func doubleClickFiresDoubleAction() {
        let g = engine { $0.bindings = [ButtonBinding(button: 3, click: .volumeDown, doubleClick: .missionControl)] }
        _ = g.buttonDown(3, at: 0)
        _ = g.buttonUp(3, at: 0.05)
        let second = g.buttonDown(3, at: 0.1)
        #expect(second.effects.contains(.cancel(.doubleClick)))
        #expect(g.buttonUp(3, at: 0.15).effects == [.perform(.missionControl)])
        #expect(g.timerFired(.doubleClick).isEmpty)
    }

    @Test func holdFiresOnceAndSuppressesClick() {
        let g = engine { $0.bindings = [ButtonBinding(button: 3, click: .volumeDown, hold: .showDesktop)] }
        let down = g.buttonDown(3, at: 0)
        #expect(down.effects == [.schedule(.hold, after: GestureEngine.holdDelay)])
        #expect(g.timerFired(.hold) == [.perform(.showDesktop)])
        let up = g.buttonUp(3, at: 1)
        #expect(up.effects == [.cancel(.hold)])
    }

    @Test func buttonWithoutClickActionReplaysNativeClick() {
        let g = engine { $0.bindings = [ButtonBinding(button: 3, drag: .dragToScroll)] }
        _ = g.buttonDown(3, at: 0)
        #expect(g.buttonUp(3, at: 0.1).effects == [.nativeClick(button: 3)])
    }

    @Test func disabledPassesEverything() {
        let g = engine { $0.enabled = false }
        #expect(g.buttonDown(3, at: 0) == .pass)
        #expect(g.scrolled(.init(dy: 1), at: 0) == .pass)
    }

    @Test func customDirectionFiresAction() {
        let dirs = DirectionalActions(up: .launchpad, down: nil, left: .back, right: .forward)
        let g = engine { $0.bindings = [ButtonBinding(button: 5, drag: .directional(dirs))] }
        _ = g.buttonDown(5, at: 0)
        _ = g.dragged(5, dx: -10, dy: 0)
        #expect(g.dragged(5, dx: -40, dy: 0).effects == [.perform(.back)])
    }

    @Test func resetUnfreezesCursorMidGesture() {
        let g = engine()
        _ = g.buttonDown(3, at: 0)
        _ = g.dragged(3, dx: 30, dy: 0)
        #expect(g.reset().contains(.freezeCursor(false)))
        #expect(!g.isBusy)
    }

    @Test func configRoundTripsAndToleratesMissingKeys() throws {
        let data = try JSONEncoder().encode(AppConfig())
        #expect(try JSONDecoder().decode(AppConfig.self, from: data) == AppConfig())
        let partial = Data(#"{"enabled":false}"#.utf8)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: partial)
        #expect(decoded.enabled == false)
        #expect(decoded.bindings == AppConfig.defaultBindings)
    }
}

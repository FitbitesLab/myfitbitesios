import SwiftUI
import UIKit

enum LaunchTransition {
    static let splashDuration = 0.78
    static let homeDuration = 0.92
    static let homeDelay = 0.08
}

/// Let prepared Home content pass through layout before uncovering it.
struct HomeLaunchReadiness: UIViewRepresentable {
    let isPrepared: Bool
    let onReady: () -> Void

    func makeUIView(context: Context) -> ReadinessView { ReadinessView() }

    func updateUIView(_ view: ReadinessView, context: Context) {
        view.onReady = onReady
        view.isPrepared = isPrepared
        view.startIfNeeded()
    }

    static func dismantleUIView(_ view: ReadinessView, coordinator: ()) {
        view.stop()
    }

    final class ReadinessView: UIView {
        var isPrepared = false
        var onReady: (() -> Void)?
        private var displayLink: CADisplayLink?
        private var frames = 0
        private var hasReported = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { stop() } else { startIfNeeded() }
        }

        func startIfNeeded() {
            guard isPrepared, window != nil, !hasReported, displayLink == nil else { return }
            frames = 0
            let link = CADisplayLink(target: self, selector: #selector(nextFrame))
            displayLink = link
            link.add(to: .main, forMode: .common)
        }

        @objc private func nextFrame() {
            guard isPrepared, window != nil else { stop(); return }
            frames += 1
            guard frames >= 2 else { return }
            stop()
            hasReported = true
            onReady?()
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }
    }
}

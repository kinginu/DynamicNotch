import Foundation
import AppKit
import SwiftUI
import Combine
import Observation
// startAnimation / animLoop / measured / shouldMove; @State contentSize, isAnimating, offset;
//   linear animation of duration (contentWidth + spacing) / speed, restarted on completion; stops on disappear.
// Single-line text marquee: static when the text fits, otherwise scrolls left in a loop (two copies,
//   `spacing` apart) after a short pause, with faded edges.
struct TheMarquee: View {
    let text: String
    var font: Font = .body
    /// points per second
    var speed: CGFloat = 30
    var spacing: CGFloat = 28
    var startDelay: Double = 1.5
    /// arbitrary content (QuickPeeksView); when nil the view shows `text`
    private var customContent: (() -> AnyView)? = nil

    init(text: String, font: Font = .body, speed: CGFloat = 30, spacing: CGFloat = 28, startDelay: Double = 1.5) {
        self.text = text
        self.font = font
        self.speed = speed
        self.spacing = spacing
        self.startDelay = startDelay
    }

    /// original shape: `TheMarquee { AnyView(...) }`
    init(content: @escaping () -> AnyView) {
        self.text = ""
        self.customContent = content
    }

    @State private var contentSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0
    @State private var isAnimating: Bool = false

    private var measured: Bool { contentSize.width > 0 && containerWidth > 0 }
    private var shouldMove: Bool { measured && contentSize.width > containerWidth + 1 }

    var body: some View {
        label
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    HStack(spacing: spacing) {
                        label
                        if shouldMove { label }
                    }
                    .fixedSize()
                    .offset(x: isAnimating ? -(contentSize.width + spacing) : 0)
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in
                        if abs(w - containerWidth) > 0.5 { containerWidth = w; restart() }
                    }
                }
            }
            .background(alignment: .leading) {
                label.fixedSize().hidden()
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { setContentSize(g.size) }
                            .onChange(of: g.size) { _, s in setContentSize(s) }
                    })
            }
            .clipped()
            .mask {
                if shouldMove {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                           .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                } else {
                    Rectangle()
                }
            }
            .onChange(of: text) { _, _ in restart() }
            .onAppear { restart() }
            .onDisappear { stopAnimation() }
    }

    @ViewBuilder private var label: some View {
        if let customContent {
            customContent()
        } else {
            Text(verbatim: text).font(font).lineLimit(1)
        }
    }

    private func setContentSize(_ size: CGSize) {
        guard abs(size.width - contentSize.width) > 0.5 || abs(size.height - contentSize.height) > 0.5 else { return }
        contentSize = size
        restart()
    }

    private func stopAnimation() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { isAnimating = false }
    }

    /// startAnimation: only when measured and the content overflows
    private func restart() {
        stopAnimation()
        guard shouldMove else { return }
        let duration = Double((contentSize.width + spacing) / max(speed, 1))
        DispatchQueue.main.async {
            withAnimation(.linear(duration: duration).delay(startDelay).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

import AppKit
import SwiftUI

private struct InteractiveHoverModifier: ViewModifier {
    let backgroundOpacity: Double
    let cornerRadius: CGFloat

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background {
                if backgroundOpacity > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(isHovering ? backgroundOpacity : 0))
                }
            }
            .animation(.easeInOut(duration: 0.12), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

private struct PointerCursorHoverModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                updateHoverState(hovering)
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
    }

    private func updateHoverState(_ hovering: Bool) {
        guard hovering != isHovering else {
            return
        }

        isHovering = hovering

        if hovering {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }
}

extension View {
    func appInteractiveHover(
        scale: CGFloat = 1,
        opacity: Double = 1,
        brightness: Double = 0,
        backgroundOpacity: Double = 0.08,
        cornerRadius: CGFloat = 10
    ) -> some View {
        modifier(
            InteractiveHoverModifier(
                backgroundOpacity: backgroundOpacity,
                cornerRadius: cornerRadius
            )
        )
    }

    func appLinkHover() -> some View {
        modifier(PointerCursorHoverModifier())
    }
}

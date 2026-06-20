import SwiftUI
import UIKit

/// Lightweight tactile feedback for control touches on the remote (an iPhone, so
/// the Taptic Engine is available).
enum Haptics {
    /// A light tap — for transport and other momentary button presses.
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// A medium tap — for primary actions like play/pause.
    static func impact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// A selection tick — for picking a row or switching context.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

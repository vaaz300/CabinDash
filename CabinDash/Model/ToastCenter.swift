import Observation
import SwiftUI

/// One short message at a time, with an optional action such as Undo.
@MainActor @Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let actionTitle: String?
    }

    private(set) var current: Toast?

    @ObservationIgnored private var action: (() -> Void)?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func show(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        dismissTask?.cancel()
        self.action = action
        current = Toast(message: message, actionTitle: actionTitle)
        AccessibilityNotification.Announcement(message).post()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    func performAction() {
        let pending = action
        dismiss()
        pending?()
    }

    func dismiss() {
        dismissTask?.cancel()
        clear()
    }

    private func clear() {
        current = nil
        action = nil
    }
}

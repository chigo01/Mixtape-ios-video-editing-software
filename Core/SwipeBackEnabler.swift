//
//  SwipeBackEnabler.swift
//  Mixtape
//

import SwiftUI
import UIKit

/// Restores the edge-swipe back gesture on screens that hide the system
/// navigation bar (`.toolbar(.hidden, for: .navigationBar)` +
/// `.navigationBarBackButtonHidden(true)`).
///
/// SwiftUI's `NavigationStack` is backed by `UINavigationController`, whose
/// `interactivePopGestureRecognizer` refuses to begin when the back button is
/// hidden. Hooking `viewDidLoad` makes every navigation controller its own
/// gesture delegate, so the swipe works whenever there is a screen to pop to —
/// and never on the root (popping the root freezes UIKit navigation).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1 && presentedViewController == nil
    }
}

/// Prevents the global edge-pop recognizer from competing with the editor's
/// timeline, graphs, horizontal toolbars, and docked iPad inspectors.
struct EditorNavigationPopGestureLock: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> LockController {
        LockController()
    }

    func updateUIViewController(_ controller: LockController, context: Context) {
        controller.setLocked(UIDevice.current.userInterfaceIdiom == .pad)
    }

    static func dismantleUIViewController(_ controller: LockController, coordinator: ()) {
        controller.releaseLock()
    }

    final class LockController: UIViewController {
        private weak var lockedNavigationController: UINavigationController?
        private var shouldLock = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyLockIfNeeded()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyLockIfNeeded()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            releaseLock()
        }

        func setLocked(_ locked: Bool) {
            shouldLock = locked
            DispatchQueue.main.async { [weak self] in
                self?.applyLockIfNeeded()
            }
        }

        func releaseLock() {
            lockedNavigationController?.interactivePopGestureRecognizer?.isEnabled = true
            lockedNavigationController = nil
        }

        private func applyLockIfNeeded() {
            guard shouldLock, viewIfLoaded?.window != nil else {
                releaseLock()
                return
            }
            guard let navigationController else { return }
            if lockedNavigationController !== navigationController {
                releaseLock()
                lockedNavigationController = navigationController
            }
            navigationController.interactivePopGestureRecognizer?.isEnabled = false
        }
    }
}

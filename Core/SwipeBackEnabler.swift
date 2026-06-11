//
//  SwipeBackEnabler.swift
//  Mixtape
//

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

import SwiftUI
import UIKit

/// Turns off the navigation "swipe back" gestures while the view is on screen.
/// iPadOS 26 also pops on a right swipe anywhere in the content, which would
/// steal the swipe used to go to the previous page.
struct PopGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setPopGestures(enabled: false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setPopGestures(enabled: true)
        }

        private func setPopGestures(enabled: Bool) {
            guard let navigation = navigationController ?? findNavigationController() else { return }
            navigation.interactivePopGestureRecognizer?.isEnabled = enabled
            navigation.interactiveContentPopGestureRecognizer?.isEnabled = enabled
        }

        private func findNavigationController() -> UINavigationController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let navigation = current as? UINavigationController { return navigation }
                responder = current.next
            }
            return nil
        }
    }
}

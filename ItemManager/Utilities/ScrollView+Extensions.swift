//
//  ScrollView+Extensions.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/10/26.
//

import SwiftUI
import UIKit

struct ScrollViewNoBounceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ScrollViewConfigurator { scrollView in
                    scrollView.bounces = false
                }
            )
    }
}

struct ScrollViewConfigurator: UIViewRepresentable {
    let configure: (UIScrollView) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false // Ensure it doesn't block touches
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let scrollView = self.findScrollView(in: uiView) {
                self.configure(scrollView)
            }
        }
    }
    
    private func findScrollView(in view: UIView) -> UIScrollView? {
        var current: UIView? = view
        while let view = current {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            // SwiftUI's ScrollView usually wraps content in a HostingController's view, 
            // which is a subview of UIScrollView.
            // So we traverse UP.
            current = view.superview
        }
        return nil
    }
}

extension View {
    /// Disables the bounce/rubber-band effect of the enclosing ScrollView.
    /// Must be applied to a view *inside* the ScrollView.
    func disableScrollBounce() -> some View {
        self.modifier(ScrollViewNoBounceModifier())
    }
}

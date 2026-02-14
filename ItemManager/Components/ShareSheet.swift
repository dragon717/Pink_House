//
//  ShareSheet.swift
//  ItemManager
//
//  Created by Pink House Dev on 2024/02/14.
//

import SwiftUI
import UIKit

// ShareSheet 包装器，用于在 SwiftUI 中使用 UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

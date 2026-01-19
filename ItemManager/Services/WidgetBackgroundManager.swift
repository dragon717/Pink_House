//
//  WidgetBackgroundManager.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import UIKit
import WidgetKit

class WidgetBackgroundManager {
    static let shared = WidgetBackgroundManager()
    private let fileManager = FileManager.default
    private let filename = "widget_background.jpg"
    
    // Computed property to get the file URL in the App Group container
    private var imageURL: URL? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: SharedPersistence.appGroupIdentifier) else {
            print("WidgetBackgroundManager: Could not find App Group container.")
            return nil
        }
        return container.appendingPathComponent(filename)
    }
    
    func saveImage(_ image: UIImage) {
        guard let url = imageURL else { return }
        
        // Compress and write to shared container
        if let data = image.jpegData(compressionQuality: 0.8) {
            do {
                try data.write(to: url)
                print("WidgetBackgroundManager: Image saved to \(url.path)")
                // Notify Widget to reload
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                print("WidgetBackgroundManager: Error saving image - \(error)")
            }
        }
    }
    
    func loadImage() -> UIImage? {
        guard let url = imageURL, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    func deleteImage() {
        guard let url = imageURL else { return }
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                print("WidgetBackgroundManager: Image deleted.")
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            print("WidgetBackgroundManager: Error deleting image - \(error)")
        }
    }
    
    func hasCustomBackground() -> Bool {
        guard let url = imageURL else { return false }
        return fileManager.fileExists(atPath: url.path)
    }
}

import XCTest
import UIKit
@testable import ItemManager

final class WardrobeNavigationStyleTests: XCTestCase {
    func testAvailableStylesOnIPadOnlyContainsClassic() {
        XCTAssertEqual(WardrobeNavigationStyle.availableStyles(for: .pad), [.classic])
    }
    
    func testFashionStyleResolvesToClassicOnIPad() {
        XCTAssertEqual(WardrobeNavigationStyle.fashion.resolved(for: .pad), .classic)
    }
    
    func testNormalizeStoredPreferenceConvertsFashionToClassicOnIPad() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(WardrobeNavigationStyle.fashion.rawValue, forKey: WardrobeNavigationStyle.userDefaultsKey)
        
        let normalized = WardrobeNavigationStyle.normalizeStoredPreference(
            userDefaults: defaults,
            idiom: .pad
        )
        
        XCTAssertEqual(normalized, .classic)
        XCTAssertEqual(
            defaults.string(forKey: WardrobeNavigationStyle.userDefaultsKey),
            WardrobeNavigationStyle.classic.rawValue
        )
    }
    
    func testNormalizeStoredPreferenceKeepsFashionOnIPhone() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(WardrobeNavigationStyle.fashion.rawValue, forKey: WardrobeNavigationStyle.userDefaultsKey)
        
        let normalized = WardrobeNavigationStyle.normalizeStoredPreference(
            userDefaults: defaults,
            idiom: .phone
        )
        
        XCTAssertEqual(normalized, .fashion)
        XCTAssertEqual(
            defaults.string(forKey: WardrobeNavigationStyle.userDefaultsKey),
            WardrobeNavigationStyle.fashion.rawValue
        )
    }
}

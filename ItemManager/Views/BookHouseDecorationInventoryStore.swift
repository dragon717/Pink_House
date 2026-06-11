import Combine
import Foundation

@MainActor
final class BookHouseDecorationInventoryStore: ObservableObject {
    static let shared = BookHouseDecorationInventoryStore()

    @Published private(set) var storedFeatureIDs: Set<AppFeatureID>
    @Published var showsPlacementControls: Bool {
        didSet {
            UserDefaults.standard.set(showsPlacementControls, forKey: Self.showsPlacementControlsKey)
        }
    }
    @Published var showsStaticDecorations: Bool {
        didSet {
            UserDefaults.standard.set(showsStaticDecorations, forKey: Self.showsStaticDecorationsKey)
        }
    }

    private static let storedFeaturesKey = "bookHouse.featureDecorationBackpack.v1"
    private static let showsPlacementControlsKey = "bookHouse.debug.showsPlacementControls.v1"
    private static let showsStaticDecorationsKey = "bookHouse.debug.showsStaticDecorations.v1"
    static let itemLayoutDefaultsKey = "bookHouse.prototypeItemPositions.v3"
    static let userInitialItemLayoutDefaultsKey = "bookHouse.userInitialItemPositions.v1"
    private static let userInitialStoredFeaturesKey = "bookHouse.userInitialFeatureDecorationBackpack.v1"

    private init() {
        let defaults = UserDefaults.standard
        let savedIDs = defaults.stringArray(forKey: Self.storedFeaturesKey) ?? []
        storedFeatureIDs = Set(savedIDs.compactMap(AppFeatureID.init(rawValue:)))

        if defaults.object(forKey: Self.showsPlacementControlsKey) != nil {
            showsPlacementControls = defaults.bool(forKey: Self.showsPlacementControlsKey)
        } else {
            #if DEBUG
            showsPlacementControls = true
            #else
            showsPlacementControls = false
            #endif
        }

        showsStaticDecorations = defaults.bool(forKey: Self.showsStaticDecorationsKey)
    }

    func isStored(_ featureID: AppFeatureID) -> Bool {
        storedFeatureIDs.contains(featureID)
    }

    func store(_ featureID: AppFeatureID) {
        guard !storedFeatureIDs.contains(featureID) else { return }
        storedFeatureIDs.insert(featureID)
        saveStoredFeatures()
    }

    func restore(_ featureID: AppFeatureID) {
        guard storedFeatureIDs.contains(featureID) else { return }
        storedFeatureIDs.remove(featureID)
        saveStoredFeatures()
    }

    func toggle(_ featureID: AppFeatureID) {
        if isStored(featureID) {
            restore(featureID)
        } else {
            store(featureID)
        }
    }

    func storeAll(_ featureIDs: [AppFeatureID]) {
        storedFeatureIDs.formUnion(featureIDs)
        saveStoredFeatures()
    }

    func restoreAll(_ featureIDs: [AppFeatureID]? = nil) {
        if let featureIDs {
            storedFeatureIDs.subtract(featureIDs)
        } else {
            storedFeatureIDs.removeAll()
        }
        saveStoredFeatures()
    }

    func resetRoomLayoutOverrides() {
        let defaults = UserDefaults.standard
        if let userInitialLayoutData = defaults.data(forKey: Self.userInitialItemLayoutDefaultsKey) {
            defaults.set(userInitialLayoutData, forKey: Self.itemLayoutDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.itemLayoutDefaultsKey)
        }
        restoreStoredFeaturesFromUserInitialIfAvailable()
        NotificationCenter.default.post(name: .bookHouseLayoutOverridesDidReset, object: nil)
        objectWillChange.send()
    }

    func saveCurrentStoredFeaturesAsUserInitial() {
        let rawValues = storedFeatureIDs.map(\.rawValue).sorted()
        UserDefaults.standard.set(rawValues, forKey: Self.userInitialStoredFeaturesKey)
    }

    private func saveStoredFeatures() {
        let rawValues = storedFeatureIDs.map(\.rawValue).sorted()
        UserDefaults.standard.set(rawValues, forKey: Self.storedFeaturesKey)
    }

    private func restoreStoredFeaturesFromUserInitialIfAvailable() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.userInitialStoredFeaturesKey) != nil else { return }

        let savedIDs = defaults.stringArray(forKey: Self.userInitialStoredFeaturesKey) ?? []
        storedFeatureIDs = Set(savedIDs.compactMap(AppFeatureID.init(rawValue:)))
        saveStoredFeatures()
    }
}

extension Notification.Name {
    static let bookHouseLayoutOverridesDidReset = Notification.Name("bookHouseLayoutOverridesDidReset")
}

//
//  Settings.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 5/8/23.
//
//  Resources
//  ---------
//  - "How To Use Multi Value Title and Value From Settings Bundle"
//    https://stackoverflow.com/questions/16451136/how-to-use-multi-value-title-and-value-from-settings-bundle
//

import Combine
import Foundation
import OSLog

class Settings: ObservableObject {
    @Published var pairedDeviceID: UUID? {
        didSet {
            guard pairedDeviceID != oldValue else { return }
            let uuidString = pairedDeviceID?.uuidString ?? "" // use "" for none
            UserDefaults.standard.set(uuidString, forSettingsKey: .pairedDeviceID)
            Logger.settings.log("[Settings] Set: \(Keys.pairedDeviceID.rawValue) = \(uuidString)")
        }
    }

    enum Keys: String {
        case pairedDeviceID = "paired_device_id"
    }

    public init() {
        Self.registerDefaults()
        NotificationCenter.default.addObserver(self, selector: #selector(Self.onSettingsChanged), name: UserDefaults.didChangeNotification, object: nil)
        onSettingsChanged()
    }

    private static func getRootPListURL() -> URL? {
        guard let settingsBundle = Bundle.main.url(forResource: "Settings", withExtension: "bundle") else {
            Logger.settings.log("[Settings] Could not find Settings.bundle")
            return nil
        }
        return settingsBundle.appendingPathComponent("Root.plist")
    }

    /// Sets the default values, if values do not already exist, for all settings from our Root.plist
    private static func registerDefaults() {
        guard let url = getRootPListURL() else {
            return
        }

        guard let settings = NSDictionary(contentsOf: url) else {
            Logger.settings.log("[Settings] Couldn't find Root.plist in settings bundle")
            return
        }

        guard let preferences = settings.object(forKey: "PreferenceSpecifiers") as? [[String: AnyObject]] else {
            Logger.settings.log("[Settings] Root.plist has an invalid format")
            return
        }

        var defaultsToRegister = [String: AnyObject]()
        for preference in preferences {
            guard let key = preference["Key"] as? String, let value = preference["DefaultValue"] else { continue }
            Logger.settings.log("[Settings] Registering default: \(key) = \(value.debugDescription ?? "<none>")")
            defaultsToRegister[key] = value as AnyObject
        }

        UserDefaults.standard.register(defaults: defaultsToRegister)
    }

    @objc private func onSettingsChanged() {
        // This property is not exposed to users in Settings and so may be absent
        let uuid = UserDefaults.standard.string(forSettingsKey: .pairedDeviceID).flatMap(UUID.init(uuidString:))
        if self.pairedDeviceID != uuid {
            self.pairedDeviceID = uuid
        }
    }
}

extension UserDefaults {
    func string(forSettingsKey settingsKey: Settings.Keys) -> String? {
        string(forKey: settingsKey.rawValue)
    }

    func integer(forSettingsKey settingsKey: Settings.Keys) -> Int {
        integer(forKey: settingsKey.rawValue)
    }

    func float(forSettingsKey settingsKey: Settings.Keys) -> Float {
        float(forKey: settingsKey.rawValue)
    }

    func set(_ value: Any?, forSettingsKey settingsKey: Settings.Keys) {
        setValue(value, forKey: settingsKey.rawValue)
    }
}

extension Logger {
    static let settings = Logger(subsystem: "Util", category: "Settings")
}

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
    @Published var openAiApiKey: String = "" {
        didSet {
            guard openAiApiKey != oldValue else { return }
            UserDefaults.standard.set(openAiApiKey, forSettingsKey: .openAI)
            Logger.settings.log("[Settings] Set: \(Keys.openAI.rawValue) = \(self.openAiApiKey)")
        }
    }
    @Published var gptModel: String = "" {
        didSet {
            guard gptModel != oldValue else { return }
            UserDefaults.standard.set(gptModel, forSettingsKey: .gptModel)
            Logger.settings.log("[Settings] Set: \(Keys.gptModel.rawValue) = \(self.gptModel)")
        }
    }
    @Published var stabilityAiApiKey: String = "" {
        didSet {
            guard stabilityAiApiKey != oldValue else { return }
            UserDefaults.standard.set(stabilityAiApiKey, forSettingsKey: .stabilityAI)
            Logger.settings.log("[Settings] Set: \(Keys.stabilityAI.rawValue) = \(self.stabilityAiApiKey)")
        }
    }
    @Published var pairedDeviceID: UUID? {
        didSet {
            guard pairedDeviceID != oldValue else { return }
            let uuidString = pairedDeviceID?.uuidString ?? "" // use "" for none
            UserDefaults.standard.set(uuidString, forSettingsKey: .pairedDeviceID)
            Logger.settings.log("[Settings] Set: \(Keys.pairedDeviceID.rawValue) = \(uuidString)")
        }
    }
    @Published private(set) var stableDiffusionModel: String = ""
    @Published private(set) var imageStrength: Float = 0
    @Published private(set) var imageGuidance: Int = 0

    enum Keys: String {
        case openAI = "api_key"
        case gptModel = "model"
        case stabilityAI = "stability_api_key"
        case stableDiffusionModel = "stability_sd_model"
        case imageStrength = "stability_image_strength"
        case imageGuidance = "stability_guidance"
        case pairedDeviceID = "paired_device_id"
    }

    let supportedGPTModels: [String]
    private let _gptModelToPrintableName: [String: String]

    public init() {
        Self.registerDefaults()

        let (modelNames, supportedModels) = Self.getPossibleTitlesAndValuesForMultiValueItem(withKey: .gptModel)
        self.supportedGPTModels = supportedModels

        var modelToPrintableName: [String: String] = [:]
        for i in 0..<min(modelNames.count, supportedModels.count) {
            modelToPrintableName[supportedModels[i]] = modelNames[i]
        }
        _gptModelToPrintableName = modelToPrintableName

        NotificationCenter.default.addObserver(self, selector: #selector(Self.onSettingsChanged), name: UserDefaults.didChangeNotification, object: nil)
        onSettingsChanged()
    }

    public func printableGPTModelName(model: String) -> String {
        _gptModelToPrintableName[model] ?? "?"
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

    /// Reads Root.plist to find all possible title and values of a multi-valued item, where the values are strings.
    /// - Parameter withKey: The key of the setting (stored in the "Identifier" field under the multi-value item in Root.plist).
    /// - Returns: Titles and values, or empty for both if an error occurred and the multi-valued item was unable to be read.
    private static func getPossibleTitlesAndValuesForMultiValueItem(withKey key: Keys) -> ([String], [String]) {
        guard let url = getRootPListURL() else {
            return ([], [])
        }

        guard let data = try? Data(contentsOf: url) else {
            Logger.settings.log("[Settings] Unable to load Root.plist")
            return ([], [])
        }

        guard let settings = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let preferenceSpecifiers = settings["PreferenceSpecifiers"] as? [[String: Any]] else {
            Logger.settings.log("[Settings] Unable to access preference specifiers")
            return ([], [])
        }

        guard let multiValueItem = preferenceSpecifiers.first(where: { $0["Key"] as? String == key.rawValue }),
              let possibleValues = multiValueItem["Values"] as? [Any],
              let titles = multiValueItem["Titles"] as? [Any] else {
            Logger.settings.log("[Settings] Unable to read allowable values for key: \(key.rawValue)")
            return ([], [])
        }

        return (titles.compactMap { $0 as? String }, possibleValues.compactMap { $0 as? String })
    }

    @objc private func onSettingsChanged() {
        // Publish changes when settings have been edited
        let openAIKey = UserDefaults.standard.string(forSettingsKey: .openAI) ?? ""
        if openAIKey != self.openAiApiKey {
            self.openAiApiKey = openAIKey
        }

        let model = UserDefaults.standard.string(forSettingsKey: .gptModel) ?? "gpt-3.5-turbo"
        if model != self.gptModel {
            self.gptModel = model
        }

        let stabilityAIKey = UserDefaults.standard.string(forSettingsKey: .stabilityAI) ?? ""
        if stabilityAIKey != self.stabilityAiApiKey {
            self.stabilityAiApiKey = stabilityAIKey
        }

        let stableDiffusionModel = UserDefaults.standard.string(forSettingsKey: .stableDiffusionModel) ?? ""
        if stableDiffusionModel != self.stableDiffusionModel {
            self.stableDiffusionModel = stableDiffusionModel
        }

        let imageStrength = UserDefaults.standard.float(forSettingsKey: .imageStrength)
        if imageStrength != self.imageStrength {
            self.imageStrength = imageStrength
        }

        let imageGuidance = UserDefaults.standard.integer(forSettingsKey: .imageGuidance)
        if imageGuidance != self.imageGuidance {
            self.imageGuidance = imageGuidance
        }

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

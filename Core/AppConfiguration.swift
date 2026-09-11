import Foundation

enum AppConfiguration {
    static let freesoundAPIKey = value(for: "FreesoundAPIKey")

    private static func value(for key: String) -> String {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return ""
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("$(") ? "" : value
    }
}

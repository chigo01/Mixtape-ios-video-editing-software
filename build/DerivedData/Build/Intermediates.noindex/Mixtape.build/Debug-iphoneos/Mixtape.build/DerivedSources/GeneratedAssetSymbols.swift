import Foundation
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "AccentColor" asset catalog color resource.
    static let accent = DeveloperToolsSupport.ColorResource(name: "AccentColor", bundle: resourceBundle)

    /// The "BackgroundColor" asset catalog color resource.
    static let background = DeveloperToolsSupport.ColorResource(name: "BackgroundColor", bundle: resourceBundle)

    /// The "DarkPrimary" asset catalog color resource.
    static let darkPrimary = DeveloperToolsSupport.ColorResource(name: "DarkPrimary", bundle: resourceBundle)

    /// The "TertiaryColor" asset catalog color resource.
    static let tertiary = DeveloperToolsSupport.ColorResource(name: "TertiaryColor", bundle: resourceBundle)

    /// The "TextColor" asset catalog color resource.
    static let text = DeveloperToolsSupport.ColorResource(name: "TextColor", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "DemoPhoto" asset catalog image resource.
    static let demoPhoto = DeveloperToolsSupport.ImageResource(name: "DemoPhoto", bundle: resourceBundle)

}


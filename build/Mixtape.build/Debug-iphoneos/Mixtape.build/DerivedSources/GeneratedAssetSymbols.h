#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.dev.mixtape";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "BackgroundColor" asset catalog color resource.
static NSString * const ACColorNameBackgroundColor AC_SWIFT_PRIVATE = @"BackgroundColor";

/// The "DarkPrimary" asset catalog color resource.
static NSString * const ACColorNameDarkPrimary AC_SWIFT_PRIVATE = @"DarkPrimary";

/// The "TertiaryColor" asset catalog color resource.
static NSString * const ACColorNameTertiaryColor AC_SWIFT_PRIVATE = @"TertiaryColor";

/// The "TextColor" asset catalog color resource.
static NSString * const ACColorNameTextColor AC_SWIFT_PRIVATE = @"TextColor";

/// The "DemoPhoto" asset catalog image resource.
static NSString * const ACImageNameDemoPhoto AC_SWIFT_PRIVATE = @"DemoPhoto";

#undef AC_SWIFT_PRIVATE

#import "SbpLauncherPlugin.h"
#if __has_include(<sbp_launcher/sbp_launcher-Swift.h>)
#import <sbp_launcher/sbp_launcher-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "sbp_launcher-Swift.h"
#endif

@implementation SbpLauncherPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftSbpLauncherPlugin registerWithRegistrar:registrar];
}
@end

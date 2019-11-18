#import <UIKit/UIKit.h>
#import "React/RCTBridgeModule.h"

@interface ReactNativeShareExtension : UIViewController<RCTBridgeModule>
/**
* Create a shareView using a common RCTBridge. The RCTBridge is reused
* for each launch of the share sheet. This allows the share sheet to
* free its resources in between launches.
*/
- (UIView*) shareView:(RCTBridge*)sharedBridge;
+ (NSString*) type;
+ (NSString*) value;
- (RCTBridge*) createBridge;
@end

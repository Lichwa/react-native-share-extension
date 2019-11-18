#import "ReactNativeShareExtension.h"
#import "React/RCTRootView.h"
#import <React/RCTImageLoader.h>
#import <React/RCTBundleURLProvider.h>
#import <MobileCoreServices/MobileCoreServices.h>

#define URL_IDENTIFIER @"public.url"
#define IMAGE_IDENTIFIER @"public.image"
#define TEXT_IDENTIFIER (NSString *)kUTTypePlainText

NSExtensionContext* extensionContext;
static NSString* type;
static NSString* value;

// Save a copy of the RCTBridge to reuse. Creating a new bridge
// each time this saves mempory.
RCTBridge *sharedBridge;

@implementation ReactNativeShareExtension

@synthesize bridge = _bridge;

- (UIView*) shareView {
    return nil;
}

RCT_EXPORT_MODULE();

- (RCTBridge*) createBridge {
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    extensionContext = self.extensionContext;
    
    [self extractDataFromContext: extensionContext withCallback:^(NSString* val, NSString* contentType, NSException* err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (sharedBridge) {
                [sharedBridge invalidate];
                sharedBridge = nil;
            }

            sharedBridge = [self createBridge];

            self.view = [self shareView:sharedBridge];
        });
    }];
}


RCT_EXPORT_METHOD(close) {
    [extensionContext completeRequestReturningItems:nil
                                  completionHandler:nil];
    [sharedBridge invalidate];
    sharedBridge = nil;
    self.view = nil;
}

RCT_REMAP_METHOD(data,
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    resolve(@{
        @"type": type,
        @"value": value
    });
}

bool _saveImage(NSString * fullPath, UIImage * image)
{
    NSData* data = UIImageJPEGRepresentation(image, 0.9);
    
    if (data == nil) {
        return NO;
    }
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    return [fileManager createFileAtPath:fullPath contents:data attributes:nil];
}

NSString * _generateFilePath(NSString * ext, NSString * outputPath)
{
    NSString* directory;

    if ([outputPath length] == 0) {
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        directory = [paths firstObject];
    } else {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        if ([outputPath hasPrefix:documentsDirectory]) {
            directory = outputPath;
        } else {
            directory = [documentsDirectory stringByAppendingPathComponent:outputPath];
        }
        
        NSError *error;
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) {
            NSLog(@"Error creating documents subdirectory: %@", error);
            @throw [NSException exceptionWithName:@"InvalidPathException" reason:[NSString stringWithFormat:@"Error creating documents subdirectory: %@", error] userInfo:nil];
        }
    }

    NSString* name = [[NSUUID UUID] UUIDString];
    NSString* fullName = [NSString stringWithFormat:@"%@.%@", name, ext];
    NSString* fullPath = [directory stringByAppendingPathComponent:fullName];

    return fullPath;
}

- (NSURL*)createResizedImage:(NSString *)path
{
    NSString *extension = @"jpg";
    NSURL* url = [NSURL URLWithString:path];
    CFURLRef cfurl = (__bridge CFURLRef)url;
    CGImageSourceRef imageSource = CGImageSourceCreateWithURL(cfurl, NULL);

    CFDictionaryRef options = (__bridge CFDictionaryRef)[NSDictionary dictionaryWithObjectsAndKeys:
        (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailWithTransform,
        (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailFromImageAlways,
        [NSNumber numberWithInt:1024], (id)kCGImageSourceThumbnailMaxPixelSize,
        nil];
    CGImageRef imgRef = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options);

    UIImage* scaled = [UIImage imageWithCGImage:imgRef];

    CGImageRelease(imgRef);
    CFRelease(imageSource);
    
    NSString* fullPath;
    fullPath = _generateFilePath(extension, nil);
    _saveImage(fullPath, scaled);
    NSURL *fileUrl = [[NSURL alloc] initFileURLWithPath:fullPath];

    return fileUrl;
}

- (void)extractDataFromContext:(NSExtensionContext *)context withCallback:(void(^)(NSString *value, NSString* contentType, NSException *exception))callback {
    @try {
        NSExtensionItem *item = [context.inputItems firstObject];
        NSArray *attachments = item.attachments;

        __block NSItemProvider *urlProvider = nil;
        __block NSItemProvider *imageProvider = nil;
        __block NSItemProvider *textProvider = nil;

        [attachments enumerateObjectsUsingBlock:^(NSItemProvider *provider, NSUInteger idx, BOOL *stop) {
            if([provider hasItemConformingToTypeIdentifier:URL_IDENTIFIER]) {
                urlProvider = provider;
                *stop = YES;
            } else if ([provider hasItemConformingToTypeIdentifier:TEXT_IDENTIFIER]){
                textProvider = provider;
                *stop = YES;
            } else if ([provider hasItemConformingToTypeIdentifier:IMAGE_IDENTIFIER]){
                imageProvider = provider;
                *stop = YES;
            }
        }];

        if(urlProvider) {
            [urlProvider loadItemForTypeIdentifier:URL_IDENTIFIER options:nil completionHandler:^(id<NSSecureCoding> item, NSError *error) {
                NSURL *url = (NSURL *)item;

                if(callback) {
                    callback([url absoluteString], @"text/plain", nil);
                }
            }];
        } else if (imageProvider) {
            [imageProvider loadItemForTypeIdentifier:IMAGE_IDENTIFIER options:nil completionHandler:^(id<NSSecureCoding> item, NSError *error) {
                NSURL *url = (NSURL *)item;

                if(callback) {
                    NSURL* fileUrl = [self createResizedImage: url.absoluteString];
                    value = [fileUrl absoluteString];
                    type = [[[fileUrl absoluteString] pathExtension] lowercaseString];
                    callback(value, type, nil);
                }
            }];
        } else if (textProvider) {
            [textProvider loadItemForTypeIdentifier:TEXT_IDENTIFIER options:nil completionHandler:^(id<NSSecureCoding> item, NSError *error) {
                NSString *text = (NSString *)item;

                if(callback) {
                    callback(text, @"text/plain", nil);
                }
            }];
        } else {
            if(callback) {
                callback(nil, nil, [NSException exceptionWithName:@"Error" reason:@"couldn't find provider" userInfo:nil]);
            }
        }
    }
    @catch (NSException *exception) {
        if(callback) {
            callback(nil, nil, exception);
        }
    }
}

@end

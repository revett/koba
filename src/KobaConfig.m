#import "KobaConfig.h"

static NSString *const KobaConfigErrorDomain = @"com.revcd.koba.config";

static NSError *KobaConfigError(NSString *message) {
    return [NSError errorWithDomain:KobaConfigErrorDomain
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey : message }];
}

@implementation KobaConfig

+ (NSString *)path {
    return [NSHomeDirectory()
        stringByAppendingPathComponent:@".config/koba/koba.json"];
}

+ (instancetype)loadWithError:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *path = [self path];

    if (![fm fileExistsAtPath:path]) {
        NSDictionary *defaults = @{ @"workingDirectories" : @[] };
        NSData *data = [NSJSONSerialization dataWithJSONObject:defaults
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:error];
        if (data == nil) return nil;
        if (![fm createDirectoryAtPath:path.stringByDeletingLastPathComponent
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:error]) return nil;
        if (![data writeToFile:path options:NSDataWritingAtomic error:error]) return nil;
    }

    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (data == nil) return nil;

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (json == nil) return nil;
    if (![json isKindOfClass:NSDictionary.class]) {
        if (error) *error = KobaConfigError(@"koba.json must contain a JSON object");
        return nil;
    }

    NSArray *directories = json[@"workingDirectories"];
    if (![directories isKindOfClass:NSArray.class]) {
        if (error) *error = KobaConfigError(
            @"koba.json requires \"workingDirectories\" (array of strings)");
        return nil;
    }
    for (id entry in directories) {
        if (![entry isKindOfClass:NSString.class]) {
            if (error) *error = KobaConfigError(
                @"\"workingDirectories\" entries must be strings");
            return nil;
        }
    }

    KobaConfig *config = [[KobaConfig alloc] init];
    config->_workingDirectories = [directories copy];
    return config;
}

@end

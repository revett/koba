#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Koba's configuration file: ~/.config/koba/koba.json. The file is required;
// a default one is written on first run. Loading fails hard on invalid JSON
// or a missing required key.
@interface KobaConfig : NSObject

// Directories that contain git repositories (e.g. "~/projects/github.com/acme").
@property (nonatomic, readonly) NSArray<NSString *> *workingDirectories;

+ (nullable instancetype)loadWithError:(NSError **)error;

+ (NSString *)path;

// Where workspace state is persisted between runs.
+ (NSString *)statePath;

@end

NS_ASSUME_NONNULL_END

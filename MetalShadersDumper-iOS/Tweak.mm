#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <dlfcn.h>
#import "SSZipArchive/SSZipArchive.h"
#import <objc/runtime.h>
#import "fishhook.h"

static id<MTLDevice> (*orig_MTLCreateSystemDefaultDevice)(void) = NULL;
static id (*orig_newLibraryWithSource)(id, SEL, NSString *, MTLCompileOptions *, NSError **) = NULL;
static NSUInteger shaderDumpCounter = 0;
static NSMutableArray<NSString *> *savedShadersPaths = nil;
static NSString* getCacheDumpFolder() {
    NSString *folder = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]
                        stringByAppendingPathComponent:@"MetalShadersDumped"];
    BOOL isDir = NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:folder isDirectory:&isDir] || !isDir) {
        NSError *error = nil;
        [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) NSLog(@"[MetalShadersDumped] Failed to create cache directory: %@", error);
    }
    return folder;
}
static NSString* generateShaderFilename(NSString *folder) {
    NSString *filePath;
    NSFileManager *fm = NSFileManager.defaultManager;
    do {
        filePath = [folder stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"shader_%03lu.metal", (unsigned long)shaderDumpCounter++]];
    } while ([fm fileExistsAtPath:filePath]);
    return filePath;
}
id hooked_newLibraryWithSource(id self, SEL _cmd, NSString *source, MTLCompileOptions *options, NSError **error) {
    NSLog(@"[MetalShadersDumped] Compiling shader source...");
    NSString *folder = getCacheDumpFolder();
    NSString *filePath = generateShaderFilename(folder);
    NSError *writeError = nil;
    if ([source writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        NSLog(@"[MetalShadersDumped] Saved shader source to %@", filePath);
        @synchronized(savedShadersPaths) {
            if (!savedShadersPaths) savedShadersPaths = [NSMutableArray new];
            [savedShadersPaths addObject:filePath];
        }
    } else {
        NSLog(@"[MetalShadersDumped] Failed to save shader source: %@", writeError);
    }
    return orig_newLibraryWithSource(self, _cmd, source, options, error);
}
id<MTLDevice> hooked_MTLCreateSystemDefaultDevice(void) {
    id<MTLDevice> device = orig_MTLCreateSystemDefaultDevice();
    if (device) {
        NSLog(@"[MetalShadersDumped] MTLCreateSystemDefaultDevice called, device: %@", device);
        Class cls = object_getClass(device);
        SEL sel = @selector(newLibraryWithSource:options:error:);
        Method m = class_getInstanceMethod(cls, sel);
        if (m && !orig_newLibraryWithSource) {
            orig_newLibraryWithSource = (id (*)(id, SEL, NSString *, MTLCompileOptions *, NSError **))method_getImplementation(m);
            method_setImplementation(m, (IMP)hooked_newLibraryWithSource);
            NSLog(@"[MetalShadersDumped] Hooked newLibraryWithSource on class %@", cls);
        }
    }
    return device;
}
@interface MetalShadersListViewController : UITableViewController
@property (nonatomic, strong) NSMutableArray<NSString *> *shadersPaths;
@property (nonatomic, strong) NSTimer *refreshTimer;
@end
@implementation MetalShadersListViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Metal Shaders Dumper";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Export All"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(exportAllShaders)]
    ];
    [self reloadShadersList];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                         target:self
                                                       selector:@selector(reloadShadersList)
                                                       userInfo:nil
                                                        repeats:YES];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"cell"];
}

- (void)dealloc {
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)reloadShadersList {
    NSString *folder = getCacheDumpFolder();
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:nil];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF ENDSWITH '.metal'"];
    NSArray *metalFiles = [files filteredArrayUsingPredicate:predicate];
    self.shadersPaths = [[metalFiles sortedArrayUsingComparator:^NSComparisonResult(NSString * obj1, NSString * obj2) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"shader_(\\d+)\\.metal" options:0 error:nil];
        NSTextCheckingResult *match1 = [regex firstMatchInString:obj1 options:0 range:NSMakeRange(0, obj1.length)];
        NSTextCheckingResult *match2 = [regex firstMatchInString:obj2 options:0 range:NSMakeRange(0, obj2.length)];
        NSInteger num1 = 0, num2 = 0;
        if (match1 && match1.numberOfRanges > 1) {
            NSString *numStr = [obj1 substringWithRange:[match1 rangeAtIndex:1]];
            num1 = numStr.integerValue;
        }
        if (match2 && match2.numberOfRanges > 1) {
            NSString *numStr = [obj2 substringWithRange:[match2 rangeAtIndex:1]];
            num2 = numStr.integerValue;
        }
        if (num1 < num2) return NSOrderedAscending;
        else if (num1 > num2) return NSOrderedDescending;
        else return NSOrderedSame;
    }] mutableCopy];
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.shadersPaths.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.textLabel.text = self.shadersPaths[indexPath.row];
    cell.textLabel.font = [UIFont systemFontOfSize:14];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *folder = getCacheDumpFolder();
    NSString *filePath = [folder stringByAppendingPathComponent:self.shadersPaths[indexPath.row]];
    NSError *err = nil;
    NSString *content = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&err];
    if (!content) content = [NSString stringWithFormat:@"Failed to load shader:\n%@", err];
    UIViewController *vc = [UIViewController new];
    vc.title = self.shadersPaths[indexPath.row];
    UITextView *tv = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.editable = NO;
    tv.text = content;
    tv.font = [UIFont systemFontOfSize:12];
    [vc.view addSubview:tv];
    UIBarButtonItem *exportButton = [[UIBarButtonItem alloc] initWithTitle:@"Export"
                                                                     style:UIBarButtonItemStylePlain
                                                                    target:self
                                                                    action:@selector(exportSingleShader:)];
    objc_setAssociatedObject(exportButton, "exportFilePath", filePath, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    vc.navigationItem.rightBarButtonItem = exportButton;

    [self.navigationController pushViewController:vc animated:YES];
}

- (void)exportSingleShader:(UIBarButtonItem *)sender {
    NSString *filePath = objc_getAssociatedObject(sender, "exportFilePath");
    if (!filePath) {
        NSLog(@"[MetalShadersDumped] No file path associated for export");
        return;
    }
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
        UIViewController *topVC = UIApplication.sharedApplication.keyWindow.rootViewController;
        while (topVC.presentedViewController) topVC = topVC.presentedViewController;

        if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            activityVC.popoverPresentationController.sourceView = topVC.view;
            activityVC.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width/2, topVC.view.bounds.size.height/4, 0, 0);
        }
        [topVC presentViewController:activityVC animated:YES completion:nil];
    });
}
- (void)exportAllShaders {
    NSString *cacheFolder = getCacheDumpFolder();
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject copy];
    NSString *zipPath = [docs stringByAppendingPathComponent:@"MetalShadersExport.zip"];
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:zipPath]) {
        NSError *removeError = nil;
        [fm removeItemAtPath:zipPath error:&removeError];
        if (removeError) NSLog(@"[MetalShadersDumped] Failed to remove old zip: %@", removeError);
    }
    BOOL success = [SSZipArchive createZipFileAtPath:zipPath withContentsOfDirectory:cacheFolder];
    if (success) {
        NSLog(@"[MetalShadersDumped] Created zip archive at %@", zipPath);
        NSURL *zipURL = [NSURL fileURLWithPath:zipPath];
        dispatch_async(dispatch_get_main_queue(), ^{
            UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[zipURL] applicationActivities:nil];
            UIViewController *topVC = UIApplication.sharedApplication.keyWindow.rootViewController;
            while (topVC.presentedViewController) topVC = topVC.presentedViewController;
            if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                activityVC.popoverPresentationController.sourceView = topVC.view;
                activityVC.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width/2, topVC.view.bounds.size.height/4, 0, 0);
            }
            activityVC.completionWithItemsHandler = ^(UIActivityType  _Nullable activityType, BOOL completed, NSArray * _Nullable returnedItems, NSError * _Nullable activityError) {
                NSError *zipDeleteError = nil;
                [fm removeItemAtPath:zipPath error:&zipDeleteError];
                if (zipDeleteError) {
                    NSLog(@"[MetalShadersDumped] Failed to delete zip archive: %@", zipDeleteError);
                } else {
                    NSLog(@"[MetalShadersDumped] Deleted zip archive after sharing");
                }
                NSError *deleteError = nil;
                NSArray *files = [fm contentsOfDirectoryAtPath:cacheFolder error:nil];
                for (NSString *file in files) {
                    NSString *filePath = [cacheFolder stringByAppendingPathComponent:file];
                    [fm removeItemAtPath:filePath error:&deleteError];
                    if (deleteError) {
                        NSLog(@"[MetalShadersDumped] Failed to delete file %@: %@", file, deleteError);
                    }
                }
                @synchronized(savedShadersPaths) {
                    [savedShadersPaths removeAllObjects];
                }
                NSLog(@"[MetalShadersDumped] Cleared cached shader files after export");
            };

            [topVC presentViewController:activityVC animated:YES completion:nil];
        });
    } else {
        NSLog(@"[MetalShadersDumped] Failed to create zip archive");
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                           message:@"Couldn't create archive"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            UIViewController *topVC = UIApplication.sharedApplication.keyWindow.rootViewController;
            while (topVC.presentedViewController) topVC = topVC.presentedViewController;
            [topVC presentViewController:alert animated:YES completion:nil];
        });
    }
}
- (void)closeTapped {
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
@interface MetalShadersDumperOverlay : NSObject
+ (void)addButton;
@end
@implementation MetalShadersDumperOverlay
+ (void)addButton {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = UIApplication.sharedApplication.keyWindow;
        if (!keyWindow) return;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(10, 50, 110, 40);
        button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        [button setTitle:@"Shaders List" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.layer.cornerRadius = 6;
        button.clipsToBounds = YES;
        button.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
        [button addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:button];
    });
}
+ (void)buttonTapped {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[MetalShadersListViewController new]];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    UIViewController *topVC = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    [topVC presentViewController:nav animated:YES completion:nil];
}
@end
__attribute__((constructor))
static void substrate_init() {
    NSLog(@"[MetalShadersDumper] substrate_init called");

    struct rebinding rebindings[] = {
        {"MTLCreateSystemDefaultDevice", (void *)hooked_MTLCreateSystemDefaultDevice, (void **)&orig_MTLCreateSystemDefaultDevice}
    };

    rebind_symbols(rebindings, 1);

    NSLog(@"[MetalShadersDumper] Hooked MTLCreateSystemDefaultDevice");
    [MetalShadersDumperOverlay addButton];
}

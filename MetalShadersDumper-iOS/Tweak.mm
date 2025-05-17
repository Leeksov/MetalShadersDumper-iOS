#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <dlfcn.h>

static id<MTLDevice> (*orig_MTLCreateSystemDefaultDevice)(void) = NULL;
static id (*orig_newLibraryWithSource)(id, SEL, NSString *, MTLCompileOptions *, NSError **) = NULL;

static NSString* getMetalDumpFolder() {
    NSString *folder = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
                        stringByAppendingPathComponent:@"MetalShadersDumped"];
    BOOL isDir = NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:folder isDirectory:&isDir] || !isDir) {
        NSError *error = nil;
        [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) NSLog(@"[MetalShadersDumped] Failed to create directory: %@", error);
    }
    return folder;
}

static NSString* generateShaderFilename(NSString *folder) {
    NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil];
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"SELF BEGINSWITH[c] %@", @"shader_"];
    NSArray *shaderFiles = [files filteredArrayUsingPredicate:pred];

    int maxNum = 0;
    for (NSString *f in shaderFiles) {
        int num = [[[[f lastPathComponent] stringByDeletingPathExtension] substringFromIndex:7] intValue];
        if (num > maxNum) maxNum = num;
    }
    return [folder stringByAppendingPathComponent:
            [NSString stringWithFormat:@"shader_%03d.metal", maxNum + 1]];
}

id hooked_newLibraryWithSource(id self, SEL _cmd, NSString *source, MTLCompileOptions *options, NSError **error) {
    NSLog(@"[MetalShadersDumped] Shader source:\n%@", source);

    NSString *folder = getMetalDumpFolder();
    NSString *filePath = generateShaderFilename(folder);
    NSError *writeError = nil;
    if ([source writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        NSLog(@"[MetalShadersDumped] Saved shader to %@", filePath);
    } else {
        NSLog(@"[MetalShadersDumped] Failed to save shader: %@", writeError);
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

__attribute__((constructor))
static void substrate_init() {
    NSLog(@"[MetalShadersDumped] substrate_init called");

    void *metal_handle = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_NOW);
    if (!metal_handle) {
        NSLog(@"[MetalShadersDumped] Failed to open Metal framework");
        return;
    }

    void *orig_func = dlsym(metal_handle, "MTLCreateSystemDefaultDevice");
    if (!orig_func) {
        NSLog(@"[MetalShadersDumped] Failed to find MTLCreateSystemDefaultDevice symbol");
        dlclose(metal_handle);
        return;
    }

    MSHookFunction(orig_func, (void *)hooked_MTLCreateSystemDefaultDevice, (void **)&orig_MTLCreateSystemDefaultDevice);
    NSLog(@"[MetalShadersDumped] Hooked MTLCreateSystemDefaultDevice");
    dlclose(metal_handle);
}

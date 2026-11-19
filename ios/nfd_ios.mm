// ios/nfd_ios.mm
// Collega l'Installer Wizard originale di FoxWorkshop/ShadowRecomp (NFD_OpenDialogU8 / NFD_PickFolderU8)
// direttamente all'App File nativa di iOS (UIDocumentPickerViewController).
// Al primo avvio su iPhone 16 Pro, l'utente può selezionare la propria ISO Xbox o cartella estratta in 1 tap.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <nfd.h>
#include <cstdlib>
#include <cstring>
#include <string>

static std::string g_lastNfdError;

@interface ShadowDocumentPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@property (nonatomic, copy) NSString *selectedPath;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL pickFolder;
@end

@implementation ShadowDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) {
        self.cancelled = YES;
        self.finished = YES;
        if (self.semaphore) dispatch_semaphore_signal(self.semaphore);
        return;
    }

    BOOL accessed = [url startAccessingSecurityScopedResource];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *docs = [[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *importDir = [docs URLByAppendingPathComponent:@"ShadowRecomp/imports" isDirectory:YES];
    [fm createDirectoryAtURL:importDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSURL *destURL = [importDir URLByAppendingPathComponent:url.lastPathComponent];
    [fm removeItemAtURL:destURL error:nil];

    NSError *copyErr = nil;
    // Copia (o linka se già nella sandbox App File) così ShadowRecomp C++ può leggerlo senza scadenza permessi
    if ([url.path hasPrefix:docs.path]) {
        self.selectedPath = url.path;
    } else if ([fm copyItemAtURL:url toURL:destURL error:&copyErr]) {
        self.selectedPath = destURL.path;
    } else {
        // Fallback: prova accesso diretto al path security-scoped
        self.selectedPath = url.path;
    }

    if (accessed) {
        [url stopAccessingSecurityScopedResource];
    }
    self.cancelled = NO;
    self.finished = YES;
    if (self.semaphore) dispatch_semaphore_signal(self.semaphore);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.cancelled = YES;
    self.finished = YES;
    if (self.semaphore) dispatch_semaphore_signal(self.semaphore);
}

@end

static UIViewController* GetTopViewController(void) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) { keyWindow = w; break; }
            }
            if (!keyWindow) keyWindow = ws.windows.firstObject;
        }
    }
    UIViewController *top = keyWindow.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    return top;
}

static ShadowDocumentPickerDelegate *g_activePickerDelegate = nil;

static nfdresult_t PresentIOSFilesPicker(nfdu8char_t** outPath, BOOL folderMode) {
    if (!outPath) {
        g_lastNfdError = "outPath is null";
        return NFD_ERROR;
    }
    *outPath = nullptr;

    ShadowDocumentPickerDelegate *delegate = [[ShadowDocumentPickerDelegate alloc] init];
    delegate.pickFolder = folderMode;
    delegate.cancelled = YES;
    delegate.finished = NO;
    g_activePickerDelegate = delegate;

    void (^presentBlock)(void) = ^{
        UIViewController *presenter = GetTopViewController();
        if (!presenter) {
            g_lastNfdError = "No active UIViewController to present Files app";
            delegate.finished = YES;
            if (delegate.semaphore) dispatch_semaphore_signal(delegate.semaphore);
            return;
        }

        NSArray<UTType *> *types = folderMode
            ? @[UTTypeFolder]
            : @[UTTypeItem, UTTypeData, UTTypeDiskImage, UTTypeArchive];

        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:NO];
        picker.delegate = delegate;
        picker.allowsMultipleSelection = NO;
        picker.modalPresentationStyle = UIModalPresentationFormSheet;
        [presenter presentViewController:picker animated:YES completion:nil];
    };

    if ([NSThread isMainThread]) {
        presentBlock();
        while (!delegate.finished) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    } else {
        delegate.semaphore = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_main_queue(), presentBlock);
        dispatch_semaphore_wait(delegate.semaphore, DISPATCH_TIME_FOREVER);
    }

    NSString *resultPath = delegate.selectedPath;
    BOOL wasCancelled = delegate.cancelled;
    g_activePickerDelegate = nil;

    if (wasCancelled || resultPath.length == 0) {
        return NFD_CANCEL;
    }

    const char* utf8 = resultPath.UTF8String;
    *outPath = static_cast<nfdu8char_t*>(std::malloc(std::strlen(utf8) + 1));
    std::strcpy(*outPath, utf8);
    return NFD_OKAY;
}

extern "C" {

nfdresult_t NFD_Init(void) { return NFD_OKAY; }
void NFD_Quit(void) {}

nfdresult_t NFD_OpenDialogU8(nfdu8char_t** outPath, const nfdu8filteritem_t*, nfdfiltersize_t, const nfdu8char_t*) {
    return PresentIOSFilesPicker(outPath, NO);
}

nfdresult_t NFD_PickFolderU8(nfdu8char_t** outPath, const nfdu8char_t*) {
    return PresentIOSFilesPicker(outPath, YES);
}

void NFD_FreePathU8(nfdu8char_t* filePath) {
    std::free(filePath);
}

const char* NFD_GetError(void) {
    return g_lastNfdError.c_str();
}

}
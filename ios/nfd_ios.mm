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

@interface ShadowDocumentPickerDelegate : NSObject <UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@property (nonatomic, copy) NSString *selectedPath;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL pickFolder;
@property (nonatomic, assign) BOOL usedCopyMode;
@end

@implementation ShadowDocumentPickerDelegate

- (void)finishWithPath:(NSString *)path cancelled:(BOOL)cancelled {
    if (self.finished) return;
    self.selectedPath = path;
    self.cancelled = cancelled;
    self.finished = YES;
    if (self.semaphore) dispatch_semaphore_signal(self.semaphore);
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) {
        [self finishWithPath:nil cancelled:YES];
        return;
    }

    BOOL accessed = [url startAccessingSecurityScopedResource];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *docs = [[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *importDir = [docs URLByAppendingPathComponent:@"ShadowRecomp/imports" isDirectory:YES];
    [fm createDirectoryAtURL:importDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSURL *destURL = [importDir URLByAppendingPathComponent:url.lastPathComponent];
    NSString *resolvedPath = nil;

    // 1. Se il file/cartella è già dentro Documents dell'app, usalo direttamente senza duplicarlo
    if ([url.path hasPrefix:docs.path]) {
        resolvedPath = url.path;
    } else {
        [fm removeItemAtURL:destURL error:nil];
        NSError *fsErr = nil;
        // 2. Con asCopy:YES iOS ha già creato un clone APFS temporaneo nell'inbox dell'app:
        //    moveItemAtURL è O(1) istantaneo e non raddoppia lo spazio su disco per ISO da 1.5 GB.
        if (self.usedCopyMode && !self.pickFolder && [fm moveItemAtURL:url toURL:destURL error:&fsErr]) {
            resolvedPath = destURL.path;
        } else if ([fm copyItemAtURL:url toURL:destURL error:&fsErr]) {
            resolvedPath = destURL.path;
        } else {
            // Fallback: percorso diretto security-scoped
            resolvedPath = url.path;
        }
    }

    if (accessed) {
        [url stopAccessingSecurityScopedResource];
    }
    [self finishWithPath:resolvedPath cancelled:(resolvedPath.length == 0)];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self finishWithPath:nil cancelled:YES];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    [self finishWithPath:nil cancelled:YES];
}

@end

static UIViewController* GetTopViewController(void) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (![ws.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) continue;
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

static NSArray<NSURL *> *ScanLocalDocumentsCandidates(void) {
    NSMutableArray<NSURL *> *found = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *docs = [[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    if (!docs) return found;

    NSArray<NSURL *> *dirs = @[
        docs,
        [docs URLByAppendingPathComponent:@"ShadowRecomp" isDirectory:YES]
    ];
    for (NSURL *dir in dirs) {
        NSArray<NSURL *> *items = [fm contentsOfDirectoryAtURL:dir
                                    includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                       options:NSDirectoryEnumerationSkipsHiddenFiles
                                                         error:nil];
        for (NSURL *item in items) {
            NSNumber *isDir = nil;
            [item getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
            if (isDir.boolValue) continue;
            NSString *ext = item.pathExtension.lowercaseString;
            if ([ext isEqualToString:@"iso"] || [ext isEqualToString:@"xiso"] || [ext isEqualToString:@"xbe"]) {
                [found addObject:item];
            }
        }
    }
    return found;
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
    delegate.usedCopyMode = !folderMode;
    g_activePickerDelegate = delegate;

    void (^presentSystemPicker)(UIViewController *) = ^(UIViewController *presenter) {
        // Per i file usiamo asCopy:YES (modalità Import, equivalente moderno al picker legacy):
        // funziona su Feather/SideStore con qualsiasi certificato senza richiedere permessi open-in-place
        // e sfrutta il clone APFS istantaneo. Per le cartelle iOS richiede asCopy:NO.
        NSArray<UTType *> *types = folderMode
            ? @[UTTypeFolder]
            : @[UTTypeData, UTTypeContent, UTTypeDiskImage, UTTypeArchive];

        UIDocumentPickerViewController *picker =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:(!folderMode)];
        picker.delegate = delegate;
        picker.allowsMultipleSelection = NO;
        picker.shouldShowFileExtensions = YES;
        picker.modalPresentationStyle = UIModalPresentationFullScreen;
        picker.presentationController.delegate = delegate;
        [presenter presentViewController:picker animated:YES completion:nil];
    };

    void (^presentBlock)(void) = ^{
        UIViewController *presenter = GetTopViewController();
        if (!presenter) {
            g_lastNfdError = "No active UIViewController to present Files app";
            [delegate finishWithPath:nil cancelled:YES];
            return;
        }

        // Se l'utente ha copiato una .iso/.xiso/.xbe in "Su iPhone -> ShadowRecomp",
        // offri la selezione istantanea in-app (zero dipendenza dal picker XPC) oltre ad App File.
        NSArray<NSURL *> *localCandidates = folderMode ? @[] : ScanLocalDocumentsCandidates();
        if (localCandidates.count > 0) {
            UIAlertController *sheet =
                [UIAlertController alertControllerWithTitle:@"Seleziona file di gioco"
                                                    message:@"Trovati file nella cartella Su iPhone → ShadowRecomp"
                                             preferredStyle:UIAlertControllerStyleAlert];
            for (NSURL *candidate in localCandidates) {
                [sheet addAction:[UIAlertAction actionWithTitle:candidate.lastPathComponent
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(__unused UIAlertAction *action) {
                    [delegate finishWithPath:candidate.path cancelled:NO];
                }]];
            }
            [sheet addAction:[UIAlertAction actionWithTitle:@"Sfoglia App File di iOS..."
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(__unused UIAlertAction *action) {
                UIViewController *p = GetTopViewController();
                if (p) {
                    presentSystemPicker(p);
                } else {
                    [delegate finishWithPath:nil cancelled:YES];
                }
            }]];
            [sheet addAction:[UIAlertAction actionWithTitle:@"Annulla"
                                                      style:UIAlertActionStyleCancel
                                                    handler:^(__unused UIAlertAction *action) {
                [delegate finishWithPath:nil cancelled:YES];
            }]];
            [presenter presentViewController:sheet animated:YES completion:nil];
            return;
        }

        presentSystemPicker(presenter);
    };

    if ([NSThread isMainThread]) {
        presentBlock();
        while (!delegate.finished) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
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
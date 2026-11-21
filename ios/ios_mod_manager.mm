// ios/ios_mod_manager.mm
// Menu Mod Manager nativo iOS ispirato a DevZer0D4Y/MarathonRecompilediOS (ui/ios_mod_manager.mm)
// Scrive nel formato REALE letto da FoxWorkshop/ShadowRecomp/mod/mod_loader.cpp:
//   <GamePath>/mods/.modloader/profiles/profiles.json
//   <GamePath>/mods/.modloader/profiles/Default.json  -> { "EnabledMods": [ ... ] }
// Permette di importare cartelle mod (con mod.ini) direttamente dall'App File di iOS.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <string>
#include <string_view>
#include <vector>
#include <nlohmann/json.hpp>
#include <user/paths.h>

namespace ShadowIOS {

struct ModEntry {
    std::string folderName;
    std::string title;
    std::string author;
    bool enabled = false;
};

static std::filesystem::path GetModsRoot() {
    auto modsDir = GetGamePath() / "mods";
    std::error_code ec;
    std::filesystem::create_directories(modsDir / ".modloader" / "profiles", ec);
    return modsDir;
}

static std::vector<std::string> ReadEnabledMods() {
    std::vector<std::string> enabled;
    auto defaultProfile = GetModsRoot() / ".modloader" / "profiles" / "Default.json";
    if (!std::filesystem::exists(defaultProfile)) return enabled;
    try {
        std::ifstream ifs(defaultProfile);
        auto j = nlohmann::json::parse(ifs);
        if (j.contains("EnabledMods") && j["EnabledMods"].is_array()) {
            for (const auto& item : j["EnabledMods"]) {
                enabled.push_back(item.get<std::string>());
            }
        }
    } catch (...) {}
    return enabled;
}

static void SaveShadowRecompProfiles(const std::vector<ModEntry>& mods) {
    auto profilesDir = GetModsRoot() / ".modloader" / "profiles";
    std::error_code ec;
    std::filesystem::create_directories(profilesDir, ec);

    nlohmann::json profilesList = {
        {"ProfileIndex", 0},
        {"ProfilesList", {{{"Name", "Default"}, {"Filename", "Default.json"}}}}
    };
    {
        std::ofstream ofs(profilesDir / "profiles.json");
        ofs << profilesList.dump(2);
    }

    nlohmann::json enabledArr = nlohmann::json::array();
    for (const auto& m : mods) {
        if (m.enabled) enabledArr.push_back(m.folderName);
    }
    nlohmann::json defaultProfile = { {"EnabledMods", enabledArr} };
    {
        std::ofstream ofs(profilesDir / "Default.json");
        ofs << defaultProfile.dump(2);
    }
}

static std::vector<ModEntry> ScanInstalledMods() {
    std::vector<ModEntry> result;
    auto enabledList = ReadEnabledMods();
    auto modsRoot = GetModsRoot();
    if (!std::filesystem::exists(modsRoot)) return result;

    for (const auto& entry : std::filesystem::directory_iterator(modsRoot)) {
        if (!entry.is_directory()) continue;
        std::string folder = entry.path().filename().string();
        if (folder == ".modloader") continue;

        ModEntry m;
        m.folderName = folder;
        m.title = folder;
        m.author = "Community";
        m.enabled = std::find(enabledList.begin(), enabledList.end(), folder) != enabledList.end();

        auto iniPath = entry.path() / "mod.ini";
        if (std::filesystem::exists(iniPath)) {
            std::ifstream ifs(iniPath);
            std::string line;
            while (std::getline(ifs, line)) {
                auto eq = line.find('=');
                if (eq == std::string::npos) continue;
                std::string key = line.substr(0, eq);
                std::string val = line.substr(eq + 1);
                if (key.find("Title") != std::string::npos || key.find("Name") != std::string::npos) m.title = val;
                if (key.find("Author") != std::string::npos) m.author = val;
            }
        }
        result.push_back(m);
    }
    return result;
}

} // namespace ShadowIOS

@interface ShadowModManagerViewController : UITableViewController <UIDocumentPickerDelegate>
@property (nonatomic, assign) std::vector<ShadowIOS::ModEntry> *modsPtr;
@end

@implementation ShadowModManagerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ShadowRecomp Mod Manager";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.modsPtr = new std::vector<ShadowIOS::ModEntry>(ShadowIOS::ScanInstalledMods());

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(closeManager)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Importa Mod"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(importModFolder)];
}

- (void)dealloc {
    delete self.modsPtr;
}

- (void)closeManager {
    ShadowIOS::SaveShadowRecompProfiles(*self.modsPtr);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)importModFolder {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *src = urls.firstObject;
    if (!src) return;
    BOOL scoped = [src startAccessingSecurityScopedResource];
    NSString *destRoot = [NSString stringWithUTF8String:ShadowIOS::GetModsRoot().c_str()];
    NSURL *dst = [[NSURL fileURLWithPath:destRoot isDirectory:YES] URLByAppendingPathComponent:src.lastPathComponent];
    [[NSFileManager defaultManager] removeItemAtURL:dst error:nil];
    [[NSFileManager defaultManager] copyItemAtURL:src toURL:dst error:nil];
    if (scoped) [src stopAccessingSecurityScopedResource];

    *self.modsPtr = ShadowIOS::ScanInstalledMods();
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.modsPtr->size();
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ModCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ModCell"];
    const auto& mod = (*self.modsPtr)[(size_t)indexPath.row];
    cell.textLabel.text = [NSString stringWithUTF8String:mod.title.c_str()];
    cell.detailTextLabel.text = [NSString stringWithUTF8String:mod.author.c_str()];
    cell.accessoryType = mod.enabled ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    auto& mod = (*self.modsPtr)[(size_t)indexPath.row];
    mod.enabled = !mod.enabled;
    ShadowIOS::SaveShadowRecompProfiles(*self.modsPtr);
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end

extern "C" void ShadowIOS_PresentModManager(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWin = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)s;
                if (![ws.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) continue;
                keyWin = ws.windows.firstObject;
                if (keyWin) break;
            }
        }
        UIViewController *root = keyWin.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        if (!root) return;
        ShadowModManagerViewController *vc = [[ShadowModManagerViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        [root presentViewController:nav animated:YES completion:nil];
    });
}
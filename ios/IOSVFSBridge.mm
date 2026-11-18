#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#include <filesystem>
#include <string>
#include <vector>

namespace ShadowRecomp::iOS {

std::filesystem::path GetDocumentsRoot() {
    NSArray<NSURL *> *paths = [[NSFileManager defaultManager]
        URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
    return std::filesystem::path([[paths firstObject] fileSystemRepresentation]);
}

std::filesystem::path ResolveXboxFile(const std::string& rawXboxPath, const std::vector<std::string>& activeModFolders) {
    std::string rel = rawXboxPath;
    if (rel.rfind("D:\\", 0) == 0 || rel.rfind("d:\\", 0) == 0) {
        rel = rel.substr(3);
    }
    std::replace(rel.begin(), rel.end(), '\\', '/');

    auto docs = GetDocumentsRoot();
    for (const auto& modFolder : activeModFolders) {
        auto candidate = docs / "Mods" / modFolder / rel;
        if (std::filesystem::exists(candidate)) {
            return candidate;
        }
    }

    return docs / "GameData" / rel;
}

} // namespace ShadowRecomp::iOS

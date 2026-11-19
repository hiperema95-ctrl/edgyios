// ios/include/nfd.h
// Drop-in header compatibile con nativefiledialog-extended per ShadowRecomp/ui/installer_wizard.cpp
#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef char nfdchar_t;
typedef char nfdu8char_t;
typedef size_t nfdfiltersize_t;

typedef struct {
    const nfdu8char_t* name;
    const nfdu8char_t* spec;
} nfdu8filteritem_t;

typedef nfdu8filteritem_t nfdfilteritem_t;

typedef enum {
    NFD_ERROR,
    NFD_OKAY,
    NFD_CANCEL
} nfdresult_t;

nfdresult_t NFD_Init(void);
void NFD_Quit(void);
nfdresult_t NFD_OpenDialogU8(nfdu8char_t** outPath, const nfdu8filteritem_t* filterList, nfdfiltersize_t filterCount, const nfdu8char_t* defaultPath);
nfdresult_t NFD_PickFolderU8(nfdu8char_t** outPath, const nfdu8char_t* defaultPath);
void NFD_FreePathU8(nfdu8char_t* filePath);
const char* NFD_GetError(void);

#ifdef __cplusplus
}
#endif
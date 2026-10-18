// SPDX-FileCopyrightText: Copyright 2024 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#include <ft2build.h>
#include FT_FREETYPE_H

#include "prx/libSceFontFt/include/FontFtDriver.hpp"
#include "prx/libc/include/General.hpp"

#pragma GCC visibility push(default)

extern "C" {

const Font::SysDriver* APS5_VABI sceFontSelectLibraryFt(int value) {
    return value == 0 ? FontFt::DriverTable() : nullptr;
}

const Font::RendererSelection* APS5_VABI sceFontSelectRendererFt(int value) {
    return value == 0 ? FontFt::RendererTable() : nullptr;
}

int APS5_VABI sceFontFtInitAliases() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceFontFtSetAliasFont() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceFontFtSetAliasPath() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceFontFtSupportBdf(FontLibrary library) {
    return FontFt::SupportModules(library, {"bdf"});
}

int APS5_VABI sceFontFtSupportCid(FontLibrary library) {
    return FontFt::SupportModules(library, {"t1cid"});
}

int APS5_VABI sceFontFtSupportFontFormats(FontLibrary library) {
    return FontFt::SupportModules(library, {"truetype", "cff", "type1", "t1cid", "type42", "pfr", "winfonts", "pcf", "bdf"});
}

int APS5_VABI sceFontFtSupportOpenType(FontLibrary library) {
    return FontFt::SupportModules(library, {"truetype", "cff"});
}

int APS5_VABI sceFontFtSupportOpenTypeOtf(FontLibrary library) {
    return FontFt::SupportModules(library, {"cff"});
}

int APS5_VABI sceFontFtSupportOpenTypeTtf(FontLibrary library) {
    return FontFt::SupportModules(library, {"truetype"});
}

int APS5_VABI sceFontFtSupportPcf(FontLibrary library) {
    return FontFt::SupportModules(library, {"pcf"});
}

int APS5_VABI sceFontFtSupportPfr(FontLibrary library) {
    return FontFt::SupportModules(library, {"pfr"});
}

int APS5_VABI sceFontFtSupportSystemFonts(FontLibrary library) {
    return FontFt::SupportModules(library, {"truetype", "cff"});
}

int APS5_VABI sceFontFtSupportTrueType(FontLibrary library) {
    return FontFt::SupportModules(library, {"truetype"});
}

int APS5_VABI sceFontFtSupportTrueTypeGx(FontLibrary library) {
#ifdef TT_CONFIG_OPTION_GX_VAR_SUPPORT
    return FontFt::SupportModules(library, {"truetype"});
#else
    const int rc = FontFt::SupportModules(library, {});
    return rc == SCE_FONT_OK ? SCE_FONT_ERROR_NO_SUPPORT_FORMAT : rc;
#endif
}

int APS5_VABI sceFontFtSupportType1(FontLibrary library) {
    return FontFt::SupportModules(library, {"type1"});
}

int APS5_VABI sceFontFtSupportType42(FontLibrary library) {
    return FontFt::SupportModules(library, {"type42"});
}

int APS5_VABI sceFontFtSupportWinFonts(FontLibrary library) {
    return FontFt::SupportModules(library, {"winfonts"});
}

int APS5_VABI sceFontFtTermAliases() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

int APS5_VABI sceFontSelectGlyphsFt() {
    NotImplemented_nid_no_patch(__func__);
    return 0;
}

}

#pragma GCC visibility pop

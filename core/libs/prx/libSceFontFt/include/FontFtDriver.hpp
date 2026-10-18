// SPDX-FileCopyrightText: Copyright 2024 shadPS4 Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

#ifndef CORE_LIBS_PRX_LIBSCEFONTFT_INCLUDE_FONTFTDRIVER_HPP
#define CORE_LIBS_PRX_LIBSCEFONTFT_INCLUDE_FONTFTDRIVER_HPP

#include <initializer_list>

#include "prx/libSceFont/include/FontDriver.hpp"

namespace FontFt {

const Font::SysDriver* DriverTable();
const Font::RendererSelection* RendererTable();
// Checks that the library was created from the FreeType driver and that its FreeType instance has
// every listed module (FreeType module names: "truetype", "cff", "type1"...).
int SupportModules(void* library, std::initializer_list<const char*> modules);

}

#endif

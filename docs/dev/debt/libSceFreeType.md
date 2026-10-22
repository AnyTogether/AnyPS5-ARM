# libSceFreeType technical debt

### Unknown function info

- [FT_Select_Charmap, FT_Set_Charmap, FT_Get_First_Char and FT_Get_Next_Char](../../../core/libs/prx/libSceFreeType/Export.cpp) (libSceFreeType) - console signatures and errors are unverified; the LP64 guest adapter follows the bundled [FreeType 2.13.3](https://github.com/freetype/freetype/blob/42608f77f20749dd6ddc9e0536788eaad70ea4b5/src/base/ftobjs.c). Character iteration uses the low 32 bits of the input code, as that version does internally, and updates the guest's selected charmap pointer without refreshing unrelated glyph or outline data. Guest charmap fields are treated as read-only copies of the native records.

- [FT_Init_FreeType, FT_New_Face, FT_Set_Pixel_Sizes, FT_Get_Char_Index, FT_Load_Glyph, FT_Render_Glyph](../../../core/libs/prx/libSceFreeType/Export.cpp) (libSceFreeType) - the PS4 library is taken to be FreeType 2 built for LP64: the face, size, charmap, glyph slot, bitmap and outline layouts follow the public headers of the bundled FreeType 2.13.3 with a 64-bit `long`, which matches the offsets the OpenOrbis samples read (`face->glyph` at 0x98, `slot->advance` at 0x80, `slot->bitmap` at 0x98, `slot->bitmap_left` at 0xc0). Which FreeType version and options the console library is built with is unknown, so the behaviour and error codes are those of FreeType 2.13.3. The OpenOrbis font, keyboard, threading, system and SDL2 samples import these six functions

- [FT_New_Memory_Face, FT_Done_Face and FT_Done_FreeType](../../../core/libs/prx/libSceFreeType/Export.cpp) (libSceFreeType) - console signatures, errors and generic-finalizer ordering are unverified; they follow the bundled [FreeType 2.13.3](https://github.com/freetype/freetype/blob/42608f77f20749dd6ddc9e0536788eaad70ea4b5/include/freetype/freetype.h) with LP64 guest arguments. Caller-owned font bytes must remain valid until the face is freed.

### Functional

- [libSceFreeType](../../../core/libs/prx/libSceFreeType/src/GuestObjects.cpp) (libSceFreeType) - private fields (`driver`, `memory`, `stream`, `sizes_list`, `extensions`) and `subglyphs` stay null. Face, size and glyph-slot records are copies. Only edits to outline points and flags are written back before `FT_Render_Glyph`; replacing arrays or exceeding the host `FT_Pos` range throws. `FT_New_Face` reads the whole file into memory and throws for files of 2 GiB or more on Windows. On macOS, native FreeType symbols remain exported and could resolve guest imports without adaptation; Windows and Linux hide them with `--exclude-libs`.

- [FT_New_Memory_Face](../../../core/libs/prx/libSceFreeType/Export.cpp) (libSceFreeType) - on Windows, the host FT_Long is 32 bits, so buffer sizes of 2 GiB or more or below -2 GiB throw before the font buffer is read

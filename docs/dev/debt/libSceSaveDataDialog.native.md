# libSceSaveDataDialog.native technical debt

### Silent stubs

- [libSceSaveDataDialog.native](../../../core/libs/prx/libSceSaveDataDialog.native/Export.cpp) shows no UI and ignores progress values. Progress-bar mode (5) stays running until the caller closes it, matching Skyrim PPSA03747's save sequence; other modes still finish immediately and return button 1 and the first nonempty directory name. Console dialog timing and selection behavior remain unverified.

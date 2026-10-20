# libScePlayGoDialog technical debt

### Unknown function info

- [scePlayGoDialogGetResult](../../../core/libs/prx/libScePlayGoDialog/Export.cpp) (libScePlayGoDialog) - checks that the dialog has reached STATUS_FINISHED and returns 0x80B80005 (COMMON_DIALOG_ERROR_NOT_FINISHED) when called before the dialog completes, following the other common dialog modules in the tree (MsgDialog, SigninDialog, PlayerSelectionDialog, SaveDataDialog). shadPS4's scePlayGoDialogGetResult is a dummy that always returns OK and provides no evidence for either value; the exact return code and intermediate state check have not been verified against a real hardware trace or title measurement.

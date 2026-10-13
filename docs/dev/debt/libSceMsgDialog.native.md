# libSceMsgDialog.native technical debt

### Silent stubs

- [libSceMsgDialog.native](../../../core/libs/prx/libSceMsgDialog.native/Export.cpp) - dialogs finish at `sceMsgDialogOpen` without UI and answer with button 1, so `sceMsgDialogClose` returns `NOT_RUNNING`; its result before `sceMsgDialogInitialize` follows libSceMsgDialog

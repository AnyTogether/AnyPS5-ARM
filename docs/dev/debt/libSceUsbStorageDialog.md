# libSceUsbStorageDialog technical debt

### Silent stubs

- [libSceUsbStorageDialog](../../../core/libs/prx/libSceUsbStorageDialog/Export.cpp) (libSceUsbStorageDialog) - the USB storage dialog runs the common-dialog state machine without showing a UI and reports the dialog as canceled by the user (`COMMON_DIALOG_RESULT_USER_CANCELED = 1`). `sceUsbStorageDialogOpen` transitions to `RUNNING` (2), while `sceUsbStorageDialogUpdateStatus` and `sceUsbStorageDialogClose` transition to `FINISHED` (3) before returning results, matching other common dialogs in the repository.

### Unknown function info

- [sceUsbStorageDialogGetResult](../../../core/libs/prx/libSceUsbStorageDialog/Export.cpp) (libSceUsbStorageDialog) - `SceUsbStorageDialogResult` full layout, size and additional fields are unverified across open references (KytyPS5, shadPS4, fpPS4, SharpProspero); only the 4-byte `result` field (`COMMON_DIALOG_RESULT_USER_CANCELED = 1`) is written to avoid guest memory corruption
- [sceUsbStorageDialogOpen, sceUsbStorageDialogClose](../../../core/libs/prx/libSceUsbStorageDialog/Export.cpp) (libSceUsbStorageDialog) - the relative validation precedence between uninitialized state, busy/running state, and null parameter checks is inferred from standard common dialog conventions and unverified against real console firmware

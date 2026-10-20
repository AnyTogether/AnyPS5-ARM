# libSceWebBrowserDialog technical debt

### Silent stubs

- [libSceWebBrowserDialog](../../../core/libs/prx/libSceWebBrowserDialog/Export.cpp) - `sceWebBrowserDialogOpen` and `sceWebBrowserDialogOpenForPredeterminedContent` run the common-dialog state machine without displaying an interactive browser, and `sceWebBrowserDialogGetResult` reports that the user cancelled. Minecraft Bedrock (PPSA17221) imports `sceWebBrowserDialogOpenForPredeterminedContent` (#5744). The real export takes a second argument, the allow-list of up to twenty addresses (SharpProspero `docs/dialogs.md`); it is not read here, so no address filtering is modelled, and the exact validation order and codes with a null second argument are unverified.
- [libSceWebBrowserDialog](../../../core/libs/prx/libSceWebBrowserDialog/Export.cpp) - `sceWebBrowserDialogClose` transitions an initialized dialog directly to `COMMON_DIALOG_STATUS_FINISHED` even when called before `Open`, following the Signin / NetCtlAp / PlayerSelection convention; this behavior is unverified against real hardware.

### Unknown function info

- [sceWebBrowserDialogGetEvent, sceWebBrowserDialogNavigate, sceWebBrowserDialogSetZoom](../../../core/libs/prx/libSceWebBrowserDialog/Export.cpp) (libSceWebBrowserDialog) - their names and NIDs are in the [PS5 3.20 export inventory](https://github.com/DNNDHH/PS5-3.20_Libs/blob/b2a77c09cd71c01f34c790cfbe98c751a13262ad/libSceWebBrowserDialog.c); the no-parameter prototypes follow [shadPS4 `webbrowserdialog.cpp`](https://github.com/shadps4-emu/shadPS4/blob/f68923fe807f657348e6719ce658bcbd0a2b1c72/src/core/libraries/web_browser_dialog/webbrowserdialog.cpp#L23-L85) and are not measured on a console. They are declared without parameters solely to resolve known imports; this is not an ABI claim, and every call throws.

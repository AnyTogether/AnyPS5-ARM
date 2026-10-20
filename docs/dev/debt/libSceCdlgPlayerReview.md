# libSceCdlgPlayerReview technical debt

### Unknown function info

- [scePlayerReviewDialogOpen, scePlayerReviewDialogGetResult](../../../core/libs/prx/libSceCdlgPlayerReview/Export.cpp) (libSceCdlgPlayerReview) - the PS5-only dialog has no public reference: the parameter is not read and the result is assumed to start with the 32-bit common dialog result, as `sceWebBrowserDialogGetResult` assumes
- [scePlayerReviewDialogClose](../../../core/libs/prx/libSceCdlgPlayerReview/Export.cpp) (libSceCdlgPlayerReview) - `scePlayerReviewDialogClose` moves an initialized dialog straight to `COMMON_DIALOG_STATUS_FINISHED` even when called before Open, as Signin, NetCtlAp and PlayerSelection do; MsgDialog.native, SaveDataDialog.native and ErrorDialog return an error there instead. Unverified against real hardware

### Functional

- [Player review dialog](../../../core/libs/prx/libSceCdlgPlayerReview/Export.cpp) (libSceCdlgPlayerReview) shows nothing: `scePlayerReviewDialogOpen` finishes at once and the result reports that the user canceled, as `sceWebBrowserDialogOpen` does

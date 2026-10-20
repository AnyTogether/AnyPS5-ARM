# libSceS3da technical debt

### Unknown function info

- [sceS3daClose, sceS3daGetInfo, sceS3daOpen and sceS3daSendData](../../../core/libs/prx/libSceS3da/Export.cpp) (libSceS3da) - names and NIDs are present in the [PS5 3.20 export inventory](https://github.com/DNNDHH/PS5-3.20_Libs/blob/b2a77c09cd71c01f34c790cfbe98c751a13262ad/libSceS3da.c), but no credible prototypes were found. The declarations have no parameters solely to resolve known imports; this is not an ABI claim and callers must not call them until signatures are verified

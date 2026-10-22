# libSceNpTrophy technical debt

### Unknown function info

- [sceNpTrophyRegisterContext, sceNpTrophyGetTrophyUnlockState, sceNpTrophyUnlockTrophy](../../../core/libs/prx/libSceNpTrophy/Export.cpp) (libSceNpTrophy, PS4) - the trophy definitions in `TROPCONF.ESFM` are encrypted, so the trophy count is the number of consecutive `TROPnnn.PNG` icons in the title's `/app0/sce_sys/trophy/trophyNN.trp`, and the calls that return names and details (`sceNpTrophyGetGameInfo`, `sceNpTrophyGetGroupInfo`, `sceNpTrophyGetTrophyInfo`) throw. Unlocks are kept per user and service label in `_trophy/trophyNN.<user id>` under the working directory, no platinum trophy is reported (`platinumId` is -1), and a locked trophy's icon fails with `TROPHY_NOT_UNLOCKED`. None of it is checked on a console.

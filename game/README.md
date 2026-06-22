# game

A working copy of the game's scripts, laid out to mirror the Roblox instance
tree. Edit modules here, then paste or sync them back into Studio. Folder paths
map directly to in-game paths:

| Folder path | In-game path |
|-------------|--------------|
| `ReplicatedStorage/Shared/<Name>.luau` | `game.ReplicatedStorage.Shared.<Name>` |

Each `.luau` file is a ModuleScript. Folders are plain Roblox folders.

## What's here so far

`ReplicatedStorage/Shared/`

- `Config.luau`
- `ScreenEffects.luau`
- `SoundController.luau`
- `TileDatabase.luau`
- `TileImages.luau`
- `TileRules.luau`

These are verbatim copies of what's in the game right now. The code has not
been edited.

## Notes

- Files use the `.luau` extension. If your Rojo setup expects `.lua`, say so and
  I'll rename them.
- More of the game is on the way. New scripts go under the folder that matches
  their service, for example `ServerScriptService/` or `StarterPlayer/`.

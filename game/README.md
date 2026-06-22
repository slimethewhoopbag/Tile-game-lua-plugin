# game

A working copy of the game's scripts, laid out to mirror the Roblox instance
tree. Edit here, then paste or sync back into Studio. Folder paths map directly
to in-game paths, for example `ServerScriptService/Modules/PathGenerator.luau`
is `game.ServerScriptService.Modules.PathGenerator`.

Folders are plain Roblox folders. The filename suffix sets the script class:

| Suffix | Roblox class |
|--------|--------------|
| `.luau` | ModuleScript |
| `.server.luau` | Script (server) |
| `.client.luau` | LocalScript |

## What's here so far

```
ReplicatedStorage/
  Shared/
    Config.luau                       ModuleScript
    ScreenEffects.luau                ModuleScript
    SoundController.luau              ModuleScript
    TileDatabase.luau                 ModuleScript
    TileImages.luau                   ModuleScript
    TileRules.luau                    ModuleScript
ServerScriptService/
  GameManager.server.luau             Script
  Modules/
    PathGenerator.luau                ModuleScript
    TilePlacer.luau                   ModuleScript
StarterPlayer/
  StarterPlayerScripts/
    TileVisualsClient.client.luau     LocalScript
```

These are verbatim copies of what's in the game right now. The code has not
been edited; only the file layout and the class suffixes were set.

## Notes

- Files use the `.luau` extension. If your Rojo setup expects `.lua`, say so and
  I'll rename them.
- `require` calls use in-game instance paths (such as
  `ReplicatedStorage:WaitForChild("Shared")`), so they are unaffected by this
  folder layout and need no changes.
- More of the game can drop in the same way. New scripts go under the folder
  that matches their service.
```

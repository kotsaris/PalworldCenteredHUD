# CenteredHUD Mod Repository

## What This Repo Is

Source of "CenteredHUD," a UE4SS Lua mod that centers Palworld's HUD on ultrawide (32:9) displays by narrowing widget anchor boxes. Developed and verified against Palworld 1.0 (Steam) + Okaetsu RE-UE4SS experimental-palworld, July 2026. The `reference-mods/` folder holds third-party mods used as API references (UltrawideFix demonstrates proven UE4SS Lua patterns; ResizeHUD shows Engine.ini ApplicationScale approach). `FINDINGS.md` contains the full technical investigation.

## Key Paths

- **Game**: `C:\Program Files (x86)\Steam\steamapps\common\Palworld`
- **Live mod install**: `<game>\Pal\Binaries\Win64\ue4ss\Mods\CenteredHUD` (enabled via `enabled.txt`, not listed in mods.txt)
- **UE4SS log** (only debug channel; GUI console disabled): `<game>\Pal\Binaries\Win64\ue4ss\UE4SS.log`
- **UE4SS settings**: `<game>\Pal\Binaries\Win64\ue4ss\UE4SS-settings.ini` (EnableHotReloadSystem=1, HotReloadKey=INS)
- **Vortex staging** (owns ue4ss deployment as hardlinks): `C:\Users\konst\AppData\Roaming\Vortex\palworld\mods\`

## Deploy Loop

1. Edit `CenteredHUD/Scripts/main.lua` or `config.lua` in this repo
2. Copy both files to the live install path
3. In-game: CTRL+INS hot-reloads Lua (CTRL is always required by UE4SS)
4. For config-only changes, just press F9 in-game to re-read config.lua
5. Bump the version tag in the final `log("vX.Y (...) loaded ...")` line on every code change so the log proves which build is running

## In-Game Keys

- **F6**: Toggle centered/vanilla
- **F8**: Dump widget tree to UE4SS.log (for discovering HUD widget classes)
- **F9**: Re-read config.lua without reloading (config-only changes)
- Reserved by other tools: F5/F7 (UltrawideFix), CTRL+J (UE4SS object dumper), F10/~ (ConsoleEnablerMod)

## Code Rules for main.lua

- Every game-object access wrapped in `pcall` AND executed via `ExecuteInGameThread`
- All log lines through the `log()` helper (includes `[CenteredHUD]` prefix); raw `print` must include the prefix manually
- Struct-field reads may return non-numeric `TrivialObject` userdata—coerce via `num()` helper; treat failures as "skip, don't crash"
- Never capture anchor "originals" without passing them through `snapResidue()` (prevents transform compounding across hot reloads)
- Keep the mod idempotent—every pass must be a no-op when the desired state is already applied
- Only direct children of class `CanvasPanel` may be squeezed, and the stray-repair pass must stay: the game briefly parents content widgets directly to the SafeZone canvas during HUD rebuilds, and squeezing those strands them double-squeezed (see FINDINGS.md v1.7)

## Testing

No automated tests; verification is in-game. Tail UE4SS.log while testing. After any working change, refresh the release zip:
```
Compress-Archive -Path CenteredHUD -DestinationPath CenteredHUD-<version>.zip -Force
```

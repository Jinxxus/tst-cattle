# vorp_cattle_herding

A full cattle herding job resource for **RedM** using the **VORP Core** framework.  
Converted and rewritten from an open-source RDR2 SHVDN C++ script.

---

## Features

- **Buy cattle** at Emerald Ranch or McFarlane Ranch
- **Herd cattle** toward sell locations using on-horseback mechanics
- **Sell your herd** at Valentine or Blackwater for dynamic prices
- **AI cowboys** — hire up to 3 AI helpers who flank the herd and chase stragglers
- **Cowboy wages** — cowboys are paid automatically every 5 minutes; unpaid ones may quit
- **Straggler cows** — a percentage of cows have a chance to wander off randomly
- **Rustler events** — optional armed bandit attacks when herding (off by default)
- **Market fluctuation** — prices shift daily between 80 % and 120 % of base value
- **Reputation & skill system** — successful drives build rep and improve payouts
- **Debug HUD** with on-screen overlay (toggle-able)

---

## Dependencies

| Dependency | Notes |
|-----------|-------|
| [RedM](https://redm.gg) | Server platform |
| [vorp_core](https://github.com/VORPCORE/vorp-core) | Economy, character, events |

---

## Installation

1. Drop the `vorp_cattle_herding` folder into your server's `resources/` directory.
2. Add `ensure vorp_cattle_herding` to your `server.cfg` **after** `ensure vorp_core`.
3. Start / restart your server.

---

## Configuration — `shared/config.lua`

All tunable values live in one place. Key options:

| Key | Default | Description |
|-----|---------|-------------|
| `CowBuyPrice` | 2000 | Cash cost per cow |
| `CowSellPrice` | 2500 | Base cash earned per cow when sold |
| `CowboyHirePrice` | 2500 | Cost to hire one AI cowboy |
| `MaxCowboys` | 3 | Max simultaneous AI cowboys |
| `WageInterval` | 300 | Seconds between wage payments |
| `RustlersEnabled` | false | Toggle rustler ambush events |
| `EventChance` | 30 | % chance an event fires after cooldown |
| `DebugHUD` | true | Show HUD overlay by default |
| `CurrencyType` | "money" | `"money"` or `"gold"` |

---

## Controls

> Controls use RedM's INPUT_ constants. You may remap them in `client/main.lua`.

| Action | Control |
|--------|---------|
| Toggle herding on/off | `INPUT_SCRIPT_PAD_UP` |
| Toggle HUD | `INPUT_CONTEXT_SECONDARY` |
| Toggle rustlers | `INPUT_SWITCH_VISOR` |
| Run herd | `INPUT_FRONTEND_UP` |
| Walk herd | `INPUT_FRONTEND_RIGHT` |
| Stop herd | `INPUT_FRONTEND_DOWN` |
| Buy cow (near buy zone) | `INPUT_CONTEXT` |
| Hire cowboy (near buy zone) | `INPUT_CONTEXT_B` |
| Sell herd (near sell zone) | `INPUT_CONTEXT` |
| Dismiss cowboy (nearby/aimed at) | `INPUT_CONTEXT_Y` |
| Debug spawn cows | `INPUT_SCRIPT_PAD_DOWN` (HUD must be on) |

---

## Locations

### Buy cattle
- **Emerald Ranch** — `1422.70, 295.06, 88.96`
- **McFarlane Ranch** — `-2373.0, -2410.0, 61.5`

### Sell cattle
- **Valentine** — `-258.03, 669.95, 113.27`
- **Blackwater** — `-754.0, -1291.0, 43.0`

---

## Known Limitations / Notes

- **Outfit randomisation** (`SetRandomOutfitPreset`) and **saddle functions** (`ApplyRandomSaddle`, `GiveSaddleToHorse`) from the original C++ script are **not directly exposed as standalone natives** in RedM. The converted script intentionally omits these calls to maintain stability. If you need outfit variety, hook into VORP's character appearance exports or add your own outfit table.
- The `MONEY` natives from the original C++ (`_MONEY_GET_CASH_BALANCE`, etc.) are **singleplayer-only** and do not work in RedM — all economy is handled through VORP Core server events instead.
- Debug spawn keys are intentionally gated behind the HUD toggle so they don't interfere with normal play.
- If `vorp_core` is not loaded yet when this resource starts, the server-side handler will retry on `onServerResourceStart`. Make sure `vorp_core` is listed **before** this resource in `server.cfg`.

---

## File Structure

```
vorp_cattle_herding/
├── fxmanifest.lua
├── shared/
│   └── config.lua       ← all config values
├── client/
│   └── main.lua         ← all client-side logic
└── server/
    └── main.lua         ← VORP economy wrappers
```

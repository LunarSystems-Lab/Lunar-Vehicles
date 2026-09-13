# lunar-vehicles

Crash damage, tyres, handling, oil, roadside repair for QBCore.

GPL-3.0 · v1.4.0 · [LICENSE](LICENSE)

## Install

1. Put `lunar-vehicles` in your resources folder.
2. Add the item from `items.lua` to `qb-core/shared/items.lua`.
3. Restart `qb-core`.
4. `server.cfg`:

```
ensure qb-core
ensure oxmysql
ensure qb-inventory
ensure qb-target
ensure progressbar
ensure lunar-vehicles
```

Optional image: `lunar_oil.png` in your inventory images folder.

## Oil

Item: `lunar_oil` — fills oil to 100%.

Out of the car, use the item or qb-target → Fill Engine oil. Hold Z for the gauge.

## Limp

| | |
| --- | --- |
| Oil ≤ 10% | limp (still driveable) |
| Engine ≤ ~20% | limp (still driveable) |
| Engine ≤ ~70 | undriveable |

## Config

| | |
| --- | --- |
| Mechanic job name | `Config.Repairs.advanced.requireJob` |
| Oil item name / fill | `Config.Oil.bottles` |
| Handling feel | `config.handling.lua` |

Owned plates save to `player_vehicles.mods.lunarState`.

## Dependencies

Required: `qb-core`, `oxmysql`  
Recommended: `qb-inventory`, `qb-target`, `progressbar`  
Optional: `ps-ui`, `qb-ambulancejob`

## Exports

```lua
exports['lunar-vehicles']:GetState(plate)        -- server
exports['lunar-vehicles']:SetState(plate, patch) -- server
exports['lunar-vehicles']:ServiceOil(plate, grade, fill)
exports['lunar-vehicles']:GetClientState()       -- client
exports['lunar-vehicles']:RefreshHandling()      -- client
```

See [NOTICE](NOTICE) for copyright and third-party notes.

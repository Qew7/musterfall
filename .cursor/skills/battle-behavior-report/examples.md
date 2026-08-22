# Worked incidents (game 42)

These are real rows from battles 170–173. Use them as the bar for a “proven” incident, not as eternal truth.

## PHANTOM_TERRAIN — B170 R1 Орки-бойзы `unit-9`

- seed `901751966`, from `(31.0, 3.0) f180` → `(28.25, 2.92) f186.9`
- kind `wheel`, `approachMode: direct`, `pathingAvoided: false`, truncated, leftover MV `0.00` / `3.00`
- summary: путь преграждён местность (house)
- unit OBB ~4×4 AABB `[26.0, 0.7]–[30.5, 5.2]`
- nearest houses: `terrain-5` `[11.95, 1.11]–[15.29, 4.60]`, `terrain-4` `[23.48, 6.38]–[26.91, 9.35]` — **no overlap**
- layer: maneuver clip / obstacle kernels reporting a house the footprint never touches; thread did not wrap

## CRASH after “bypass” — B170 R2 Имперские мечники (center)

- `(10.7, 12.3) f7.5` → `(13.12, 12.62) f16.6`, kind `bypass`, `pathingAvoided: true`, leftover `0.24`
- summary: обходит местность (lake)
- final AABB overlaps `terrain-3:lake` `[15.36, 6.91]–[19.92, 10.47]`
- layer: Follow accepted a wrap that still collides; `avoided` is not “clear of terrain”

## REFUSED_BYPASS — B172 R5 Наездники `unit-?` vs Орки-бойзы

- `(34.1, 10.0) f179.3` → `(33.14, 10.09) f183.4`, kind `wheel`, truncated, leftover **`5.93` / `7.00`**
- `pathingAvoided: false`, blocker = allied/enemy orcs, Δxy `0.97`
- layer: clip stopped the tray; leftover MV was enough to wrap; planner stayed `direct`

## TURN_AWAY then IDLE_ROW — B170 R1–R2 Каменные тролли `unit-11`

- R1: `(35.0, 19.0) f180` → `(34.25, 18.25) f270`, steps `advance+turn+advance`, Δfacing **+90°**, Δxy `1.06`
- `kind: bypass`, `approachMode: direct`, target Имперские мечники
- `heading: 180`, `desiredFacing: 180`, **`desired.facing: 270`**
- R2: `row_advance` support→front, Δxy `0`, MV `0/0` — legal row bookkeeping **after** the wasted 90° turn
- layer: Follow walked a wrap vertex beside the tray (`Turn.applies?`); heading is first segment, not the goal

## Naming collision — B170 unit-38 vs unit-35

Summary «путь преграждён Имперские мечники» is **another** swordsmen block (`blockerId=unit-35`), not self-collision. Always cite ids.

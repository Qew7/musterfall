---
name: battle-behavior-report
description: >-
  Produce a patch-ready report of strange Musterfall unit movement (terrain
  crashes, refused bypass, standing still, turns into nowhere) from recent
  battles. Use when the user asks to study бои, replay movement bugs,
  врезаются в терейн, поворот вникуда, отказ от обхода, стояние на месте,
  or wants a movement behavior report before fixing pathing.
---

# Battle Behavior Report

Companion to [read-battle-info](../read-battle-info/SKILL.md). That skill loads data. This one turns movement actions into a **clustered, layer-attributed report** that a later change can implement without flags or fallbacks.

Do **not** patch from replay vibes. Do **not** add `if truncated then bypass` / special-case flags. Name the pipeline stage that produced the pose.

## Workflow

```
- [ ] Dump last N real battles (read-battle-info, Docker first)
- [ ] Stop if combatants/actions are 0
- [ ] Scan movement actions (script below)
- [ ] Cluster by tag, not by unit name
- [ ] Prove each cluster with pose + leftover MV + terrain AABB + blocker
- [ ] Attribute to a pipeline stage
- [ ] Write the report in the template below
- [ ] Only then propose a fix in Thread / Follow / Maneuvers / planner
```

### 1. Dump

From repo root, last N non-empty `Battle` rows. Write JSON the scanner understands (`phases[].actions`, `terrain`, `initial_snapshot`). Prefer `RoundMatchup.result_payload` for `initial_snapshot` + `terrain`; phase `actions` from persisted `Battle`.

Facing **0 = +X**. Matchup/result_payload is snake_case; `BattlePhase#actions` is camelCase. Read both.

### 2. Scan

Run (execute, do not rewrite):

```bash
ruby .cursor/skills/battle-behavior-report/scripts/scan_movements.rb \
  backend/tmp/battle_dumps/battle_*.json
```

Stdlib only (JSON). No Bundler, no Rails.

Tags:

| Tag | Meaning |
|-----|---------|
| `PHANTOM_TERRAIN` | `truncatedByCollision`, summary/blocker is terrain, **final OBB does not overlap** impassable AABB |
| `CRASH` | final OBB **overlaps** impassable (house/lake), including after `pathingAvoided` |
| `REFUSED_BYPASS` | truncated, `pathingAvoided=false`, leftover MV `> 0.5` |
| `TURN_AWAY` | ~90° turn; `desired.facing` disagrees with `heading`/`desiredFacing`; summary «разворачивается на фланг» |
| `IDLE_ROW` | `row_advance`, Δxy ≈ 0 (formation bookkeeping — escalate only if it follows `TURN_AWAY`) |

A move may have several tags. **Cluster on tags**, then list repeat actor-ids.

### 3. Prove (required fields per incident)

Every cited incident must include:

- `battle_id`, `seed`, round, `actorId` (names collide — «Имперские мечники» is not unique)
- from/to `x,y,facing`, Δxy, leftover MV / budget
- `maneuver.kind`, `approachMode`, `pathingAvoided`, `truncatedByCollision`
- `blockerId`/`blockerName`, `targetId`
- `heading` vs `desired.facing` vs `desiredFacing` (they are **not** the same)
- overlap of **final** OBB with impassable AABBs (yes/no + feature id)
- `steps[]` kinds

`trace` on persisted actions is `{result, trigger, ruleKeys}` — **not** the geometric thread. Thread points are dropped. To see the thread, re-sim with matchup seed and print `Pathing::Thread.pull` / `Follow.along` `[:thread]`.

### 4. Attribute to a layer

Walk this table; pick **one** primary stage. Do not invent a new flag in `phases/movement.rb`.

| Stage | File | Symptom |
|-------|------|---------|
| Target / slot | `rules/ground/movement.rb` | wrong enemy, `approachMode: direct` while a flank orbit was the intent |
| Thread | `pathing/thread.rb` | no wrap around house/lake; vertices inside obstacle; first vertex 90° off the goal |
| Follow | `pathing/follow.rb` | walks first wrap vertex as a 90° `Turn`; `heading` is **first segment**, not the goal; `avoided` only if `wrapped.any? && thread[:complete]` |
| Maneuver clip | `pathing/maneuvers/*.rb` | `truncatedByCollision` with leftover MV, or stop 1–3" short of the named blocker (`PHANTOM_TERRAIN`) |
| Collision kernels | `pathing/obstacles.rb` | inflated OBB / kernel reports a house the footprint never touches |
| Flyer | `rules/flying/movement.rb` | leap/charge facing ≠ travel heading; landing on impassable |

`Follow.along` sets `heading` to `heading_to(origin, points[1])`. A wrap vertex beside the tray becomes `Turn.applies?` (~90°) while `desiredFacing` on the action may still be the original facing. That is `TURN_AWAY`, not a missing «flank intent» flag.

### 5. What not to flag

- `IDLE_ROW` alone: row/lane **did** change (`support → front`) with Δxy=0. Legal formation step. Flag the **previous** 90° turn if that wasted the assault.
- Truncated, leftover ≈ 0, **and** final OBB actually against the blocker: MV spent walking into a real obstacle. Still a thread failure if a wrap existed; not «standing still».
- `FACE_VS_MOVE` using `atan2(dx, dy)`: facing 0 is **+X**. Do not report facing/heading bugs from a +Y convention.
- Engaged skip / charge already in contact.
- Duplicate display names: always `actorId` vs `blockerId`.

## Report template

```markdown
# Movement report — battles <ids> (game <id>, round <n>)

## Scope
seed(s), map terrain (id/type/aabb), combatant counts. Same map_seed ⇒ copy terrain once.

## Failure modes (clusters)
For each tag: count, 2–4 proven incidents (fields from §3), primary layer from §4.
Repeat actor-ids across rounds = same failure, not new bugs.

## Not bugs
IDLE_ROW-only, spent-MV real contacts, naming collisions.

## Patch target
One sentence per cluster: which file/method should own the pose (Thread wrap / Follow segment / kernel).
No flags, no fallbacks, no `if house then sidestep`.
```

## Anti-patterns

- Patching `phases/movement.rb` or adding `bypass_forced` / `stuck` flags
- Trusting replay without leftover MV + AABB overlap
- Treating `pathingAvoided=true` as success (can still `CRASH` into lake/house)
- One paragraph per unit instead of clusters
- Proposing a fix before naming the layer

## Example

Worked incidents: [examples.md](examples.md)

---
name: battle-rules
description: >-
  Create, change, and extend Musterfall battle rules under
  backend/app/domain/sim/battle/rules/<rule>/<phase>.rb with phase hooks,
  registry wiring, logs, and tests. Use when adding abilities (flying, fear,
  breath, charge…), overriding melee/shooting/movement/morale behavior,
  describing a new rule, or refactoring rule/phase composition.
---

# Musterfall Battle Rules

Rule-first architecture. **Do not** paste special-case logic into phase files.

## Layout

```
backend/app/domain/sim/battle/
  rules.rb                      # REGISTRY + RuleSet
  rules/<rule>/<phase>.rb       # one folder per rule; phase files inside
  phases/*.rb                   # thin orchestrators only
  decisions/*.rb                # shared facades (constants, default dispatch)
  geometry/battlefield/         # pure geometry (no phase/rule policy)
```

Examples:

| Rule | Files |
|------|--------|
| fear | `rules/fear/melee.rb` |
| breath | `rules/breath/shooting.rb` |
| flying | `rules/flying/movement.rb` |
| ground (default planner) | `rules/ground/movement.rb` |

If a rule later touches two phases: add another file in the **same** rule folder (`rules/fear/morale.rb`), then register it.

Zeitwerk: `rules/fear/melee.rb` → `Sim::Battle::Rules::Fear::Melee`.

## When describing a new rule (planning / specs)

State explicitly:

1. **Rule key** — ability/template name (`fear`, `flying`, `breath`).
2. **Phases touched** — `melee` / `shooting` / `movement` / `morale` / …
3. **Hooks to override** — list method names from the contract below.
4. **Trigger** — when it applies (`abilities.include?("fear")`, `shooting_template == "breath"`, …).
5. **Behavior** — concrete outcomes (cancel assault, leap landing, template hits).
6. **Logs** — player `summary` + `details` lines (roll, models_hit, …).
7. **Data** — seeds/ability/template changes if needed.
8. **Tests** — which cases under `test/game/battle/`.

Do **not** specify “edit `phases/melee.rb` to if fear…”. Specify “add `rules/fear/melee.rb` overriding `before_play!` / `allow_attack?`”.

## Hook contract

Optional methods on a rule module (`module_function`). `RuleSet` only calls what exists.

| Hook | Phase / caller | Semantics |
|------|----------------|-----------|
| `before_play!(ctx)` | start of phase (`ctx`: `:phase`, `:acting_side`, `:target_side`, `:round_number`, …) | side effects, checks, push actions |
| `allow_attack?(attacker, ctx)` | before melee resolve | AND across rules; `false` skips attacker |
| `applies?(profile, attack_type)` | shooting/missile | whether this rule owns the strike |
| `attack_victims(...)` | targeting | victim list (models_hit, multipliers, …) |
| `resolve_missile_strike!(...)` | attack resolution | apply damage + logs when `applies?` |
| `template_descriptor(...)` | replay overlay | shape/points for frontend |
| `expected_damage(...)` | missile AI | must match resolve semantics |
| `plan_entries` / `plan_entry` / `build_approach_intent` | movement decisions | planner API |
| `corner_contact_reachable?(...)` | movement facade via `planner_for` | reachability for that move style |

Movement planners are selected by `Rules.planner_for_movement(combatant)` (ability → Flying, else Ground), not only via `RuleSet` chain.

## Registry

In [`rules.rb`](backend/app/domain/sim/battle/rules.rb), index **by phase**:

```ruby
REGISTRY = {
  melee: -> { [ Fear::Melee ] },
  shooting: -> { [ Breath::Shooting ] },
  movement: -> { [ Flying::Movement ] }  # optional; planners often via planner_for_movement
}.freeze
```

After adding a phase file, **register it** (or wire `planner_for_*` for movement defaults).

## Phase thinning (required)

Phases may only:

1. Call `Rules.for(:phase).before_play!(ctx)` / `allow_attack?` / `find_applicable`
2. Delegate planner methods to `Rules.planner_for_movement` / rule modules
3. Keep shared defaults (generic wheeled path, single-target shot)

**Forbidden in phases / decisions facades:**

- `if abilities.include?("fear")` / `"flying"` / template branches for special weapons
- Inlined leap / teardrop / fear-check logic

Put those in `rules/<rule>/<phase>.rb`. Shared geometry → `geometry/battlefield/` (e.g. `templates.rb`).

## Logs (game + dev)

Every meaningful rule outcome must write:

1. **Player:** `action[:summary]` + `AttackResolution.add_event(phase, summary)`
2. **Dev:** `action[:details]` — array of short key=value lines (`fear_check reason=…`, `models_hit=…`, `template_points=…`)
3. Push `phase[:actions] << action` so DB/`result_payload` and replay (`summary` → log, `details` → devLog) stay correct

Reuse existing action shapes (`fear_check`, shooting with `template`, movement maneuvers).

## Seeds / data

- New ability → `db/seeds.rb` abilities list + templates that use it
- Template kinds (`breath`) → `default_*_template_for` / explicit fields on templates
- After seed changes in Docker: `docker compose exec backend bin/rails db:seed`

## Tests

- Unit/integration under `backend/test/game/battle/`
- Cover: registry membership, rule folder path exists, behavioral cases, log fields (`summary` / `details`)
- Run: `cd backend && bin/rails test test/game/battle/`

## Workflow checklist

```
- [ ] rules/<rule>/<phase>.rb created (hooks only for that phase)
- [ ] REGISTRY / planner_for_* updated
- [ ] Phase/facade only delegates — no rule if-branches
- [ ] Geometry kept out of rule policy when possible
- [ ] summary + details + phase events
- [ ] seeds if ability/template changed (+ db:seed in container)
- [ ] tests green
```

## Anti-patterns

- Editing `phases/*.rb` to special-case an ability
- Putting flying leap checks in `decisions/movement.rb` instead of `rules/flying/movement.rb`
- Rule folder named by phase (`rules/melee/fear.rb`) — wrong; use `rules/fear/melee.rb`
- AI expected_damage that disagrees with resolve
- Player-facing logs only in `details` (or only `add_event` without action)

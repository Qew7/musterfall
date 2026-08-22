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
| fear | `rules/fear/melee.rb`, `rules/fear/morale.rb` |
| breath / volley / blast | `rules/*/shooting.rb` |
| charge / ferocious / steadfast / skirmisher | `rules/*/melee.rb` |
| machine | `rules/machine/shooting.rb` |
| undead | `rules/undead/morale.rb`, `rules/undead/round.rb` |
| flying / ground | `rules/flying/movement.rb`, `rules/ground/movement.rb` |
| bannerAura / steadfastAura | `rules/*/setup.rb` |

If a rule later touches two phases: add another file in the **same** rule folder (`rules/fear/morale.rb`), then register it.

Zeitwerk: `rules/fear/melee.rb` → `Sim::Battle::Rules::Fear::Melee`.
Zeitwerk: `rules/banner_aura/setup.rb` → `Sim::Battle::Rules::BannerAura::Setup`.

## When describing a new rule (planning / specs)

State explicitly:

1. **Rule key** — ability/template name (`fear`, `flying`, `breath`).
2. **Phases touched** — `melee` / `shooting` / `movement` / `morale` / `setup` / `round` / …
3. **Hooks to override** — list method names from the contract below.
4. **Trigger** — when it applies (`abilities.include?("fear")`, `shooting_template == "breath"`, …).
5. **Behavior** — concrete outcomes (cancel assault, leap landing, template hits).
6. **Logs** — player `summary` + `details` lines (roll, models_hit, …).
7. **Data** — seeds/ability/template changes if needed.
8. **Tests** — which cases under `test/game/battle/`.

Do **not** specify “edit `phases/melee.rb` to if fear…”. Specify “add `rules/fear/melee.rb` overriding `before_play!` / `allow_attack?`”.

## Hook contract

Optional methods on a rule module (`module_function`). `RuleSet` only calls what exists.

| Hook | Aggregation | Phase / caller | Semantics |
|------|-------------|----------------|-----------|
| `before_play!(ctx)` | each | start of phase | side effects, checks, push actions |
| `after_play!(ctx)` | each | end of phase / turn | movement and timed-effect triggers |
| `after_hit!(ctx)` | each | after a successful strike | reactions such as retaliatory damage |
| `allow_attack?(attacker, ctx)` | AND | before melee resolve | `false` skips attacker |
| `allow_target?(attacker, target, attack_type)` | AND | missile targeting | concealment and target restrictions |
| `hit_chance_factor(attacker, defender, attack_type)` | product | attack resolution / missile AI | temporary accuracy penalties |
| `applies?(profile, attack_type)` | first match | shooting/missile | whether this rule owns the strike |
| `attack_victims(...)` | via `find_applicable` | targeting | victim list (models_hit, multipliers, …) |
| `resolve_missile_strike!(...)` | via `find_applicable` | attack resolution | apply damage + logs |
| `template_descriptor(...)` | via `find_applicable` | replay overlay | shape/points for frontend |
| `expected_damage(...)` | via `find_applicable` | missile AI | must match resolve semantics |
| `damage_factor(attacker, defender, attack_type, vector, round_number)` | **product** | `AttackResolution.damage` | ability multipliers (default 1.0) |
| `facing_damage_factor(defender, vector)` | **first non-nil** | `AttackResolution.damage` | skirmisher → 1.0; else phase default facing |
| `morale_threshold_delta(combatant, allies, enemies, combat_score_delta)` | **sum** | `Morale.resolve_check` | fear −1, disciplined +1 |
| `effective_morale(combatant, allies)` | **first non-nil** | `Morale.effective_morale` | muster override |
| `handle_morale_failure!(combatant, check, ctx)` | **first truthy Hash** | `Morale.resolve_action` | undead HP loss instead of flee |
| `requires_front_arc_for_ranged?(attacker)` | **AND** (default true) | targeting / reposition | skirmisher → false |
| `movement_multiplier(combatant, ctx)` | product | movement budget | temporary movement modifiers |
| `apply_attach!(host_ctx)` | each | `State` combatant build | bannerAura / steadfastAura |
| `apply_passives!(side)` | concat events | `State.apply_faction_passives!` | undead regen |
| `plan_entries` / `plan_entry` / `build_approach_intent` | planner API | movement decisions | |
| `corner_contact_reachable?(...)` | via `planner_for` | movement facade | |

Damage walks `Rules.for(Rules.damage_phase_for(attack_type))` (`melee` vs `shooting`; magic uses shooting registry). Default facing when no rule returns a factor: rear 1.55, flank 1.25, else 1.0.

Movement planners are selected by `Rules.planner_for_movement(combatant)` (ability → Flying, else Ground), not only via `RuleSet` chain.

## Registry

In [`rules.rb`](backend/app/domain/sim/battle/rules.rb), index **by phase**:

```ruby
REGISTRY = {
  melee: -> { [ Fear::Melee, Charge::Melee, Ferocious::Melee, Steadfast::Melee, Skirmisher::Melee ] },
  shooting: -> { [ Breath::Shooting, Volley::Shooting, Blast::Shooting, Machine::Shooting, Steadfast::Melee, Skirmisher::Melee ] },
  morale: -> { [ Undead::Morale, Fear::Morale, Disciplined::Morale, Muster::Morale ] },
  setup: -> { [ BannerAura::Setup, SteadfastAura::Setup ] },
  round: -> { [ Undead::Round ] },
  movement: -> { [ Flying::Movement ] }
}.freeze
```

`Steadfast::Melee` / `Skirmisher::Melee` are dual-registered so facing/steadfast factors also apply to shooting/magic damage.

After adding a phase file, **register it** (or wire `planner_for_*` for movement defaults).

## Phase thinning (required)

Phases may only:

1. Call `Rules.for(:phase).*` hooks (`before_play!`, `allow_attack?`, `find_applicable`, `damage_factor`, …)
2. Delegate planner methods to `Rules.planner_for_movement` / rule modules
3. Keep shared defaults (generic wheeled path, single-target shot, default facing table)

**Forbidden in phases / decisions facades:**

- `if abilities.include?("fear")` / `"flying"` / `"charge"` / template branches for special weapons
- Inlined leap / teardrop / fear-check / undead-break logic

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

Lefthook `rule_layers` (`ruby test/support/rule_layer_lint.rb`) fails if phases / decisions / pathing / geometry grow ability or flyer-mode branches. Move the branch; do not disable the scan.

## Anti-patterns

- Editing `phases/*.rb` to special-case an ability
- Putting flying leap checks in `decisions/movement.rb` instead of `rules/flying/movement.rb`
- Rule folder named by phase (`rules/melee/fear.rb`) — wrong; use `rules/fear/melee.rb`
- AI expected_damage that disagrees with resolve
- Player-facing logs only in `details` (or only `add_event` without action)

---
name: reseed-templates
description: >-
  Re-run Musterfall db:seed after backend/db/seeds.rb changes without wiping
  battle logs (RoundMatchup, Battle). Prefer docker exec on musterfall-backend-1.
  Use when the user edits unit stats, factions, abilities, or upgrades in seeds
  and asks to reseed, перезапустить сиды, обновить статы шаблонов, or keep
  battle/replay history.
---

# Reseed Templates (Keep Battle Logs)

`backend/db/seeds.rb` is **idempotent**: it upserts catalog data only. Safe command is **`db:seed`**, not destructive replant/reset.

## Safe vs destructive

| Command | Battle logs |
|---------|-------------|
| `bin/rails db:seed` | **Kept** — use this |
| `bin/rails db:seed:replant` | **Wiped** — never for this task |
| `bin/rails db:reset` / `db:setup` | **Wiped** — never unless user explicitly wants full reset |

Seeds touch: `Faction`, `ArmyTemplate`, `Ability`, `HeroUpgrade`, `ArmyTemplateAbility` (join rows recreated per template). They do **not** touch `Game`, `RoundMatchup`, `Battle`, or campaign state.

## Workflow

1. Confirm Docker backend is up (from repo root):

```bash
docker compose ps
# typical container: musterfall-backend-1
```

2. Snapshot battle-log counts **before** seeding:

```bash
docker exec musterfall-backend-1 bin/rails runner \
  'puts "RoundMatchups=#{RoundMatchup.count} Battles=#{Battle.count}"'
```

3. Run seeds:

```bash
docker exec musterfall-backend-1 bin/rails db:seed
```

4. Verify counts **unchanged** and spot-check a template if the user changed stats:

```bash
docker exec musterfall-backend-1 bin/rails runner "$(cat <<'RUBY'
puts "RoundMatchups=#{RoundMatchup.count} Battles=#{Battle.count}"
t = ArmyTemplate.find_by!(template_key: "state_swords")
puts "state_swords melee=#{t.melee} movement=#{t.movement} morale=#{t.morale}"
RUBY
)"
```

Replace `template_key` / fields with whatever the user edited.

5. Report to the user: seed OK, battle counts unchanged, which templates were updated.

## Local fallback

Only if Docker is unavailable:

```bash
cd backend && bin/rails db:seed
```

Local DB may be empty or stale — prefer Docker for development data.

## Tell the user when relevant

- **Existing replays** use snapshots stored in `RoundMatchup` / `Battle` at fight time; reseeding does not rewrite them.
- **New battles** after reseed pick up updated template stats from the catalog.
- Editing seeds does not require `db:migrate` unless schema changed separately.

## Do not

- Run `db:seed:replant`, `db:reset`, or `db:setup` when the user asks to keep battle logs.
- Truncate or delete `round_matchups`, `battles`, or related tables.
- Assume `Game#state_payload` reflects template changes — campaign entities keep their own copies until recruited/rebuilt.

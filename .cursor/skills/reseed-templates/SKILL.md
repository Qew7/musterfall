---
name: reseed-templates
description: >-
  Musterfall catalog seeds: backend/db/seeds.rb is idempotent. With docker compose
  up, seed-watcher auto-runs db:seed on save — agents do NOT manually seed after
  edits. Use for verifying seed results, battle-log safety, local fallback without
  Docker, or when user explicitly asks to reseed / перезапустить сиды.
---

# Reseed Templates (Keep Battle Logs)

`backend/db/seeds.rb` is **idempotent**: it upserts catalog data only. Safe command is **`db:seed`**, not destructive replant/reset.

## Auto-seed in Docker (default dev)

`docker compose up` starts **`seed-watcher`**: on every save of `backend/db/seeds.rb` it runs `db:seed` in the container.

**Agents: after editing seeds in Docker dev, do NOT run `db:seed` yourself.** Save the file (or let your edit land on disk) and wait a few seconds. Check `docker compose logs seed-watcher --tail 20` only if you need confirmation.

Do **not** also run `bin/watch-seeds` on the host — that duplicates the watcher.

Manual `db:seed` only when:

- `seed-watcher` is not running (`docker compose ps seed-watcher`)
- Docker dev stack is down (local `cd backend && bin/rails db:seed`)
- User explicitly asks to reseed or verification shows DB still stale

## Safe vs destructive

| Command | Battle logs |
|---------|-------------|
| `bin/rails db:seed` | **Kept** — use this |
| `bin/rails db:seed:replant` | **Wiped** — never for this task |
| `bin/rails db:reset` / `db:setup` | **Wiped** — never unless user explicitly wants full reset |

Seeds touch: `Faction`, `ArmyTemplate`, `Ability`, `HeroUpgrade`, `ArmyTemplateAbility` (join rows recreated per template). They do **not** touch `Game`, `RoundMatchup`, `Battle`, or campaign state.

## Verify after seed (optional)

When the user cares about battle logs or you need proof the catalog updated:

1. Confirm stack is up:

```bash
docker compose ps
```

2. If you ran seed manually or want to confirm watcher finished, check logs:

```bash
docker compose logs seed-watcher --tail 20
```

3. Spot-check counts and a template (replace `template_key` / fields as needed):

```bash
docker compose exec -T backend bin/rails runner "$(cat <<'RUBY'
puts "RoundMatchups=#{RoundMatchup.count} Battles=#{Battle.count}"
t = ArmyTemplate.find_by!(template_key: "state_swords")
puts "state_swords melee=#{t.melee} movement=#{t.movement} morale=#{t.morale}"
RUBY
)"
```

4. Report: seed OK (auto or manual), battle counts unchanged, which templates changed.

## Manual seed (fallback)

Only if auto watcher is unavailable:

```bash
docker compose exec -T backend bin/rails db:seed
```

Local without Docker:

```bash
cd backend && bin/rails db:seed
```

Local DB may be empty or stale — prefer Docker for development data.

## Tell the user when relevant

- **Existing replays** use snapshots stored in `RoundMatchup` / `Battle` at fight time; reseeding does not rewrite them.
- **New battles** after reseed pick up updated template stats from the catalog.
- Editing seeds does not require `db:migrate` unless schema changed separately.

## Do not

- Run `db:seed` after every seeds.rb edit when `seed-watcher` is Up — redundant.
- Run `db:seed:replant`, `db:reset`, or `db:setup` when the user asks to keep battle logs.
- Truncate or delete `round_matchups`, `battles`, or related tables.
- Assume `Game#state_payload` reflects template changes — campaign entities keep their own copies until recruited/rebuilt.

---
name: read-battle-info
description: >-
  Fully inspect Musterfall battle data from DB, matchups, and dumps. Prefer
  docker exec on the Compose backend (musterfall-backend-1) before local rails
  runner. Use when debugging a fight, tracing charge/movement/footprint bugs,
  finding a battle by player names (Полководец/Бот), reading phase actions, or
  the user asks to look at a бой / battle / replay / RoundMatchup.
---

# Read Musterfall Battle Info

Do **not** rely on `development.log` or empty seed shells. Query the DB via Rails runner, then frontend replay only for visuals.

## How to run queries (DB access)

Live game data lives in the Docker Compose Postgres (`db` service). **Always try Docker first**; local `backend/` runner only as fallback (often empty / wrong DB).

1. **Docker (preferred)** — from repo root:

```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep -E 'backend|db'
# typical: musterfall-backend-1
docker exec musterfall-backend-1 bin/rails runner '...'
```

If the backend container name differs, resolve it:

```bash
docker compose ps -q backend | xargs -I{} docker inspect -f '{{.Name}}' {} | sed 's#^/##'
# or: docker ps --format '{{.Names}}' | grep backend
```

Long Ruby: pass via heredoc so quotes survive:

```bash
docker exec musterfall-backend-1 bin/rails runner "$(cat <<'RUBY'
# ... query ...
RUBY
)"
```

Dump JSON from the container to the host when needed (`./backend` is mounted at `/rails`):

```bash
# write inside container to /rails/tmp/... then read on host at backend/tmp/...
docker exec musterfall-backend-1 bin/rails runner 'File.write("tmp/battle_dumps/x.json", ...)'
# or: docker cp musterfall-backend-1:/rails/tmp/... ./backend/tmp/...
```

2. **Local fallback** — only if Docker is down / unavailable:

```bash
cd backend && bin/rails runner '...'
```

## Source priority

1. **`RoundMatchup.result_payload`** — full sim output (snake_case): `initial_snapshot`, `left`/`right`, `rounds`, `events`
2. **`Game#last_round_report`** — same package after settle (snake_case in DB)
3. **`Battle` + nested rounds/turns/phases** — persisted report; phase `actions` are the debug gold (camelCase via BattleWriter)
4. **Frontend replay** — only after confirming `initialSnapshot` + phase `actions` exist
5. **Ignore** `Game#state_payload` — always unused `{}`

## Find the battle

Run the snippets below via **`docker exec … bin/rails runner`** (see above).

```ruby
# Prefer game_id + names; verify it actually fought
b = Battle.includes(battle_rounds: { battle_turns: :battle_phases })
          .where(left_player_name: "Полководец 1", right_player_name: "Бот 1")
          .order(id: :desc).first
# or Battle.where(game_id: ID, round_number: CAMPAIGN_ROUND)

lc = Array(b.left_payload["combatants"]).size
rc = Array(b.right_payload["combatants"]).size
actions = b.battle_rounds.sum { |r|
  r.battle_turns.sum { |t| t.battle_phases.sum { |p| Array(p.actions).size } }
}
puts "id=#{b.id} game=#{b.game_id} combatants=#{lc}/#{rc} actions=#{actions} summary=#{b.summary}"
```

**Stop if `combatants` and `actions` are 0** — empty seed/auto games. Do not analyze those shells; find a matchup with real `result_payload["rounds"]` or re-run after recruit/deploy.

```ruby
rm = RoundMatchup.where(game_id: b.game_id, campaign_round: b.round_number)
                 .find { |m| [m.attacker_player_key, m.defender_player_key].sort ==
                             [b.left_player_id, b.right_player_id].sort }
rp = rm&.result_payload || {}
puts "matchup=#{rm&.id} status=#{rm&.status} seed=#{rm&.seed} rounds=#{Array(rp["rounds"]).size} initial=#{Array(rp["initial_snapshot"]).size}"
```

## What each field means

| Need | Where |
|------|--------|
| Deployment / start poses | `initial_snapshot` (matchup / last_round_report) — **not** `Battle#left_payload` |
| End-of-battle units | `Battle#left_payload` / `right_payload` → `combatants` |
| Phase log lines | `BattlePhase#events` (RU); top-level `Battle#events` is truncated (~24) |
| Movement / charge / shrink | `BattlePhase#actions` where `phase_type` / action `type` matches |
| Live campaign roster | `GamePlayer` → `GameEntity` (not in-battle poses) |
| Deterministic replay | `RoundMatchup#seed` + `attacker_snapshot` / `defender_snapshot` |

## Key shape pitfalls

- Matchup / `last_round_report`: **snake_case** strings (`player_id`, `initial_snapshot`, `actor_id`)
- Persisted `Battle*` actions/payloads: **camelCase** (`playerId`, `actorId`, `actorStateBefore`, `maneuver.contactSlot`)
- In-sim Ruby: **symbol snake** (`:actor_id`)
- Always try both `foo["combatants"]` and dig safely; never assume symbols from jsonb

## Inspect movement / charge / footprint

```ruby
b.battle_rounds.each do |round|
  round.battle_turns.each do |turn|
    turn.battle_phases.each do |phase|
      phase.actions.each do |a|
        next unless %w[movement melee].include?(a["type"].to_s)
        puts "R#{round.number} #{phase.phase_type} #{turn.player_name}: #{a["summary"]}"
        if a["type"] == "movement"
          puts "  from=#{a["from"]} to=#{a["to"]}"
          puts "  maneuver=#{a["maneuver"]&.slice("kind","targetId","targetName","contactSlot","truncatedByCollision","blockedByAlly")}"
          before = a["actorStateBefore"] || a["actor_state_before"]
          after  = a["actorStateAfter"]  || a["actor_state_after"]
          puts "  footprint #{before&.slice("baseWidth","baseDepth","files","ranks","modelsRemaining")} → #{after&.slice("baseWidth","baseDepth","files","ranks","modelsRemaining")}"
        end
        if (charge = a["charge"])
          puts "  charge start=#{charge["start"]} dest=#{charge["destination"]} vector=#{charge["vector"]}"
        end
      end
    end
  end
end
```

Footprint shrink (rear trim, front edge fixed): `Sim::Battle::State.sync_combatant_footprint!` — see `test/game/battle/footprint_sync_test.rb`.

Engage/contact band: `Sim::Battle::Pathing::CONTACT` / `ENGAGE`. Approach skipped when already engaged.

## Full package from last round

```ruby
g = Game.find(b.game_id)
m = g.last_round_report.fetch("matchups").find { |x|
  [x.dig("left","player_id"), x.dig("right","player_id")].sort ==
    [b.left_player_id, b.right_player_id].sort
}
# m["initial_snapshot"], m["rounds"], m["summary"], m["events"]
```

## Re-simulate cleanly

```ruby
catalog = Sim::Catalog::Loader.load
result = Sim::Battle::Simulator.call(
  rm.attacker_player, rm.defender_player, catalog,
  rng: Sim::Rng::Seeded.new(rm.seed)
)
# File.write("tmp/battle_dumps/replay_#{rm.id}.json", JSON.pretty_generate(result.deep_stringify_keys))
```

## Checklist

1. Query via **Docker** `musterfall-backend-1` (or current compose backend) first; local runner only if Docker is unavailable
2. Locate `Battle` + matching `RoundMatchup`
3. Assert non-empty combatants **and** actions / rounds
4. Start poses from `initial_snapshot`; end from payloads
5. Dig phase `actions` (not only top-level events)
6. Remember camelCase vs snake_case by store
7. Re-run Simulator with matchup seed if DB row is thin
8. Frontend replay only after data quality check

## Key files

- Persist: `app/domain/sim/persistence/battle_writer.rb`, `campaign_repository.rb`
- Sim entry: `app/domain/sim/battle/simulator.rb`, `turn.rb`
- Jobs: `app/jobs/simulate_battle_job.rb`, `app/services/games/advance_round.rb`
- Replay UI: `frontend/src/game/battle/replayProjection.js`, `frontend/src/screens/BattleScreen.jsx`

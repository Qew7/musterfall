---
name: read-player-actions
description: >-
  Read Musterfall player UI/API action audit from the player_actions table.
  Prefer docker exec on musterfall-backend-1. Use when the user asks to read
  player logs, audit trail, какие кнопки нажали, player_actions, кто что
  нажал, or to reconstruct a campaign session from commands.
---

# Read Player Action Logs

Player button presses that hit the API are appended to **`player_actions`** (not Rails `development.log`). Prefer Docker; local runner only if Compose is down.

## How to query

```bash
docker ps --format '{{.Names}}' | grep backend
# typical: musterfall-backend-1
docker exec musterfall-backend-1 bin/rails runner "$(cat <<'RUBY'
# ... query ...
RUBY
)"
```

## Schema

| column | meaning |
|--------|---------|
| `game_id` | Game PK (nullable only if create audit failed to parse id) |
| `action` | `"controller#action"` e.g. `games#recruit`, `games#advance_round`, `battles#replay` |
| `player_id` | Campaign player key from params (`player-1`), nil for create/advance_round |
| `http_status` | Response status (200/201/422/409…) |
| `params` | jsonb: permitted command fields only (`base_version`, `template_id`, `deploy_mode`, …) |
| `created_at` | When the request finished |

Written by `ApplicationController#audit_player_action` on every `api/*` POST. UI-only clicks (Отмена, смена активного игрока без команды) **не** пишутся.

## Common queries

### Last actions (any game)

```ruby
PlayerAction.order(id: :desc).limit(30).each do |a|
  puts "#{a.created_at.iso8601} game=#{a.game_id} #{a.action} player=#{a.player_id} #{a.http_status} #{a.params}"
end
```

### One game timeline

```ruby
gid = ARGV # or hardcode
PlayerAction.where(game_id: gid).order(:created_at, :id).each do |a|
  puts "#{a.created_at.strftime('%H:%M:%S')} #{a.action} p=#{a.player_id} #{a.http_status} #{a.params.except('base_version')}"
end
```

Via runner one-liner with game id:

```bash
docker exec musterfall-backend-1 bin/rails runner 'gid=GAME_ID; PlayerAction.where(game_id: gid).order(:created_at,:id).each{|a| puts "#{a.created_at.iso8601} #{a.action} #{a.player_id} #{a.http_status} #{a.params}"}'
```

### Failures / conflicts only

```ruby
PlayerAction.where("http_status >= 400").order(id: :desc).limit(20)
```

### One player in a game

```ruby
PlayerAction.where(game_id: gid, player_id: "player-1").order(:created_at)
```

### Find latest game then dump

```ruby
gid = PlayerAction.where.not(game_id: nil).maximum(:game_id)
puts "game_id=#{gid}"
PlayerAction.where(game_id: gid).order(:created_at, :id).map { |a|
  { t: a.created_at, action: a.action, player: a.player_id, status: a.http_status, params: a.params }
}
```

## Action → meaning

| `action` | Player intent |
|----------|----------------|
| `games#create` | New campaign |
| `games#assign_faction` | Pick faction / hero / school |
| `games#recruit` | Buy unit/hero |
| `games#upgrade_access` | Unlock recruit tier |
| `games#dismiss` | Remove entity |
| `games#attach_hero` | Attach hero to unit |
| `games#restore_unit` | Heal models |
| `games#deploy` | Place/rotate/reserve/auto (`params["deploy_mode"]`) |
| `games#prepare_hero_draft` / `pick_hero_draft` | Upgrade draft |
| `games#prepare_round` | Prep (rare; usually inside advance) |
| `games#advance_round` | «Начать раунд» / fight |
| `battles#replay` | Replay matchup (dev) |

`deploy_mode`: `transform` | `rotate` | `reserve` | `auto`.

## Output style

When reporting to the user: chronological timeline, one line per action, highlight `http_status >= 400`. Do not dump full battle payloads — those are in [read-battle-info](../read-battle-info/SKILL.md).

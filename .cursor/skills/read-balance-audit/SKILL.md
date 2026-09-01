---
name: read-balance-audit
description: >-
  Read Musterfall balance audit dashboard via one API call or rails runner.
  Prefer curl to http://localhost:13000/api/admin/balance (Docker backend).
  Use when reviewing faction winrates, unit damage matrix, rule triggers,
  balance stats, synthetic simulation status, or the user asks about баланс /
  balance audit / winrate / damage matrix.
---

# Read Balance Audit

Вся статистика админки — **одним GET**. UI дергает тот же endpoint.

## HTTP (preferred for agents)

Backend в Docker: порт **13000** (см. `frontend/src/api/config.js`).

```bash
# все бои, последняя версия каталога
curl -s 'http://localhost:13000/api/admin/balance?matchup_type=all'

# конкретная версия каталога
curl -s 'http://localhost:13000/api/admin/balance?catalog_version_id=3&matchup_type=all'

# только bvb / pvb / pvp
curl -s 'http://localhost:13000/api/admin/balance?matchup_type=bvb'
```

Сохранить на диск для разбора:

```bash
curl -s 'http://localhost:13000/api/admin/balance?matchup_type=all' \
  | python3 -m json.tool > backend/tmp/balance_dashboard.json
```

Выборочно (jq):

```bash
curl -s 'http://localhost:13000/api/admin/balance?matchup_type=all' \
  | jq '{summary, faction_wins, top_rules: .rule_triggers[:10], top_damage: .unit_matchups[:10]}'
```

Если `connection refused` — поднять backend: `docker compose up -d backend` (см. read-battle-info про stale `server.pid`).

## Query params

| Param | Values | Default |
|-------|--------|---------|
| `matchup_type` | `all`, `pvp`, `pvb`, `bvb` | `all` |
| `catalog_version_id` | integer | latest `CatalogVersion` |

Counters для `matchup_type=all` — только строки с `matchup_type: "all"` (не смешивать с pvb/bvb).

## Response shape (top-level keys)

```json
{
  "catalog_versions": [{ "id", "content_hash", "battle_count", ... }],
  "selected_version_id": 3,
  "matchup_type": "all",
  "summary": { "battle_count", "recorded_battles", "upset_count", "upset_rate", "avg_rounds" },
  "faction_wins": [{ "faction_id", "wins", "winrate" }],
  "faction_matchups": [{ "key", "battles" }],
  "template_wins": [{ "template_id", "wins", "winrate" }],
  "unit_matchups": [{ "attacker", "target", "hits", "total_damage", "avg_damage" }],
  "damage_matrix": [{ "attacker", "target", "phase", "hits", "total_damage", "avg_damage" }],
  "rule_triggers": [{ "key", "count", "sum" }],
  "rule_results": [{ "key", "count", "sum" }],
  "action_counts": [{ "key", "count", "sum" }],
  "morale": [{ "key", "count", "sum" }],
  "contacts": [{ "key", "count", "sum" }],
  "spells": [{ "spell_key", "casts", "total_damage", "avg_damage" }],
  "models_lost": [{ "key", "count", "sum" }],
  "recent_battles": [{ "id", "matchup_type", "source", "winner_faction", "left_faction", "right_faction", "rounds", "upset", ... }],
  "simulation_runs": [{ "id", "status", "battles_completed", "config", ... }],
  "active_simulation": { ... } | null,
  "factions": ["empire", "chaos", ...]
}
```

`source` в recent_battles: `campaign` | `synthetic`. Дуэли отрядов (`POST /api/admin/balance/duels`) в аудит **не** пишутся.

## Other admin balance endpoints

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/admin/balance/backfill` | фоновый backfill campaign-боёв |
| POST | `/api/admin/balance/simulations` | старт bvb-симуляции (в аудит) |
| POST | `/api/admin/balance/simulations/:id/stop` | стоп симуляции |
| POST | `/api/admin/balance/duels` | дуэль двух template (не в аудит) — см. skill **run-unit-duels** |

## Rails runner fallback

```bash
docker exec musterfall-backend-1 bin/rails runner \
  'puts JSON.pretty_generate(Balance::Dashboard.build(matchup_type: "all"))'
```

Прямой SQL редко нужен: агрегаты в `balance_counters`, per-battle JSON в `balance_battle_rollups.metrics`.

## Code map

- API: `backend/app/controllers/api/admin/balance_controller.rb`
- Payload: `backend/app/domain/balance/dashboard.rb`
- Persist hook: `Balance::Record.from_matchup!` после campaign-боя; synthetic — `Balance::Synthetic::Play`

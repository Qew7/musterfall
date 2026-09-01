---
name: run-unit-duels
description: >-
  Run Musterfall unit-vs-unit balance duels (two army templates, no heroes).
  Prefer POST http://localhost:13000/api/admin/balance/duels (Docker backend).
  Use when comparing отряды, matchup winrate, contact front/flank/rear, or the
  user asks to запустить дуэль / unit duel / synthetic duel / бои отрядов.
---

# Run Unit Duels

**Дуэль** — N прогонов боя **двух unit-шаблонов** (без героев, без кампании). Результаты **не** пишутся в balance audit (`balance_battle_rollups` / counters).

UI: `/admin/balance/simulation` → блок «Дуэль отрядов». Агентам удобнее curl/rails runner.

## HTTP (preferred)

Backend в Docker: порт **13000** (`frontend/src/api/config.js`).

```bash
curl -s -X POST 'http://localhost:13000/api/admin/balance/duels' \
  -H 'Content-Type: application/json' \
  -d '{
    "left_template": "state_swords",
    "right_template": "rift_heavies",
    "contact": "front",
    "iterations": 100
  }' | python3 -m json.tool
```

С кастомным числом моделей (иначе — из шаблона каталога):

```bash
curl -s -X POST 'http://localhost:13000/api/admin/balance/duels' \
  -H 'Content-Type: application/json' \
  -d '{
    "left_template": "state_swords",
    "right_template": "rift_heavies",
    "left_models": 20,
    "right_models": 16,
    "contact": "flank",
    "iterations": 50
  }' | jq '{left_template, right_template, contact, left_wins, right_wins, left_winrate, avg_rounds}'
```

Если `connection refused` — `docker compose up -d backend`. Stale `server.pid` — см. read-battle-info.

## Request body

| Field | Required | Default | Notes |
|-------|----------|---------|-------|
| `left_template` | yes | — | `template_key` из каталога (напр. `state_swords`) |
| `right_template` | yes | — | то же |
| `contact` | no | `front` | `front` \| `flank` \| `rear` — стартовая позиция правого отряда |
| `iterations` | no | `1` | 1…200 (`Balance::Synthetic::Duel::MAX_ITERATIONS`) |
| `left_models` | no | из шаблона | переопределяет `models` + HP |
| `right_models` | no | из шаблона | то же |

Ошибки: `422` + `{ "error": "..." }` (нет шаблона, пустой `left_template`, и т.д.).

## Response

```json
{
  "iterations": 100,
  "left_template": "state_swords",
  "right_template": "rift_heavies",
  "contact": "front",
  "left_models": null,
  "right_models": null,
  "left_wins": 58,
  "right_wins": 42,
  "left_winrate": 0.58,
  "right_winrate": 0.42,
  "avg_rounds": 4.12
}
```

`left` / `right` — порядок в запросе, не «сильнее/слабее». RNG на каждый прогон свой (seed от `SecureRandom` в API).

## Список шаблонов отрядов

```bash
curl -s 'http://localhost:13000/api/game_catalog' \
  | jq '[.units[] | {id, name, factionId, cost, models, melee, ranged, abilities}] | sort_by(.name)'
```

Только ключи:

```bash
curl -s 'http://localhost:13000/api/game_catalog' | jq -r '.units[].id' | sort
```

Hero-шаблоны в дуэли не используют — только `units` (`kind: "unit"`).

## Rails runner (batch / reproducible seed)

```bash
docker exec musterfall-backend-1 bin/rails runner "$(cat <<'RUBY'
catalog = Sim::Catalog::Loader.load
rng = Sim::Rng::Seeded.new(42_002)
result = Balance::Synthetic::Duel.run!(
  catalog: catalog,
  config: {
    left_template: "state_swords",
    right_template: "rift_heavies",
    contact: "front",
    iterations: 100
  },
  rng: rng
)
puts JSON.pretty_generate(result)
RUBY
)"
```

Несколько матчапов подряд — цикл в том же runner; для отчёта сохранить в `backend/tmp/duel_results.json`.

## Когда что использовать

| Задача | Инструмент |
|--------|------------|
| Winrate двух отрядов, контакт | **POST /duels** или `Balance::Synthetic::Duel` |
| Агрегаты по кампании / bvb-симуляции | read-balance-audit (`GET /api/admin/balance`) |
| Один реальный бой, фазы, replay | read-battle-info |

## Code map

- API: `backend/app/controllers/api/admin/balance_controller.rb#run_duel`
- Engine: `backend/app/domain/balance/synthetic/duel.rb`
- Test: `backend/test/balance/synthetic_duel_test.rb`
- Catalog keys: `Unit#template_key`, loader `Sim::Catalog::Loader`

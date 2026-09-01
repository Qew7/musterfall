---
name: run-unit-duels
description: >-
  Run Musterfall unit-vs-unit balance duels (two army templates, no heroes).
  Prefer POST http://localhost:13000/api/admin/balance/duels (Docker backend).
  For all-vs-all matrix use POST .../duel_matrix (defaults deploy=ranged,
  random_first_turn=true). Supports deploy melee|ranged. Use when comparing
  отряды, matchup winrate, contact front/flank/rear, or запустить дуэль /
  unit duel / synthetic duel / бои отрядов / матрица отрядов.
---

# Run Unit Duels

**Дуэль** — N прогонов боя двух unit-шаблонов (без героев). Результаты → `balance_duel_runs`, не `balance_battle_rollups`.

UI: `/admin/balance/simulation`. Анализ — skill **read-balance-audit**.

## Deploy + contact + first turn

| Param | Дуэль `POST /duels` | Матрица `POST /duel_matrix` |
|-------|---------------------|-----------------------------|
| `deploy` | default **`melee`** | default **`ranged`** |
| `random_first_turn` | не в API → **false** | default **true** (не в permit, но всегда true если не передан в `normalize_config`) |
| `contact` | default `front` | default `front` |
| `iterations` | default `1` | UI: 10; morning job: **50** |

### `engagement_gap` (код: `Balance::Synthetic::Duel`)

| deploy | shooting_range | Дистанция |
|--------|----------------|-----------|
| `melee` | — | `GAP` — контакт, без заряда |
| `ranged` | 0 у обоих | `STANDOFF_GAP` (GAP + 1) |
| `ranged` | ≥1 у кого-то | `max(shooting_range)`, `STANDOFF_GAP` |

`random_first_turn: true` — `pick_turn_order` случайно swap left/right в `Simulator.call`; winrate left template не меняется.

## Рекомендуемые сценарии

| Задача | deploy | contact | iterations |
|--------|--------|---------|------------|
| **Матрица (баланс)** | `ranged` | `front` | 50–100 |
| Line infantry parity | `melee` | `front` | 50–100 |
| Elite cavalry | `melee` | `flank` | 50–100 |
| Стрелки / пушки | `ranged` | `front` | 50–100 |

При `iterations < 30` — шум, не выводы.

## Одна дуэль (sync)

```bash
# melee — default для POST /duels
curl -s -X POST 'http://localhost:13000/api/admin/balance/duels' \
  -H 'Content-Type: application/json' \
  -d '{
    "left_template": "state_swords",
    "right_template": "orc_brutes",
    "contact": "front",
    "iterations": 100
  }' | jq '{left_template, right_template, deploy, left_winrate, avg_rounds}'

# ranged — стрелок vs пехота
curl -s -X POST 'http://localhost:13000/api/admin/balance/duels' \
  -H 'Content-Type: application/json' \
  -d '{
    "left_template": "handgunners",
    "right_template": "state_swords",
    "contact": "front",
    "deploy": "ranged",
    "iterations": 100
  }'

# flank cavalry
curl -s -X POST 'http://localhost:13000/api/admin/balance/duels' \
  -H 'Content-Type: application/json' \
  -d '{
    "left_template": "boar_riders",
    "right_template": "shadow_riders",
    "contact": "flank",
    "deploy": "melee",
    "iterations": 50
  }'
```

## Request body

| Field | Default (дуэль / матрица) | Notes |
|-------|---------------------------|-------|
| `left_template`, `right_template` | required | `template_key` |
| `contact` | `front` | `front` \| `flank` \| `rear` — позиция **правого** |
| `deploy` | `melee` / **`ranged`** | см. таблицу gap выше |
| `iterations` | `1` / UI `10` | 1…200 |
| `batch_size` | — / `10` | только матрица |
| `left_models`, `right_models` | из шаблона | override models + HP |

Response: `deploy`, `contact`, `left_winrate`, `duel_run_id`.

## Матрица (async)

UI и `BalanceMorningSimulationJob` **не шлют** `deploy` — backend подставляет `ranged` + `random_first_turn: true`.

```bash
curl -s -X POST 'http://localhost:13000/api/admin/balance/duel_matrix' \
  -H 'Content-Type: application/json' \
  -d '{
    "contact": "front",
    "iterations": 50,
    "batch_size": 10
  }' | jq '.run | {id, status, matchups_total, config}'

# явно melee-матрица (редко)
curl -s -X POST 'http://localhost:13000/api/admin/balance/duel_matrix' \
  -H 'Content-Type: application/json' \
  -d '{"contact":"front","deploy":"melee","iterations":50}'

curl -s -X POST 'http://localhost:13000/api/admin/balance/duel_matrix/1/stop'
```

Пар: `N*(N-1)/2`. После `completed` → `balance:duel_tier_report` + `DEPLOY=ranged`.

## Rails runner

```bash
docker exec musterfall-backend-1 bin/rails runner "$(cat <<'RUBY'
catalog = Sim::Catalog::Loader.load
rng = Sim::Rng::Seeded.new(42_002)
result = Balance::Synthetic::Duel.run!(
  catalog: catalog,
  config: {
    left_template: "handgunners",
    right_template: "goblin_archers",
    contact: "front",
    deploy: "ranged",
    random_first_turn: true,
    iterations: 100
  },
  rng: rng
)
puts JSON.pretty_generate(result)
RUBY
)"
```

`random_first_turn` в runner — да; в `POST /duels` — только через runner, не HTTP.

## Когда что использовать

| Задача | Инструмент |
|--------|------------|
| Winrate пары | **POST /duels** / `Balance::Synthetic::Duel` |
| Вся матрица | **POST /duel_matrix** |
| Tier parity | `balance:duel_tier_report` |
| Cost vs winrate | `balance:cost_audit` |
| Diff версий | `balance:compare_versions` |
| Campaign / bvb | `Balance::Dashboard` (read-balance-audit) |

## Code map

- Engine: `backend/app/domain/balance/synthetic/duel.rb` — `GAP`, `STANDOFF_GAP`, `engagement_gap`, `pick_turn_order`
- Matrix: `backend/app/domain/balance/duel_matrix.rb` — defaults `deploy: ranged`, `random_first_turn: true`
- Job: `backend/app/jobs/balance_duel_matrix_batch_job.rb`
- Morning: `backend/app/jobs/balance_morning_simulation_job.rb` — `DUEL_MATRIX_CONFIG`
- Stats: `backend/app/domain/balance/duel_runs.rb`
- API: `backend/app/controllers/api/admin/balance_controller.rb`
- Tests: `synthetic_duel_test.rb`, `duel_matrix_test.rb`, `balance_morning_simulation_job_test.rb`

Catalog: `ArmyTemplate#template_key`, `Sim::Catalog::Loader`.

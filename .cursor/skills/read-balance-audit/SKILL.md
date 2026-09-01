---
name: read-balance-audit
description: >-
  Read Musterfall balance audit dashboard via one API call or rails runner.
  Prefer curl to http://localhost:13000/api/admin/balance (Docker backend).
  Unit duels: GET .../balance/units. Analysis rake tasks: duel_tier_report,
  cost_audit, compare_versions. Balance::TierReport, CostAudit, CompareVersions.
  Matrix duels default deploy=ranged. Use when reviewing faction winrates, unit
  damage matrix, rule triggers, balance stats, tier winrate parity, cost audit,
  version diff, or баланс / balance audit.
---

# Read Balance Audit

Две страницы админки — **два GET**:

| UI | Endpoint | Данные |
|----|----------|--------|
| Статистика сражений | `GET /api/admin/balance` | кампания + bvb (`balance_battle_rollups`) |
| Статистика отрядов | `GET /api/admin/balance/units` | дуэли (`balance_duel_runs`) |

Query для units: `catalog_version_id`, `contact`, `deploy`.

**Важно:** матрица (UI-кнопка + `BalanceMorningSimulationJob`) пишет runs с `deploy=ranged`, `random_first_turn=true`. Отчёты по матрице — с `DEPLOY=ranged`.

## Баланс-цели

| Tier | Цель | Как мерить |
|------|------|------------|
| **line** | ≈50/50 line vs line | матрица `ranged/front` |
| **elite** | разброс OK | + ручная дуэль `melee/flank` для cavalry |
| **rare** | RPS 90/10 | матрица `ranged/front` (пушки на range) |

**Мало итераций = шум**: `< 30` (`TierReport::LOW_SAMPLE_ITERATIONS`) — не тюнить.

**Цена ≠ tier**: `recruit_tier` vs `computed_template_cost`.

## Deploy: как читать дистанцию (`engagement_gap`)

| deploy | shooting_range | Gap |
|--------|----------------|-----|
| `melee` | любой | `GAP` — контакт |
| `ranged` | 0 у обоих | `STANDOFF_GAP` (= GAP + 1) — короткий разрыв, не рубка вплотную |
| `ranged` | есть стрелок/пушка | `max(shooting_range)`, `STANDOFF_GAP` |

**random_first_turn** (только матрица): каждый прогон случайно меняет порядок `Simulator.call`; `left_winrate` всё равно считается для **left_template**.

## Ruby-инструменты

### Tier report

```bash
docker exec musterfall-backend-1 bin/rails balance:duel_tier_report
docker exec musterfall-backend-1 env CONTACT=front DEPLOY=ranged bin/rails balance:duel_tier_report
```

`Balance::TierReport.build(contact:, deploy:)` → `by_tier`, `cross_tier_leaks`, `low_sample_pairs`, `cost_outliers`.

### Cost audit

```bash
docker exec musterfall-backend-1 env DEPLOY=ranged bin/rails balance:cost_audit
```

Verdicts: `overcosted_weak`, `undercosted_strong`, `overcosted_but_wins`, `cheap_but_loses`, `overperformer`, `underperformer`, `fair`, `low_sample`.

### Compare versions

```bash
docker exec musterfall-backend-1 env FROM=5 TO=6 DEPLOY=ranged bin/rails balance:compare_versions
```

`significant` — delta ≥10% при достаточных iterations с обеих сторон.

### Workflow «помоги с балансом»

1. `GET /units` → `duel_matrix_runs[0].config` (`deploy`, `iterations`, `random_first_turn`).
2. `balance:duel_tier_report` + `DEPLOY=ranged` (если смотрим матрицу).
3. `balance:cost_audit`.
4. После патча — новая матрица → `balance:compare_versions FROM=… TO=…`.
5. `Balance::Dashboard` → `rule_triggers` / `rule_results`.
6. Предложения — **без правок**, пока пользователь явно не попросил.

## HTTP

```bash
curl -s 'http://localhost:13000/api/admin/balance?matchup_type=all'
curl -s 'http://localhost:13000/api/admin/balance/units?deploy=ranged&contact=front'
curl -s 'http://localhost:13000/api/admin/balance/units?catalog_version_id=6'
```

## Rails runner

```bash
docker exec musterfall-backend-1 bin/rails runner \
  'puts JSON.pretty_generate(Balance::Dashboard.build(matchup_type: "all"))'

docker exec musterfall-backend-1 bin/rails runner \
  'puts JSON.pretty_generate(Balance::DuelDashboard.build(deploy: "ranged"))'

docker exec musterfall-backend-1 bin/rails runner \
  'puts JSON.pretty_generate(Balance::CostAudit.build(deploy: "ranged"))'
```

## Admin endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/admin/balance` | бои |
| GET | `/api/admin/balance/units` | дуэли (`contact`, `deploy`) |
| POST | `/api/admin/balance/duels` | одна дуэль (default `deploy=melee`) |
| POST | `/api/admin/balance/duel_matrix` | матрица (default `deploy=ranged`, `random_first_turn=true`) |
| POST | `/api/admin/balance/simulations` | bvb-симуляция |

Запуск дуэлей — skill **run-unit-duels**.

## Code map

| Module | Rake | Назначение |
|--------|------|------------|
| `Balance::TierReport` | `balance:duel_tier_report` | tier parity, cross-tier |
| `Balance::CostAudit` | `balance:cost_audit` | cost vs winrate |
| `Balance::CompareVersions` | `balance:compare_versions` | diff версий каталога |
| `Balance::DuelRuns` | — | фильтр + агрегация runs |
| `Balance::Synthetic::Duel` | — | engine: `engagement_gap`, `pick_turn_order` |
| `Balance::DuelDashboard` | — | API payload units |
| `Balance::Dashboard` | — | API payload battles |

Rake: `backend/lib/tasks/balance.rake`. Утренний job: `BalanceMorningSimulationJob` (`DUEL_MATRIX_CONFIG`: ranged, 50 iter).

## Чего ещё нет

- `Balance::RuleAudit` — rule_triggers по tier
- multi-deploy отчёт одним rake (melee + ranged)

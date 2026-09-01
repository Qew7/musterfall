---
name: read-balance-audit
description: >-
  Read Musterfall balance audit via rake tasks. Army snapshot: balance:battle_report
  or GET .../balance/summary. Unit duels: balance:duel_tier_report. Rule semantics:
  balance:rule_index (# rule: headers). Balance::BattleReport, TierReport, RuleCatalog.
  Matrix duels default deploy=ranged. Use for faction winrates, tier parity, upset rate,
  cost audit, rule impact, or баланс / balance audit.
---

# Read Balance Audit

## Два контура данных

| Контур | Что это | Лёгкий путь |
|--------|---------|-------------|
| **Армия vs армия** | Кампания, bvb-симы (`balance_battle_rollups`) | `balance:battle_report` или `GET /balance/summary` |
| **Юнит vs юнит** | Матрица дуэлей (`balance_duel_runs`) | `balance:duel_tier_report` |

**Не тянуть** полный `GET /balance` (~430 KB) или `GET /units` (~100 KB) — только если нужны damage_matrix, rule_triggers, сырые matchups.

## Армии / кампания

```bash
docker exec musterfall-backend-1 env MATCHUP_TYPE=all bin/rails balance:battle_report
docker exec musterfall-backend-1 env MATCHUP_TYPE=pvp DEPLOY=ranged bin/rails balance:battle_report
```

```bash
curl -s 'http://localhost:13000/api/admin/balance/summary?matchup_type=all'
curl -s 'http://localhost:13000/api/admin/balance/summary?matchup_type=pvp&deploy=ranged'
```

Возвращает:

- **battles.summary** — battle_count, upset_count, upset_rate, avg_rounds
- **battles.faction_wins** — винрейт фракций
- **duels.summary** — iterations, upset_count/rate по дуэлям (фильтр `CONTACT`/`DEPLOY`)

`MATCHUP_TYPE`: `all` | `pvp` | `pvb` | `bvb`.

Конкретный бой (replay, фазы) — skill **read-battle-info**, не balance API.

## Дуэли / line-elite-rare

```bash
docker exec musterfall-backend-1 env CONTACT=front DEPLOY=ranged bin/rails balance:duel_tier_report
```

Содержит: `by_tier`, `worst_pairs`, `cross_tier_leaks`, `cost_outliers`, **upset** в шапке.

`cost_audit` отдельно — только если нужен полный verdict-лист.

Матрица: `deploy=ranged`, `random_first_turn=true`.

## Правила боя

Не гадать по имени ability — читать `# rule:` через индекс:

```bash
docker exec musterfall-backend-1 bin/rails balance:rule_index
docker exec musterfall-backend-1 env KEYS=shieldwall,fear,poison bin/rails balance:rule_index
```

Формат в `rules/<rule>/<phase>.rb` — **только механика**, без привязки к дуэлям/кампании:

```ruby
# rule: shieldwall | melee | Incoming frontal charge damage ×0.75 (front vector, charged_distance > 0).
```

## Workflow «помоги с балансом»

**Фракции / кампания:**

1. `balance:battle_report` или `GET /balance/summary`
2. При необходимости `rule_index KEYS=…` для abilities из winning/losing roster

**Tier parity (1v1):**

1. `balance:duel_tier_report` + `DEPLOY=ranged`
2. Outlier-юниты → abilities из seeds → `rule_index KEYS=…`
3. Сравнить винрейт с concept из rule_index

5. Предложения — **без правок**, пока пользователь явно не попросил.

## Upset

Победа стороны с **меньшей стоимостью** (армия: cost ростра; дуэль: template cost).

- Армии: `battles.summary.upset_count` / `upset_rate`
- Дуэли: в шапке `duel_tier_report` и в `duels.summary` у `battle_report`

## Баланс-цели

| Tier | Цель | Как мерить |
|------|------|------------|
| **line** | ≈50/50 line vs line | матрица `ranged/front` |
| **elite** | разброс OK | + ручная дуэль `melee/flank` для кавалерии |
| **rare** | RPS 90/10 | матрица `ranged/front` |

**Мало итераций = шум**: `< 30` (`TierReport::LOW_SAMPLE_ITERATIONS`) — не тюнить.

## Rake-задачи

```bash
docker exec musterfall-backend-1 env MATCHUP_TYPE=all bin/rails balance:battle_report
docker exec musterfall-backend-1 env CONTACT=front DEPLOY=ranged bin/rails balance:duel_tier_report
docker exec musterfall-backend-1 env DEPLOY=ranged bin/rails balance:cost_audit
docker exec musterfall-backend-1 env FROM=5 TO=6 DEPLOY=ranged bin/rails balance:compare_versions
docker exec musterfall-backend-1 bin/rails balance:rule_index
```

## Code map

| Module | Rake / HTTP | Назначение |
|--------|-------------|------------|
| `Balance::BattleReport` | `balance:battle_report`, `GET /balance/summary` | армии: faction_wins + upset |
| `Balance::TierReport` | `balance:duel_tier_report` | tier parity, duel upset |
| `Balance::CostAudit` | `balance:cost_audit` | cost vs winrate |
| `Balance::RuleCatalog` | `balance:rule_index` | `# rule:` из кода |
| `Balance::Dashboard` | `GET /balance` | полный payload (тяжёлый) |
| `Balance::DuelDashboard` | `GET /balance/units` | сырой JSON матрицы |

Запуск дуэлей — **run-unit-duels**. Правила — **battle-rules**.

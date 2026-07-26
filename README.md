# Musterfall

Монорепа для автобатлера в духе фэнтези-армий.

Игровой движок (кампания, рекрут, деплой, бой, мораль) авторитетен на Rails (`backend/app/domain/sim`). Frontend показывает UI, optimistic-команды и replay; исходы раундов считаются на сервере.

## Один запуск через Docker

```bash
docker compose up --build
```

После старта:

- frontend: http://localhost:5173
- backend: http://localhost:13000/api/status

Порт backend на Mac настраивается через `.env` (`BACKEND_HOST_PORT`, по умолчанию 13000) — чтобы не пересекаться с другими проектами на 3000.

База доступна только внутри Docker-сети (`db:5432`), порт на Mac не публикуется.

Остановка:

```bash
docker compose down
```

## Структура

- `backend` — Rails 8 API + domain `Sim` (каталог, кампания, бой) + нормализованное состояние кампании в PostgreSQL
- `frontend` — React + Vite клиент (optimistic command queue, placement preview, battle replay)

## Требования

- Ruby 3.2+
- Rails 8+
- Node.js 20/22/24 LTS
- PostgreSQL 14+

## Запуск backend

```bash
cd backend
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/rails server
```

Backend будет доступен на `http://localhost:3000`.

Проверка API:

```bash
curl http://localhost:3000/api/status
curl http://localhost:3000/api/game_catalog
```

Основные command endpoints:

- `POST /api/games` — создать кампанию
- `POST /api/games/:id/assign_faction|recruit|dismiss|attach_hero|deploy|...`
- `POST /api/games/:id/prepare_round`
- `POST /api/games/:id/advance_round` — серверная симуляция раунда

## Запуск frontend

```bash
cd frontend
npm install
npm run dev
```

Frontend будет доступен на `http://localhost:5173`.

Если backend работает не на `http://localhost:3000`, задайте переменную окружения:

```bash
VITE_API_BASE_URL=http://localhost:3000 npm run dev
```

Для Docker frontend обычно указывает на `http://localhost:13000`.

## Тесты backend

```bash
cd backend
RAILS_ENV=test bin/rails db:prepare db:seed
bin/rails test
```

# Musterfall

Монорепа для автобатлера в духе фэнтези-армий.

## Один запуск через Docker

```bash
docker compose up --build
```

После старта:

- frontend: http://localhost:5173
- backend: http://localhost:3000/api/status
- postgres: localhost:5432

Остановка:

```bash
docker compose down
```

## Структура

- `backend` - Rails 8 API с PostgreSQL
- `frontend` - React + Vite клиент

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
bin/rails server
```

Backend будет доступен на `http://localhost:3000`.

Проверка API:

```bash
curl http://localhost:3000/api/status
```

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
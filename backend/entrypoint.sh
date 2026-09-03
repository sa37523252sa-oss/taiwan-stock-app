#!/bin/sh

set -e

DB_PATH="${DB_PATH:-/app/stocks.db}"

mkdir -p "$(dirname "$DB_PATH")"

export DB_PATH

exec uvicorn main:app --host 0.0.0.0 --port "${PORT:-8080}"

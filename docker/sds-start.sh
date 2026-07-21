#!/bin/sh
# SDS patch: single container entrypoint so Railway needs no custom start
# command (nothing for the platform to mangle). Runs Sidekiq and the Rails web
# server together in one container.
#
# The database is expected to be already prepared and migrated (deploying the
# same Chatwoot version onto an existing DB). Set SDS_RUN_DB_PREPARE=true when
# bootstrapping a fresh database.
set -e

if [ "${SDS_RUN_DB_PREPARE}" = "true" ]; then
  echo "[sds-start] preparing database"
  bundle exec rails db:chatwoot_prepare
  bundle exec rails db:migrate
fi

echo "[sds-start] starting sidekiq"
bundle exec sidekiq -C config/sidekiq.yml &

echo "[sds-start] starting rails on port ${PORT:-3000}"
exec bundle exec rails s -b 0.0.0.0 -p "${PORT:-3000}"

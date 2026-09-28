#!/bin/sh
# Jenkins container runs this against the local Docker Desktop daemon.
set -eu
image="${1:?usage: local-deploy.sh IMAGE_REF}"
: "${DB_USER:?Create orders-db-app Jenkins credential}"
: "${DB_PASSWORD:?Create orders-db-app Jenkins credential}"
previous="$(docker inspect --format='{{.Config.Image}}' loadtest-order 2>/dev/null || true)"
start_container() {
  docker run -d --name loadtest-order --network loadtest-lab --network-alias order \
    -p 127.0.0.1:8080:8080 \
    -e DB_URL=jdbc:postgresql://postgres:5432/loadtest \
    -e DB_USER -e DB_PASSWORD -e LOG_DIR=/var/log/loadtest -e APP_REVISION="$1" \
    -v loadtest-order-logs:/var/log/loadtest "$1" >/dev/null
}
ready() {
  i=0
  while [ "$i" -lt 45 ]; do
    if curl -fsS --max-time 2 http://order:8080/actuator/health/readiness 2>/dev/null | grep -q '"status":"UP"'; then
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  return 1
}
docker rm -f loadtest-order >/dev/null 2>&1 || true
start_container "$image"
if ready; then
  echo "Local deployment ready: $image"
  exit 0
fi
echo 'New container did not become ready. Recent logs:' >&2
docker logs --tail=50 loadtest-order >&2 || true
docker rm -f loadtest-order >/dev/null 2>&1 || true
if [ -n "$previous" ]; then
  echo "Attempting rollback to: $previous" >&2
  start_container "$previous"
  ready || echo 'Rollback container is also unhealthy' >&2
fi
exit 1

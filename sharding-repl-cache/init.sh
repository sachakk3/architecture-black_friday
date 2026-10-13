#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

wait_for_mongos() {
  local service="$1"
  local port="$2"
  local retries=40
  local delay=2

  echo "Waiting for ${service}:${port} to accept connections..."
  for ((i=1; i<=retries; i++)); do
    if docker compose exec -T "$service" mongosh --port "$port" --quiet --eval "db.adminCommand({ ping: 1 }).ok" >/dev/null 2>&1; then
      echo "${service}:${port} is ready"
      return 0
    fi
    sleep "$delay"
  done

  echo "ERROR: ${service}:${port} did not become ready in time"
  docker compose logs --tail=120 "$service" || true
  return 1
}

echo "[1/7] Starting containers (with Redis cache)"
docker compose up -d

echo "[2/7] Initializing config server replica set"
docker compose exec -T configSrv_repl mongosh --port 27017 --quiet <<'EOF'
try {
  rs.status();
  print('config_server already initialized');
} catch (e) {
  rs.initiate({
    _id: 'config_server',
    configsvr: true,
    members: [{ _id: 0, host: 'configSrv_repl:27017' }]
  });
}
EOF

echo "[3/7] Initializing shard1 replica set (3 members)"
docker compose exec -T shard1_1_repl mongosh --port 27018 --quiet <<'EOF'
try {
  rs.status();
  print('shard1 already initialized');
} catch (e) {
  rs.initiate({
    _id: 'shard1',
    members: [
      { _id: 0, host: 'shard1_1_repl:27018' },
      { _id: 1, host: 'shard1_2_repl:27018' },
      { _id: 2, host: 'shard1_3_repl:27018' }
    ]
  });
}
EOF

echo "[4/7] Initializing shard2 replica set (3 members)"
docker compose exec -T shard2_1_repl mongosh --port 27019 --quiet <<'EOF'
try {
  rs.status();
  print('shard2 already initialized');
} catch (e) {
  rs.initiate({
    _id: 'shard2',
    members: [
      { _id: 0, host: 'shard2_1_repl:27019' },
      { _id: 1, host: 'shard2_2_repl:27019' },
      { _id: 2, host: 'shard2_3_repl:27019' }
    ]
  });
}
EOF

echo "[5/7] Adding shards and enabling sharding"
wait_for_mongos mongos_router 27020
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
const shardIds = (sh.status().shards || []).map(s => s._id);
if (!shardIds.includes('shard1')) {
  printjson(sh.addShard('shard1/shard1_1_repl:27018,shard1_2_repl:27018,shard1_3_repl:27018'));
}
if (!shardIds.includes('shard2')) {
  printjson(sh.addShard('shard2/shard2_1_repl:27019,shard2_2_repl:27019,shard2_3_repl:27019'));
}
try { printjson(sh.enableSharding('somedb')); } catch (e) { print('somedb already sharded'); }
try { printjson(sh.shardCollection('somedb.helloDoc', { name: 'hashed' })); } catch (e) { print('collection already sharded'); }
printjson(sh.status());
EOF

echo "[6/7] Seeding test data"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
use somedb
const existing = db.helloDoc.countDocuments();
if (existing === 0) {
  for (let i = 0; i < 1000; i++) {
    db.helloDoc.insertOne({ age: i, name: 'ly' + i });
  }
  print('Inserted 1000 documents');
} else {
  print('Skip insert, existing documents: ' + existing);
}
EOF

echo "[7/7] Counts by shard + API check"
docker compose exec -T shard1_1_repl mongosh --port 27018 --quiet <<'EOF'
use somedb
print('shard1 primary count=' + db.helloDoc.countDocuments())
EOF

docker compose exec -T shard2_1_repl mongosh --port 27019 --quiet <<'EOF'
use somedb
print('shard2 primary count=' + db.helloDoc.countDocuments())
EOF

curl -i --max-time 10 http://localhost:8080/ || true

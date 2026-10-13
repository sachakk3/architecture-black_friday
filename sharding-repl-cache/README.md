Инициализация шард-кластера MongoDB (2 шарда, каждый с репликацией 1 primary + 2 secondary)

1. Поднять контейнеры:

```bash
docker compose up -d
```

2. Инициализировать replica set сервера конфигурации:

```bash
docker compose exec -T configSrv_repl mongosh --port 27017 --quiet <<'EOF'
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv_repl:27017" }]
})
EOF
```

3. Инициализировать replica set `shard1` (3 узла):

```bash
docker compose exec -T shard1_1_repl mongosh --port 27018 --quiet <<'EOF'
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1_1_repl:27018" },
    { _id: 1, host: "shard1_2_repl:27018" },
    { _id: 2, host: "shard1_3_repl:27018" }
  ]
})
EOF
```

4. Инициализировать replica set `shard2` (3 узла):

```bash
docker compose exec -T shard2_1_repl mongosh --port 27019 --quiet <<'EOF'
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2_1_repl:27019" },
    { _id: 1, host: "shard2_2_repl:27019" },
    { _id: 2, host: "shard2_3_repl:27019" }
  ]
})
EOF
```

5. Добавить шарды в `mongos`, включить шардирование БД и коллекции:

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
sh.addShard("shard1/shard1_1_repl:27018,shard1_2_repl:27018,shard1_3_repl:27018")
sh.addShard("shard2/shard2_1_repl:27019,shard2_2_repl:27019,shard2_3_repl:27019")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { name: "hashed" })
sh.status()
EOF
```

6. Наполнить базу `somedb` тестовыми данными:

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
use somedb
for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i })
}
EOF
```

7. Проверить количество документов на primary каждого шарда:

```bash
docker compose exec -T shard1_1_repl mongosh --port 27018 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
EOF
```

```bash
docker compose exec -T shard2_1_repl mongosh --port 27019 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
EOF
```

Проверка API:

```bash
curl -i http://localhost:8080/
```

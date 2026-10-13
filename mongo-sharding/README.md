Инициализация шард-кластера MongoDB

1. Инициализировать replica set сервера конфигурации:

```bash
docker compose exec -T configSrv mongosh --port 27017 --quiet <<'EOF'
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27017" }]
})
EOF
```

2. Инициализировать replica set `shard1`:

```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "shard1:27018" }]
})
EOF
```

3. Инициализировать replica set `shard2`:

```bash
docker compose exec -T shard2 mongosh --port 27019 --quiet <<'EOF'
rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "shard2:27019" }]
})
EOF
```

4. Добавить шарды в `mongos` и включить шардирование для базы `somedb`:

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
sh.addShard("shard1/shard1:27018")
sh.addShard("shard2/shard2:27019")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
sh.status()
EOF
```

5. Наполнить базу `somedb` тестовыми данными:

```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insert({ age: i, name: "ly" + i })
EOF
```

6. Проверить количество документов на каждом шарде:

```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
EOF
```

```bash
docker compose exec -T shard2 mongosh --port 27019 --quiet <<'EOF'
use somedb
db.helloDoc.countDocuments()
EOF
```

Проверка API:

```bash
curl -i http://localhost:8080/
```

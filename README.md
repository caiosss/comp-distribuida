# Testes de Carga — WordPress + Locust

## Estrutura de arquivos

```
.
├── docker-compose.yml
├── nginx/
│   └── nginx.conf
├── locust/
│   ├── locustfile.py
│   └── resultados/          ← CSVs gerados pelo Locust
└── run_tests.sh
```

---

## 1. Pré-requisito: criar os posts no WordPress

Antes de qualquer teste, suba o ambiente com 1 instância e crie os posts:

```bash
docker compose up -d --scale wordpress=1
```

Acesse `http://localhost/wp-admin` e crie os 3 posts com os seguintes conteúdos:

| Post | Conteúdo exigido |
|------|-----------------|
| Post 1 | Imagem de ~1MB inserida no corpo |
| Post 2 | Texto de ~400KB (pode usar Lorem Ipsum gerado) |
| Post 3 | Imagem de ~300KB inserida no corpo |

Os slugs já estão configurados em `locust/locustfile.py`:

```python
URL_CENARIO_1 = "/2026/04/27/resenhas/"           # post com imagem ~1MB
URL_CENARIO_2 = "/2026/04/27/this-is-elon-musk/"  # post com texto ~400KB
URL_CENARIO_3 = "/2026/04/27/13/"                 # post com imagem ~300KB
```

Se criar novos posts ou os slugs mudarem, atualize essas variáveis.

---

## 2. Controle do número de instâncias

O número de instâncias do WordPress é controlado pelo flag `--scale`:

```bash
# 1 instância
docker compose up -d --scale wordpress=1

# 3 instâncias
docker compose up -d --scale wordpress=3

# 5 instâncias
docker compose up -d --scale wordpress=5
```

O nginx descobre automaticamente as réplicas via DNS interno do Docker.
Para verificar o balanceamento, observe o header `X-Upstream` nas respostas HTTP.

---

## 3. Executar testes manualmente (modo UI)

```bash
docker compose up -d --scale wordpress=N
```

Acesse `http://localhost:8089`, configure o número de usuários e a spawn rate,
inicie o teste e exporte os resultados via **Download Data → CSV**.

O cenário ativo é controlado pela variável de ambiente `CENARIO` (1, 2 ou 3).
O valor padrão é `1`. Para trocar, edite o `command` no `docker-compose.yml`
ou exporte antes de subir:

```bash
CENARIO=2 docker compose up -d --scale wordpress=N
```

---

## 4. Executar testes automatizados (todos os cenários)

```bash
chmod +x run_tests.sh
./run_tests.sh
```

O script roda automaticamente todas as combinações:
- Cenários: 1, 2, 3 (selecionados via variável `CENARIO` passada ao container)
- Usuários: 10, 100, 1000
- Instâncias: 1, 3, 5

Os CSVs são salvos em `locust/resultados/` com nomenclatura:

```
cenario{N}_{I}inst_{U}u_stats.csv
cenario{N}_{I}inst_{U}u_stats_history.csv
cenario{N}_{I}inst_{U}u_failures.csv
```

---

## 5. Derrubar o ambiente

```bash
docker compose down      # mantém volumes (dados do WordPress preservados)
docker compose down -v   # remove volumes também (reset completo)
```
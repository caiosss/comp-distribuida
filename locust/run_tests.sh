#!/bin/bash
# =============================================================================
# run_tests.sh — Executa todas as combinações de teste automaticamente:
#   - 3 cenários de conteúdo (selecionados via variável CENARIO no locustfile)
#   - 3 quantidades de usuários: 10, 100, 1000
#   - 3 quantidades de instâncias WordPress: 1, 3, 5
#
# Uso:
#   chmod +x run_tests.sh
#   ./run_tests.sh
# =============================================================================

set -e

USUARIOS=(10 100 1000)
INSTANCIAS=(1 3 5)
CENARIOS=(1 2 3)
DURACAO="60s"
SPAWN_RATE=10
RESULTADOS_DIR="./locust/resultados"

mkdir -p "$RESULTADOS_DIR"

for instancias in "${INSTANCIAS[@]}"; do
    echo ""
    echo "======================================================"
    echo " Subindo $instancias instância(s) do WordPress..."
    echo "======================================================"

    docker compose up -d --scale wordpress="$instancias" mysql nginx wordpress
    echo " Aguardando estabilização (20s)..."
    sleep 20

    for cenario in "${CENARIOS[@]}"; do
        for usuarios in "${USUARIOS[@]}"; do
            PREFIXO="cenario${cenario}_${instancias}inst_${usuarios}u"
            echo " Rodando: cenário $cenario | $instancias instância(s) | $usuarios usuários..."

            docker compose run --rm \
                -e CENARIO="$cenario" \
                locust \
                -f /mnt/locust/locustfile.py \
                --host=http://nginx \
                --headless \
                -u "$usuarios" \
                -r "$SPAWN_RATE" \
                --run-time "$DURACAO" \
                --csv="/mnt/locust/resultados/${PREFIXO}" \
                --csv-full-history

            echo " Salvo: ${PREFIXO}_stats.csv"
            sleep 5
        done
    done

    echo " Derrubando instâncias do WordPress..."
    docker compose stop wordpress
    docker compose rm -f wordpress
done

echo ""
echo "======================================================"
echo " Todos os testes concluídos!"
echo " Resultados em: $RESULTADOS_DIR"
echo "======================================================"
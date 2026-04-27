# =============================================================================
# run_tests.ps1 — Executa todas as combinações de teste automaticamente:
#   - 3 cenários de conteúdo (selecionados via variável CENARIO no locustfile)
#   - 3 quantidades de usuários: 100, 4000, 8000
#   - 3 quantidades de instâncias WordPress: 1, 3, 5
#
# Spawn rate: 200 usuários/s
# Duração: calculada para que exatamente metade do tempo seja em carga máxima.
#   Fórmula: run_time = 2 × (usuarios / spawn_rate)
#   Exemplo com 8000u e spawn 200/s → ramp-up = 40s → run_time = 80s
#
# Uso (PowerShell):
#   .\run_tests.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

$USUARIOS       = @(100, 4000, 8000)
$INSTANCIAS     = @(1, 3, 5)
$CENARIOS       = @(1, 2, 3)
$SPAWN_RATE     = 200
$RESULTADOS_DIR = "./locust/resultados"

New-Item -ItemType Directory -Force -Path $RESULTADOS_DIR | Out-Null

foreach ($instancias in $INSTANCIAS) {
    Write-Host ""
    Write-Host "======================================================"
    Write-Host " Subindo $instancias instancia(s) do WordPress..."
    Write-Host "======================================================"

    docker compose up -d --scale wordpress=$instancias mysql nginx wordpress

    Write-Host " Aguardando estabilizacao (20s)..."
    Start-Sleep -Seconds 20

    foreach ($cenario in $CENARIOS) {
        foreach ($usuarios in $USUARIOS) {

            # Duração = 2 × ramp-up, garantindo 50% do tempo em carga máxima.
            # Ramp-up (s) = usuarios / spawn_rate
            $rampUp  = [math]::Ceiling($usuarios / $SPAWN_RATE)
            $DURACAO = "${( $rampUp * 2 )}s"

            $PREFIXO = "cenario${cenario}_${instancias}inst_${usuarios}u"
            Write-Host ""
            Write-Host " Rodando : cenario $cenario | $instancias instancia(s) | $usuarios usuarios"
            Write-Host " Ramp-up : ${rampUp}s  |  Duracao total: $DURACAO  |  Carga maxima: ${rampUp}s"

            docker compose run --rm `
                -e CENARIO="$cenario" `
                locust `
                -f /mnt/locust/locustfile.py `
                --host=http://nginx `
                --headless `
                -u $usuarios `
                -r $SPAWN_RATE `
                --run-time $DURACAO `
                --csv="/mnt/locust/resultados/${PREFIXO}" `
                --csv-full-history

            Write-Host " Salvo: ${PREFIXO}_stats.csv"
            Start-Sleep -Seconds 5
        }
    }

    Write-Host ""
    Write-Host " Derrubando instancias do WordPress..."
    docker compose stop wordpress
    docker compose rm -f wordpress
}

Write-Host ""
Write-Host "======================================================"
Write-Host " Todos os testes concluidos!"
Write-Host " Resultados em: $RESULTADOS_DIR"
Write-Host "======================================================"
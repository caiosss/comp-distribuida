# =============================================================================
# run_tests.ps1 — Executa todas as combinações de teste automaticamente:
#   - 4 cenários de conteúdo (1-3 individuais + 4 híbrido round-robin)
#   - 3 quantidades de usuários: 100, 900, 2000
#   - 3 quantidades de instâncias WordPress: 1, 3, 5
#
# Spawn rate: 100 usuários/s
# Duração: ramp_up + max(5, ramp_up), garantindo mínimo de 5s em carga máxima.
#   Ramp-up (s) = ceil(usuarios / spawn_rate)
#   Exemplo com 2000u e spawn 100/s → ramp-up = 20s → run_time = 40s
#
# Uso (PowerShell):
#   .\run_tests.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

$USUARIOS       = @(100, 200, 900)
$INSTANCIAS     = @(1, 3, 5)
$CENARIOS       = @(1, 2, 3, 4)
$SPAWN_RATE     = 100
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

            $rampUp   = [math]::Ceiling($usuarios / $SPAWN_RATE)
            $sustained = [math]::Max(5, $rampUp)
            $DURACAO  = "$($rampUp + $sustained)s"

            $PREFIXO = "cenario${cenario}_${instancias}inst_${usuarios}u"
            Write-Host ""
            Write-Host " Rodando : cenario $cenario | $instancias instancia(s) | $usuarios usuarios"
            Write-Host " Ramp-up : ${rampUp}s  |  Max: ${sustained}s  |  Total: $DURACAO"

            docker compose run --rm `
                -e CENARIO="$cenario" `
                locust `
                -f /mnt/locust/locustfile.py `
                --host=http://nginx `
                --headless `
                -u $usuarios `
                -r $SPAWN_RATE `
                --run-time $DURACAO `
                --csv="/mnt/locust/resultados/${PREFIXO}"

            Remove-Item -Force -ErrorAction SilentlyContinue "${RESULTADOS_DIR}/${PREFIXO}_failures.csv"
            Remove-Item -Force -ErrorAction SilentlyContinue "${RESULTADOS_DIR}/${PREFIXO}_exceptions.csv"
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
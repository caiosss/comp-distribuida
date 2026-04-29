# =============================================================================
# run_tests.ps1 — Executa todas as combinações de teste automaticamente:
#   - 4 cenários de conteúdo (1-3 individuais + 4 híbrido round-robin)
#   - 3 quantidades de usuários: 500, 2000, 4000
#   - 3 quantidades de instâncias WordPress: 1, 3, 5
#
# Spawn rate: 50 usuários/s
# Duração: ramp_up + max(30, ramp_up), garantindo mínimo de 30s em carga máxima.
#   Ramp-up (s) = ceil(usuarios / spawn_rate)
#   Exemplo com 4000u e spawn 50/s → ramp-up = 80s → run_time = 110s
#
# Uso (PowerShell):
#   .\locust\run_tests.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

$USUARIOS       = @(100, 200, 300)
$INSTANCIAS     = @(1, 3, 5)
$CENARIOS       = @(1, 2, 3, 4)
$SPAWN_RATE     = 50
$RESULTADOS_DIR = "./locust/resultados"

$totalTestes  = $INSTANCIAS.Count * $CENARIOS.Count * $USUARIOS.Count
$testeAtual   = 0

New-Item -ItemType Directory -Force -Path $RESULTADOS_DIR | Out-Null

foreach ($instancias in $INSTANCIAS) {
    Write-Host ""
    Write-Host ">>> Subindo $instancias instancia(s) do WordPress..."
    docker compose up -d --scale wordpress=$instancias mysql nginx wordpress | Out-Null

    Write-Host "    Aguardando WordPress responder (max 5min)..."
    $pronto = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 5
        try {
            $r = Invoke-WebRequest -Uri "http://localhost/" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
            if ($r.StatusCode -lt 500) { $pronto = $true; break }
        } catch { }
    }
    if ($pronto) { Write-Host "    WordPress pronto." }
    else         { Write-Host "    AVISO: WordPress pode nao estar pronto." }

    foreach ($usuarios in $USUARIOS) {
        foreach ($cenario in $CENARIOS) {
            $testeAtual++

            $rampUp    = [math]::Ceiling($usuarios / $SPAWN_RATE)
            $sustained = [math]::Max(30, $rampUp)
            $DURACAO   = "$($rampUp + $sustained)s"
            $PREFIXO   = "cenario${cenario}_${instancias}inst_${usuarios}u"

            Write-Host ""
            Write-Host "[$testeAtual/$totalTestes] Iniciando: cenario $cenario | ${instancias} inst | ${usuarios}u | duracao ${DURACAO}"

            docker compose run --rm `
                -e CENARIO="$cenario" `
                locust `
                -f /mnt/locust/locustfile.py `
                --host=http://nginx `
                --headless `
                -u $usuarios `
                -r $SPAWN_RATE `
                --run-time $DURACAO `
                --csv="/mnt/locust/resultados/${PREFIXO}" | Out-Null

            Remove-Item -Force -ErrorAction SilentlyContinue "${RESULTADOS_DIR}/${PREFIXO}_failures.csv"
            Remove-Item -Force -ErrorAction SilentlyContinue "${RESULTADOS_DIR}/${PREFIXO}_exceptions.csv"

            $csvExiste = Test-Path "${RESULTADOS_DIR}/${PREFIXO}_stats.csv"
            if ($csvExiste) {
                Write-Host "    Concluido. CSV salvo: ${PREFIXO}_stats.csv"
            } else {
                Write-Host "    AVISO: CSV nao gerado para ${PREFIXO} - verifique o Docker."
            }

            Start-Sleep -Seconds 10
        }
    }

    Write-Host ""
    Write-Host ">>> Derrubando instancias do WordPress..."
    docker compose stop wordpress | Out-Null
    docker compose rm -f wordpress | Out-Null
}

Write-Host ""
Write-Host ">>> Todos os $totalTestes testes concluidos. Resultados em: $RESULTADOS_DIR"


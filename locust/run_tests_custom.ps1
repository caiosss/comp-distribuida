# =============================================================================
# run_tests_custom.ps1 — Igual ao run_tests.ps1, mas permite escolher
#   interativamente a(s) quantidade(s) de instâncias WordPress antes de rodar.
#
# Cenários: 1-4 | Usuários: 100, 200, 300 | Spawn rate: 50/s
# Nomenclatura dos CSVs: cenario${c}_${inst}inst_${u}u  (idêntica ao original)
#
# Uso:
#   .\locust\run_tests_custom.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

# ---------- entrada do usuário -----------------------------------------------
Write-Host ""
Write-Host "Quantas instancias do WordPress deseja testar?"
Write-Host "  - Digite um numero unico (ex: 3)"
Write-Host "  - Ou varios separados por virgula (ex: 1,3,5)"
Write-Host ""
$entrada = Read-Host "Instancias"

$INSTANCIAS = @($entrada -split "," | ForEach-Object {
    $v = $_.Trim()
    if ($v -match "^\d+$" -and [int]$v -gt 0) { [int]$v }
    else {
        Write-Host "Valor invalido ignorado: '$v'"
    }
} | Where-Object { $_ -ne $null } | Sort-Object -Unique)

if ($INSTANCIAS.Count -eq 0) {
    Write-Host "Nenhuma instancia valida informada. Encerrando."
    exit 1
}

Write-Host ""
Write-Host "Instancias selecionadas: $($INSTANCIAS -join ', ')"
# -----------------------------------------------------------------------------

$USUARIOS       = @(200, 600, 1200)
$CENARIOS       = @(1, 2, 3, 4)
$SPAWN_RATE     = 100
$RESULTADOS_DIR = "./locust/resultados"

$totalTestes = $INSTANCIAS.Count * $CENARIOS.Count * $USUARIOS.Count
$testeAtual  = 0

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

            if (Test-Path "${RESULTADOS_DIR}/${PREFIXO}_stats.csv") {
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

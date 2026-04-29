Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location ..

$ErrorActionPreference = "Stop"

$USUARIOS       = @(100, 200, 900)
$INSTANCIAS     = @(1, 3, 5)
$CENARIOS       = @(1, 2, 3, 4)
$SPAWN_RATE     = 100
$RESULTADOS_DIR = "./locust/resultados"

New-Item -ItemType Directory -Force -Path $RESULTADOS_DIR | Out-Null

function Wait-WordpressReady {
    Write-Host "Aguardando WordPress..."

    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Seconds 3

        docker compose run --rm --entrypoint python locust -c "import urllib.request; urllib.request.urlopen('http://wordpress')"

        if ($LASTEXITCODE -eq 0) {
            Write-Host "WordPress pronto!"
            return
        }
    }

    Write-Host "ERRO: WordPress nao respondeu"
    exit 1
}

function Test-LocustFile {
    docker compose run --rm --entrypoint sh locust -c "ls /mnt/locust" | findstr locustfile.py

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERRO: locustfile.py nao encontrado"
        exit 1
    }
}

Test-LocustFile

foreach ($instancias in $INSTANCIAS) {

    Write-Host ""
    Write-Host "==============================="
    Write-Host "Instancias: $instancias"
    Write-Host "==============================="

    docker compose down
    docker compose up -d --scale wordpress=$instancias

    Wait-WordpressReady

    foreach ($cenario in $CENARIOS) {
        foreach ($usuarios in $USUARIOS) {

            $rampUp    = [math]::Ceiling($usuarios / $SPAWN_RATE)
            $sustained = [math]::Max(5, $rampUp)
            $duracao   = "$($rampUp + $sustained)s"

            $prefixo = "cenario${cenario}_${instancias}inst_${usuarios}u"

            Write-Host "Rodando: $prefixo"

            docker compose run --rm `
                -e CENARIO="$cenario" `
                locust `
                -f locustfile.py `
                --host=http://nginx `
                --headless `
                -u $usuarios `
                -r $SPAWN_RATE `
                --run-time $duracao `
                --csv="resultados/${prefixo}"

            if ($LASTEXITCODE -ne 0) {
                Write-Host "ERRO: $prefixo"
                continue
            }

            # 🔥 Remover arquivos desnecessários
            Remove-Item -Force -ErrorAction SilentlyContinue "${RESULTADOS_DIR}/${prefixo}_failures.csv"
            Remove-Item -Force -ErrorAction SilentlyContinue "${RESULTADOS_DIR}/${prefixo}_exceptions.csv"

            Write-Host "OK: $prefixo"
        }
    }
}

Write-Host ""
Write-Host "TODOS OS TESTES FINALIZADOS"
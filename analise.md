# Análise de Resultados: Testes de Carga em Ambiente WordPress Distribuído

**Disciplina:** Computação Distribuída  
**Data de execução dos testes:** Maio de 2026  

---

## 1. Introdução

O presente documento analisa os resultados obtidos nos testes de carga realizados sobre uma aplicação WordPress orquestrada via Docker Compose, com balanceamento de carga gerenciado pelo Nginx. O objetivo central dos experimentos foi avaliar o comportamento do sistema sob diferentes níveis de concorrência e diferentes graus de replicação horizontal do serviço WordPress, identificando os limites de escalabilidade da arquitetura proposta e os gargalos que os determinam.

Os testes foram conduzidos com a ferramenta Locust, que gerou carga sintética sobre o endpoint público da aplicação. Foram variados dois parâmetros independentes ao longo dos experimentos: o número de instâncias WordPress em execução simultânea (1, 3 e 5 réplicas) e o número de usuários virtuais concorrentes (200, 600 e 1200). Os cenários de carga foram definidos de acordo com o tipo de recurso solicitado: Cenário 1, requisição de uma imagem de 1 MB; Cenário 2, requisição de um arquivo de texto de 400 KB; Cenário 3, requisição de uma imagem de 300 KB; e Cenário 4, carga mista combinando os três tipos anteriores de forma simultânea.

Para cada combinação de instâncias e usuários, o Locust registrou métricas de throughput (requisições por segundo), tempo médio de resposta, distribuição de percentis de latência (P50, P90, P95, P99), contagem total de requisições e taxa de falha. A análise a seguir examina esses dados sob três perspectivas: o impacto do número de instâncias sobre o desempenho, o impacto da carga de usuários e a identificação dos gargalos arquiteturais observados.

---

## 2. Descrição da Infraestrutura

A arquitetura implantada consiste em quatro camadas de serviços executadas em contêineres Docker sobre uma máquina hospedeira Windows com o Docker Desktop (backend WSL2). A camada de banco de dados é composta por uma única instância MySQL 5.7, compartilhada por todas as réplicas WordPress. A camada de aplicação é formada pelas réplicas do serviço WordPress 5.4.2 com PHP 7.2 e Apache 2 no modelo de processos prefork, cujo número é controlado via `docker compose up --scale wordpress=N`. A camada de balanceamento é composta por uma única instância Nginx 1.19, que distribui as requisições entre as réplicas WordPress via resolução dinâmica de DNS interno do Docker (`resolver 127.0.0.11 valid=5s`). Por fim, a camada de carga é representada pelo contêiner Locust.

Um aspecto arquitetural relevante diz respeito à ausência de limites explícitos de CPU e memória nos contêineres WordPress no arquivo `docker-compose.yml`. Enquanto o contêiner do Locust possui um limite de 2 vCPUs configurado, os contêineres WordPress disputam livremente os recursos de processamento disponíveis na máquina hospedeira. Esse detalhe tem implicações significativas no comportamento observado sob múltiplas réplicas, como será detalhado na seção de análise de anomalias.

Outro ponto de configuração relevante está no Nginx: os parâmetros `proxy_connect_timeout 10s` e `proxy_read_timeout 60s` definem os limites de tempo que o balanceador aguarda por uma conexão ou resposta do backend antes de encerrar a tentativa. Esses valores interagem diretamente com os padrões de latência observados nos testes.

Todos os contêineres WordPress compartilham o mesmo volume Docker (`wordpress_data`), responsável por armazenar os arquivos estáticos servidos nos cenários de teste. Essa característica implica que múltiplas réplicas leem o mesmo arquivo de disco de maneira concorrente, o que pode introduzir contenção de I/O dependendo do tamanho do arquivo e da carga aplicada.

---

## 3. Resultados por Nível de Carga

### 3.1 Carga Leve: 200 Usuários Simultâneos

Sob carga de 200 usuários, o comportamento do sistema varia significativamente conforme o cenário. Para os Cenários 2, 3 e 4, cujos payloads variam entre 300 KB e 400 KB, a adição de instâncias produz resultados estáveis e dentro do esperado. As médias de tempo de resposta ficam entre 70 ms e 95 ms independentemente do número de réplicas, o throughput se mantém próximo de 97 req/s e a taxa de falha permanece em zero em todas as combinações. Esse comportamento confirma que, sob carga leve e payloads moderados, o sistema opera bem dentro de sua capacidade e o overhead de múltiplos contêineres é negligenciável.

O Cenário 1 (imagem de 1 MB), no entanto, apresenta comportamento radicalmente diferente. A tabela abaixo condensa os dados relevantes:

| Instâncias | Req/s | Tempo Médio | P50 | P80 | P95 | Máximo |
|---|---|---|---|---|---|---|
| 1 | 97,9 | 94 ms | 44 ms | 100 ms | 410 ms | 774 ms |
| 3 | 77,5 | 637 ms | 42 ms | 70 ms | 10.000 ms | 10.494 ms |
| 5 | 52,0 | 1.871 ms | 40 ms | 60 ms | 20.000 ms | 25.519 ms |

Os dados revelam uma distribuição bimodal da latência: o P50 permanece praticamente inalterado (~42 ms) enquanto o P95 salta para 10 e 20 segundos com 3 e 5 instâncias, respectivamente. Em termos práticos, isso significa que aproximadamente 80% das requisições são atendidas em menos de 70 ms, mas uma parcela consistente das requisições, em torno de 15 a 20%, aguarda mais de 10 segundos por uma resposta. Adicionalmente, o throughput cai de 97,9 req/s com uma instância para 52,0 req/s com cinco instâncias, o que representa uma redução de aproximadamente 47% na capacidade de processamento, comportamento oposto ao esperado de uma arquitetura escalável horizontalmente.

### 3.2 Carga Média: 600 Usuários Simultâneos

Sob carga de 600 usuários, o sistema exibe o comportamento esperado de escalabilidade horizontal. Em todos os quatro cenários, o aumento do número de instâncias reduz levemente o tempo médio de resposta e aumenta o throughput. A diferença não é expressiva, situando-se na ordem de 5 a 10% de ganho, mas a tendência é consistente e na direção correta.

Por exemplo, no Cenário 1 com 600 usuários, o tempo médio de resposta cai de 2.278 ms com uma instância para 2.122 ms com cinco instâncias, e o throughput sobe de 130,7 req/s para 136,0 req/s. O Cenário 3 mostra o ganho mais evidente: de 133,6 req/s com uma instância para 140,6 req/s com cinco instâncias. A taxa de falha se mantém em zero em todas as combinações de 600 usuários, indicando que o sistema ainda opera dentro de sua capacidade sob essa carga.

O comportamento nessa faixa de carga é o mais representativo do benefício real de escalabilidade horizontal dentro das condições do ambiente testado, embora os ganhos sejam modestos em razão dos gargalos que serão discutidos na seção seguinte.

### 3.3 Carga Alta: 1200 Usuários Simultâneos

Com 1200 usuários simultâneos, o sistema entra em colapso independentemente do número de instâncias WordPress. A taxa de falha se estabiliza em torno de 54 a 56% em todas as combinações e cenários, e os tempos de resposta médios ficam entre 1.650 ms e 2.252 ms. O throughput se estabiliza próximo de 265 a 280 req/s independentemente de quantas réplicas estejam ativas.

A convergência dos resultados nessa faixa de carga é o indicador mais claro do gargalo real da arquitetura: o banco de dados MySQL. Como há apenas uma instância de banco de dados compartilhada por todas as réplicas WordPress, o MySQL satura antes que o número de instâncias da camada de aplicação faça diferença. Adicionar mais réplicas WordPress apenas aumenta a concorrência por conexões de banco de dados, sem aumentar a capacidade efetiva do sistema. O número máximo de conexões simultâneas permitido pelo MySQL 5.7 em configuração padrão é 151, e com múltiplas réplicas WordPress cada uma tentando manter seu próprio pool de conexões, esse limite é atingido rapidamente.

---

## 4. Análise das Anomalias

### 4.1 Distribuição Bimodal no Cenário 1 com Múltiplas Instâncias e Carga Leve

A anomalia mais significativa observada nos dados, que consiste na degradação severa de desempenho no Cenário 1 ao adicionar instâncias sob carga leve, tem origem em uma combinação de três fatores estruturais da infraestrutura.

**Contenção de CPU entre contêineres sem limites de recursos.** O arquivo `docker-compose.yml` não define limites de CPU para os contêineres WordPress. Em uma máquina hospedeira com número limitado de núcleos físicos, cinco contêineres Apache disputam ativamente os mesmos recursos de processamento. Servir uma resposta de 1 MB é consideravelmente mais intensivo em CPU do que servir respostas de 300 a 400 KB, pois envolve mais operações no stack de rede TCP (maior volume de segmentos, mais chamadas de sistema, maior pressão sobre buffers de socket). Com uma única instância e 200 usuários, todos os núcleos disponíveis são dedicados a um único processo Apache, que consegue servir as respostas de 1 MB dentro de margens aceitáveis. Com cinco instâncias, cada processo Apache recebe proporcionalmente menos tempo de CPU, fazendo com que a geração e transmissão das respostas grandes demore muito mais, o que segura os workers por períodos prolongados e cria fila.

**Efeito de fila nos workers Apache prefork.** O Apache 2 no modelo prefork aloca um número fixo de processos filhos, cada um capaz de atender apenas uma requisição por vez. Quando os workers demoram mais para completar uma resposta (por conta da contenção de CPU descrita acima), novas requisições que chegam ao mesmo contêiner são colocadas na fila do kernel TCP antes de serem aceitas pelo Apache. As requisições na fila aguardam até que um worker fique livre. Esse fenômeno de enfileiramento é o mecanismo que cria a distribuição bimodal: a maioria das requisições encontra um worker imediatamente disponível e é atendida em ~42 ms, mas uma minoria cai na fila e aguarda dezenas de segundos. O valor de P95 de exatamente 10.000 ms observado para 3 instâncias não é coincidência: corresponde ao parâmetro `proxy_connect_timeout 10s` configurado no Nginx, indicando que o balanceador está atingindo o limite de timeout de conexão com os backends saturados e, após essa espera, a requisição é finalmente processada ou redirecionada.

**Contenção de I/O no volume compartilhado em ambiente Windows/WSL2.** Todos os contêineres WordPress montam o mesmo volume Docker (`wordpress_data`). No Docker Desktop com backend WSL2, o acesso ao sistema de arquivos virtual é intermediado por uma camada de tradução entre o Windows NT e o kernel Linux do WSL2. Leituras concorrentes do mesmo arquivo de 1 MB por cinco processos Apache distintos podem ser serializadas nessa camada, criando uma fila de I/O que adiciona latência variável a algumas requisições. Arquivos menores (300 a 400 KB) são mais facilmente mantidos no page cache do kernel Linux e, por isso, leituras subsequentes são servidas diretamente da memória sem acesso ao disco virtual, reduzindo o impacto desse gargalo para os Cenários 2 e 3.

### 4.2 Por Que os Cenários 2, 3 e 4 Não Apresentam a Anomalia

A ausência da distribuição bimodal nos cenários de payload menor confirma a hipótese de que o arquivo de 1 MB é o gatilho da anomalia, não o balanceamento em si. No Cenário 4 (carga mista), as requisições ao arquivo de 1 MB representam apenas um terço do total, o que reduz a pressão sobre os workers por esse tipo de carga e dilui o efeito de fila. Os Cenários 2 e 3 geram respostas menores, cujos workers são liberados mais rapidamente, impedindo que a fila se forme mesmo sob o efeito da contenção de CPU.

---

## 5. Validade dos Resultados

Os resultados obtidos são válidos dentro das condições do ambiente testado, mas devem ser interpretados com o contexto da infraestrutura de desenvolvimento em mente. Tratando cada faixa de carga separadamente:

Os resultados de 600 usuários são os mais representativos do benefício real de escalabilidade horizontal nesta arquitetura, pois nessa faixa o sistema opera próximo de sua capacidade efetiva sem ultrapassá-la, e a distribuição de carga entre réplicas produz ganhos mensuráveis.

Os resultados de 200 usuários no Cenário 1 são, em grande parte, um artefato das condições do ambiente: ausência de resource limits nos contêineres, contenção de I/O no Docker Desktop e o modelo de processos do Apache prefork sem ajuste fino dos parâmetros `MaxRequestWorkers` e `ServerLimit`. Em um ambiente de produção com limites de recursos definidos por contêiner, isolamento de volume por instância e configuração adequada do Apache, o comportamento esperado seria de manutenção ou melhora do desempenho com mais réplicas, mesmo sob carga leve.

Os resultados de 1200 usuários evidenciam um limite arquitetural real: a ausência de escalabilidade na camada de banco de dados. Esse resultado é válido e representa uma conclusão relevante do experimento: o MySQL single-node é o gargalo que impede que qualquer ganho na camada de aplicação se reflita em melhora de desempenho observável.

---

## 6. Conclusões

Os experimentos demonstram que a escalabilidade horizontal da camada de aplicação WordPress, dentro da arquitetura proposta, produz benefícios modestos e condicionados à faixa de carga e ao tipo de recurso servido. Sob carga média (600 usuários), há ganhos de 5 a 10% no throughput ao adicionar réplicas. Sob carga alta (1200 usuários), o sistema satura independentemente do número de réplicas em razão do gargalo no MySQL. Sob carga leve com payloads grandes (200 usuários, 1 MB), adicionar réplicas degrada o desempenho por conta de contenção de recursos no ambiente de execução.

As duas lições arquiteturais centrais que os resultados evidenciam são as seguintes. Primeiro, escalabilidade horizontal é eficaz somente quando o gargalo está na camada que está sendo escalada. Quando o gargalo é o banco de dados, como ocorre sob alta carga neste experimento, escalar a camada de aplicação não produz melhora observável. A solução arquitetural para esse problema seria a adoção de réplicas de leitura no MySQL, uso de um cache de objetos como Redis para reduzir a pressão sobre o banco, ou a migração para um banco de dados com suporte nativo a escalabilidade horizontal. Segundo, a ausência de limites de recursos por contêiner em um ambiente com múltiplas réplicas cria contenção implícita que pode anular, e até inverter, os benefícios esperados da replicação, especialmente para cargas de trabalho intensivas em I/O e processamento de rede.

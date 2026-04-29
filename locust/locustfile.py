import itertools
import os
from locust import HttpUser, task, between, TaskSet

# =============================================================================
# URLs dos posts por cenário — já configuradas com os slugs reais
# =============================================================================

URL_CENARIO_1 = "/2026/04/28/teste-forte/"           # post com imagem ~1MB
URL_CENARIO_2 = "/2026/04/28/teste-fraco/"          # post com texto ~400KB
URL_CENARIO_3 = "/2026/04/28/teste-medio/"                 # post com imagem ~300KB


class CenarioImagem1MB(TaskSet):
    """Cenário 1: post com imagem de ~1MB."""

    @task
    def acessar_post(self):
        self.client.get(URL_CENARIO_1, name="[Cenario 1] Imagem 1MB")


class CenarioTexto400KB(TaskSet):
    """Cenário 2: post com texto de ~400KB."""

    @task
    def acessar_post(self):
        self.client.get(URL_CENARIO_2, name="[Cenario 2] Texto 400KB")


class CenarioImagem300KB(TaskSet):
    """Cenário 3: post com imagem de ~300KB."""

    @task
    def acessar_post(self):
        self.client.get(URL_CENARIO_3, name="[Cenario 3] Imagem 300KB")


class CenarioHibrido(TaskSet):
    """Cenário 4 (híbrido): alterna entre os 3 posts em round-robin por usuário."""

    def on_start(self):
        self._ciclo = itertools.cycle([
            (URL_CENARIO_1, "[Cenario 1] Imagem 1MB"),
            (URL_CENARIO_2, "[Cenario 2] Texto 400KB"),
            (URL_CENARIO_3, "[Cenario 3] Imagem 300KB"),
        ])

    @task
    def acessar_post(self):
        url, name = next(self._ciclo)
        self.client.get(url, name=name)


# =============================================================================
# Seleção do cenário via variável de ambiente CENARIO (1, 2, 3 ou 4).
# O run_tests.sh passa essa variável automaticamente em cada execução.
# Para rodar manualmente: CENARIO=4 locust -f locustfile.py --host=...
# =============================================================================

_CENARIOS = {
    "1": CenarioImagem1MB,
    "2": CenarioTexto400KB,
    "3": CenarioImagem300KB,
    "4": CenarioHibrido,
}

_cenario_escolhido = os.environ.get("CENARIO", "1")

if _cenario_escolhido not in _CENARIOS:
    raise ValueError(
        f"Variável CENARIO inválida: '{_cenario_escolhido}'. Use 1, 2, 3 ou 4."
    )


class UsuarioAtivo(HttpUser):
    wait_time = between(1, 3)
    tasks = [_CENARIOS[_cenario_escolhido]]
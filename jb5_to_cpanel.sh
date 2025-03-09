#!/bin/bash
#
# Script para converter backup do JetBackup5 para formato cPanel
# Uso: ./jb5_to_cpanel.sh {JETBACKUP5_BACKUP} {DESTINATION_DIRECTORY}
 
function print_help {
  echo "
   Uso:
 
       ./jb5_to_cpanel.sh {JETBACKUP5_BACKUP} {DESTINATION_DIRECTORY}
 
        {JETBACKUP5_BACKUP} - Localização do arquivo de backup JetBackup5
        {DESTINATION_DIRECTORY} - Diretório onde o backup convertido será salvo
 
   Exemplo:
        ./jb5_to_cpanel.sh ./download_sensuste_1741403658_93378.tar.gz ./resultado
   "
  exit 0
}
 
function message {
  echo ""
  echo "$1"
  echo ""
  [[ -z $2 ]] && print_help
  exit 1
}
 
function untar() {
  BACKUP_PATH=$1
  DESTINATION_PATH=$2
  tar -xf "$BACKUP_PATH" -C "$DESTINATION_PATH"
  CODE=$?
  [[ $CODE -gt 0 ]] && message "Erro: Não foi possível extrair o arquivo $BACKUP_PATH" 1
}
 
function extract() {
  FILE_PATH=$1
  gunzip "$FILE_PATH"
  CODE=$?
  [[ $CODE -gt 0 ]] && message "Erro: Não foi possível extrair arquivos" 1
}
 
function create_dir() {
  DIRECTORY_PATH=$1
  mkdir -p "$DIRECTORY_PATH" >/dev/null 2>&1
  CODE=$?
  [[ $CODE -gt 0 ]] && message "Erro: Não foi possível criar o diretório $DIRECTORY_PATH" 1
}
 
function move_dir() {
  echo "Migrando $1"
  SOURCE=$1
  DESTINATION=$2
  
  # Verifica se o destino existe antes de tentar mover
  if [ ! -d "$DESTINATION" ]; then
    mkdir -p "$DESTINATION"
  fi
  
  # Corrigir o problema com wildcard
  if [[ "$SOURCE" == *"*"* ]]; then
    SOURCE_DIR=$(dirname "$SOURCE")
    PATTERN=$(basename "$SOURCE")
    for file in "$SOURCE_DIR"/$PATTERN; do
      mv "$file" "$DESTINATION"/ 2>/dev/null
    done
  else
    mv "$SOURCE" "$DESTINATION"/ 2>/dev/null
  fi
  
  # Mesmo que falhe o mv, continuamos para tentar concluir a conversão
  return 0
}
 
function archive() {
  TAR_NAME=$1
  
  echo "Criando arquivo $UNZIP_DESTINATION/$TAR_NAME"
  
  cd "$UNZIP_DESTINATION" || message "Erro: Não foi possível acessar o diretório $UNZIP_DESTINATION" 1
  tar -czf "$TAR_NAME" "cpmove-$ACCOUNT_NAME" >/dev/null 2>&1
  CODE=$?
  [[ $CODE != 0 ]] && message "Erro: Não foi possível criar o arquivo tar" 1
  
  echo "Arquivo criado com sucesso: $UNZIP_DESTINATION/$TAR_NAME"
}
 
function create_ftp_account() {
  DIRECTORY_PATH=$1
  CONFIG_PATH=$2
  
  # Cria o arquivo se não existir
  touch "$CPANEL_DIRECTORY/proftpdpasswd"
  
  if [ -d "$DIRECTORY_PATH" ] && [ "$(ls -A "$DIRECTORY_PATH")" ]; then
    HOMEDIR=$(cat "$CONFIG_PATH/meta/homedir_paths" 2>/dev/null)
    USER=$(ls "$CONFIG_PATH/cp/" 2>/dev/null)
    
    for FILE in $(ls "$DIRECTORY_PATH" 2>/dev/null | grep -iE "\.acct$"); do
      USERNAME=$(grep -Po '(?<=name: )(\w\D+)' "$DIRECTORY_PATH/$FILE" 2>/dev/null)
      PASSWORD=$(grep -Po '(?<=password: )([A-Za-z0-9!@#$%^&*,()\/\\.])+' "$DIRECTORY_PATH/$FILE" 2>/dev/null)
      PUBLIC_HTML_PATH=$(grep -Po '(?<=path: )([A-Za-z0-9\/_.-]+)' "$DIRECTORY_PATH/$FILE" 2>/dev/null)
      
      if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
        echo "Criando conta FTP $USERNAME"
        printf "$USERNAME:$PASSWORD:0:0:$USER:$HOMEDIR/$PUBLIC_HTML_PATH:/bin/ftpsh\n" >> "$CPANEL_DIRECTORY/proftpdpasswd"
      fi
    done
  fi
}
 
function create_mysql_file() {
  DIRECTORY_PATH=$1
  SQL_FILE_PATH=$2
  
  # Cria o arquivo SQL se não existir
  touch "$SQL_FILE_PATH"
  
  if [ -d "$DIRECTORY_PATH" ] && [ "$(ls -A "$DIRECTORY_PATH")" ]; then
    for FILE in $(ls "$DIRECTORY_PATH" 2>/dev/null | grep -iE "\.user$"); do
      USERNAME=$(grep -Po '(?<=name: )([a-zA-Z0-9!@#$%^&*(\)\_\.-]+)' "$DIRECTORY_PATH/$FILE" 2>/dev/null)
      DATABASE=$(grep -Po '(?<=database `)([_a-zA-Z0-9]+)' "$DIRECTORY_PATH/$FILE" 2>/dev/null)
      USER=$(grep -Po '(?<=name: )([a-zA-Z0-9!#$%^&*(\)\_\.]+)' "$DIRECTORY_PATH/$FILE" 2>/dev/null)
      DOMAIN=$(echo "$USERNAME" | grep -Po '(?<=@)(.*)$' 2>/dev/null)
      PASSWORD=$(grep -Po '(?<=password: )([a-zA-Z0-9*]+)' "$DIRECTORY_PATH/$FILE" 2>/dev/null)
      PERMISSIONS=$(grep -Po '(?<=:)[A-Z ,]+$' "$DIRECTORY_PATH/$FILE" 2>/dev/null)
      
      if [ -n "$USER" ] && [ -n "$DATABASE" ]; then
        echo "Criando BD $DATABASE"
        echo "Adicionando usuário de BD $USER"
        
        echo "GRANT USAGE ON *.* TO '$USER'@'$DOMAIN' IDENTIFIED BY PASSWORD '$PASSWORD';" >> "$SQL_FILE_PATH"
        echo "GRANT$PERMISSIONS ON \`$DATABASE\`.* TO '$USER'@'$DOMAIN';" >> "$SQL_FILE_PATH"
      fi
    done
  fi
}
 
function create_email_account() {
  BACKUP_EMAIL_PATH=$1
  DESTINATION_EMAIL_PATH=$2
  
  if [ -d "$BACKUP_EMAIL_PATH" ] && [ -d "$DESTINATION_EMAIL_PATH" ]; then
    DOMAIN_USER=$(grep -Po '(?<=DNS=)([A-Za-z0-9-.]+)' "$CPANEL_DIRECTORY/cp/$ACCOUNT_NAME" 2>/dev/null)
    
    if [ -n "$DOMAIN_USER" ]; then
      echo "Criando contas de email para $DOMAIN_USER"
      
      # Certifica-se de que o diretório existe
      mkdir -p "$DESTINATION_EMAIL_PATH/$DOMAIN_USER" 2>/dev/null
      touch "$DESTINATION_EMAIL_PATH/$DOMAIN_USER/shadow" 2>/dev/null
      
      for JSON_FILE in $(ls "$BACKUP_EMAIL_PATH" 2>/dev/null | grep -iE "\.conf$"); do
        PASSWORD=$(grep -Po '(?<=,"password":")([a-zA-Z0-9\=,]+)' "$BACKUP_EMAIL_PATH/$JSON_FILE" 2>/dev/null)
        if [ -n "$PASSWORD" ]; then
          DECODED_PASSWORD=$(echo "$PASSWORD" | base64 --decode 2>/dev/null)
          printf "$DOMAIN_USER:$DECODED_PASSWORD\n" >> "$DESTINATION_EMAIL_PATH/$DOMAIN_USER/shadow"
        fi
      done
    fi
  fi
}

# Função principal

# Verifica parâmetros
if [ "$#" -lt 2 ]; then
  print_help
fi

FILE_PATH=$1
DES_PATH=$2
UNZIP_DESTINATION="$DES_PATH/jb5_migrate_$RANDOM"

# Verifica caminhos
[[ "$DES_PATH" == "/" ]] && message "Erro: Não use a pasta raiz como destino"
[[ ! -f "$FILE_PATH" ]] && message "Erro: Arquivo de backup não encontrado"

# Extrai o nome da conta do nome do arquivo
ACCOUNT_NAME=$(basename "$FILE_PATH" | grep -oP '(?<=download_)([^_]+)' || echo "cpuser")
BACKUP_PATH="$FILE_PATH"

echo "Caminho do backup: $BACKUP_PATH"
echo "Nome da conta: $ACCOUNT_NAME"
echo "Criando pasta $UNZIP_DESTINATION"

# Cria diretório de destino
create_dir "$UNZIP_DESTINATION"

echo "Extraindo $BACKUP_PATH para $UNZIP_DESTINATION"
untar "$BACKUP_PATH" "$UNZIP_DESTINATION"

# Verifica se a estrutura do backup é válida
if [ ! -d "$UNZIP_DESTINATION/backup" ]; then
  message "Erro: Diretório de backup JetBackup5 $UNZIP_DESTINATION/backup não encontrado" 1
fi

# Define diretórios
CPANEL_DIRECTORY="$UNZIP_DESTINATION/cpmove-$ACCOUNT_NAME"
JB5_BACKUP="$UNZIP_DESTINATION/backup"

echo "Convertendo conta '$ACCOUNT_NAME'"
echo "Pasta de trabalho: $CPANEL_DIRECTORY"

# Cria estrutura de diretórios do cPanel
create_dir "$CPANEL_DIRECTORY"
create_dir "$CPANEL_DIRECTORY/mysql"
create_dir "$CPANEL_DIRECTORY/homedir"

# Move e organiza os arquivos
if [ -d "$JB5_BACKUP/config" ]; then
  move_dir "$JB5_BACKUP/config" "$CPANEL_DIRECTORY/"
fi

if [ -d "$JB5_BACKUP/homedir" ]; then
  if [ ! -d "$CPANEL_DIRECTORY/homedir" ]; then
    move_dir "$JB5_BACKUP/homedir" "$CPANEL_DIRECTORY"
  else 
    rsync -ar "$JB5_BACKUP/homedir/" "$CPANEL_DIRECTORY/homedir/" 2>/dev/null || cp -rf "$JB5_BACKUP/homedir/"* "$CPANEL_DIRECTORY/homedir/" 2>/dev/null
  fi
fi

if [ -d "$JB5_BACKUP/database" ]; then
  # Corrige o comando para mover apenas conteúdo
  for db_file in "$JB5_BACKUP/database/"*; do
    if [ -f "$db_file" ]; then
      cp "$db_file" "$CPANEL_DIRECTORY/mysql/" 2>/dev/null
      # Tenta descomprimir arquivos .gz
      if [[ "$db_file" == *.gz ]]; then
        gunzip "$CPANEL_DIRECTORY/mysql/$(basename "$db_file")" 2>/dev/null
      fi
    fi
  done
fi

if [ -d "$JB5_BACKUP/database_user" ]; then
  create_mysql_file "$JB5_BACKUP/database_user" "$CPANEL_DIRECTORY/mysql.sql"
fi

if [ -d "$JB5_BACKUP/email" ]; then
  create_dir "$CPANEL_DIRECTORY/homedir/mail"
  move_dir "$JB5_BACKUP/email" "$CPANEL_DIRECTORY/homedir/mail"
  
  if [ -d "$JB5_BACKUP/jetbackup.configs/email" ]; then
    create_dir "$CPANEL_DIRECTORY/homedir/etc"
    create_email_account "$JB5_BACKUP/jetbackup.configs/email" "$CPANEL_DIRECTORY/homedir/etc"
  fi
fi

if [ -d "$JB5_BACKUP/ftp" ]; then
  create_ftp_account "$JB5_BACKUP/ftp" "$CPANEL_DIRECTORY"
fi

echo "Criando arquivo final de backup do cPanel..."
archive "cpmove-$ACCOUNT_NAME.tar.gz"

echo "Conversão concluída!"
echo "Você pode remover com segurança a pasta de trabalho: $JB5_BACKUP"
echo "Localização do backup do cPanel: $UNZIP_DESTINATION/cpmove-$ACCOUNT_NAME.tar.gz"

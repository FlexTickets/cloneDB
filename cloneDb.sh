#!/usr/bin/env bash
#set -x
set -euo pipefail

if [ $# -lt 1 ]; then
        echo "Usage: $0 <new db name>"
        exit 0
fi

DB_SERVER=shop-test.k8s.enamine.net
DB_PORT=30000
DB_NAME=market
USER_NAME=estore
DBPWD="sdfs5t@Dc67!Lkk"
DATE=$(date +%Y%m%d_%H%M)
DUMP=/home/kofe/dumps/${DB_NAME}_${DATE}.sql
scriptDir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# Redirect stdout and stderr to syslog
exec 1> >(logger -s -t $(basename $0)) 2>&1

function my_trap() {
        local lineno=$1
        local cmd=$2
	rm ${DUMP}
	msg=$(echo "$(basename $0): Failed at line ${lineno}: ${cmd}" | sed 's/\"/\\\"/g')
        ${scriptDir}/send2bot.sh "${msg}"
        exit 1
}

trap 'my_trap ${LINENO} "${BASH_COMMAND}"' ERR

${scriptDir}/send2bot.sh "$(basename $0) $1"

# Parse arg into array of databases name
[[ -z "$(echo $1 | grep ',')" ]] && arg1="$(echo "$1" | tr -s ' ' | sed 's/ /|/g')" || arg1="$(echo "$1" | tr -d ' ' | sed 's/,/|/g')"
IFS='|'
read -a databases <<< "${arg1}"
#echo "${#databases[@]}: ${databases[@]}"

# Dump source db
/usr/bin/mysqldump -h ${DB_SERVER} -P ${DB_PORT} -u ${USER_NAME} -p${DBPWD} --default-character-set=utf8 -R -E --triggers --single-transaction -r ${DUMP} ${DB_NAME}

for db in ${databases[@]}; do
	# Define commands
	DROP_DB="/usr/bin/mysql -h ${DB_SERVER} -P ${DB_PORT} -u ${USER_NAME} -p${DBPWD} -e \"drop database ${db} if exists;\" 2>&1"
	CREATE_DB="/usr/bin/mysql -h ${DB_SERVER} -P ${DB_PORT} -u ${USER_NAME} -p${DBPWD} -e \"create database ${db} charset = utf8 collate = utf8_general_ci;\" 2>&1"
	GRANT_PRIVS="/usr/bin/mysql -h ${DB_SERVER} -P ${DB_PORT} -u ${USER_NAME} -p${DBPWD} -e \"grant all privileges on ${db}.* to ${USER_NAME}@'%';\" 2>&1"
	SED=$(printf "sed -i 's/%s/%s/g' %s" "\`${DB_NAME}\`" "\`${db}\`" ${DUMP})
	IMPORT="/usr/bin/mysql -h ${DB_SERVER} -P ${DB_PORT} -u ${USER_NAME} -p${DBPWD} ${db} < ${DUMP} 2>&1"

	# Replace source db name with new db name
	eval ${SED}
	[ $? -ne 0 ] && (echo "sed execution error"; exit 1)

	DB_NAME=${db}
	# Create new db and grant privileges
	[[ -z "$(eval ${CREATE_DB})" ]] || (echo "Creating DB error"; continue)
	[[ -z "$(eval ${GRANT_PRIVS})" ]] || (echo "Granting privileges error"; continue)

	# Import dump to new db
	[[ -z "$(eval ${IMPORT})" ]] || (echo "Importing DB error")
done
rm ${DUMP}
${scriptDir}/send2bot.sh "$(basename $0): exit"

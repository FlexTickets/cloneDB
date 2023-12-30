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
DATE=$(date +%Y%m%d_%H%M)
scriptDir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
DUMP=${scriptDir}/../dumps/${DB_NAME}_${DATE}.sql
source ${scriptDir}/.db.passwd
FLAG=0

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

${scriptDir}/send2bot.sh "$(basename $0) \"$1\""

# Parse arg into array of databases name
[[ -z "$(echo $1 | grep ',')" ]] && arg1="$(echo "$1" | tr -s ' ' | sed 's/ /|/g')" || arg1="$(echo "$1" | tr -d ' ' | sed 's/,/|/g')"
IFS='|'
read -a databases <<< "${arg1}"
#echo "${#databases[@]}: ${databases[@]}"

# Dump source db
/usr/bin/mysqldump -h ${DB_SERVER} -P ${DB_PORT} -u ${USER_NAME} -p${DBPWD} --default-character-set=utf8 -R -E --triggers --single-transaction -r ${DUMP} ${DB_NAME}

for db in ${databases[@]}; do
	# Define commands
	DROP_DB="/usr/bin/mysql -h ${DB_SERVER} -P ${DB_PORT} -u ${USER_NAME} -p${DBPWD} -e \"drop database if exists ${db};\" 2>&1"
	CREATE_DB="/usr/bin/mysql -h ${DB_SERVER} -P ${DB_PORT} -u ${USER_NAME} -p${DBPWD} -e \"create database ${db} charset = utf8 collate = utf8_general_ci;\" 2>&1"
	GRANT_PRIVS="/usr/bin/mysql -h ${DB_SERVER} -P ${DB_PORT} -u ${USER_NAME} -p${DBPWD} -e \"grant all privileges on ${db}.* to ${USER_NAME}@'%';\" 2>&1"
	SED=$(printf "sed -i 's/%s/%s/g' %s" "\`${DB_NAME}\`" "\`${db}\`" ${DUMP})
	IMPORT="/usr/bin/mysql -h ${DB_SERVER} -P ${DB_PORT} -u ${USER_NAME} -p${DBPWD} ${db} < ${DUMP} 2>&1"

	# Replace source db name with new db name
	eval ${SED}
	[ $? -ne 0 ] && (echo "sed execution error"; exit 1)

	DB_NAME=${db}
	# Drop DB
	[[ -z "$(eval ${DROP_DB})" ]] || (FLAG=1; echo "Drop DB error"; ${scriptDir}/send2bot.sh "$(basename $0) \"Drop DB error\""; continue)

	# Create new db and grant privileges
	[[ -z "$(eval ${CREATE_DB})" ]] || (FLAG=1; echo "Creating DB error"; ${scriptDir}/send2bot.sh "$(basename $0) \"Creating DB error\""; continue)
	[[ -z "$(eval ${GRANT_PRIVS})" ]] || (FLAG=1; echo "Granting privileges error"; ${scriptDir}/send2bot.sh "$(basename $0) \"Granting privileges error\""; continue)

	# Import dump to new db
	[[ -z "$(eval ${IMPORT})" ]] || (FLAG=1; echo "Importing DB error"; ${scriptDir}/send2bot.sh "$(basename $0) \"Importing DB error\"")
done
rm ${DUMP}
#${scriptDir}/send2bot.sh "$(basename $0): exit"
exit ${FLAG}

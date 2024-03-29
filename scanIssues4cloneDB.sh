#!/usr/bin/env bash
#set -x
set -euo pipefail

# Get list of transitions for given issue
#
# curl -ks -u f.kolodiazhnyi@enamine.net:<Attlassian tocken> https://enamine.atlassian.net/rest/api/2/issue/SHOP-XXXXX/transitions | jq .[]

# Redirect stdout and stderr to syslog
exec 1> >(logger -s -t $(basename $0)) 2>&1

USER=f.kolodiazhnyi@enamine.net
CURL_KEYS="-ks"
JIRA_URL=https://enamine.atlassian.net
scriptDir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
source ${scriptDir}/.jira.token
TRANSITIONS=""
inProgress=""
Done=""

function my_trap() {
        local lineno=$1
        local cmd=$2
        ${scriptDir}/send2bot.sh "<b>$(basename $0)</b> \nFailed at line ${lineno}: ${cmd}"
        exit 1
}

trap 'my_trap ${LINENO} "${BASH_COMMAND}"' ERR

# Get issues for DB manipulation
ISSUES=$( curl ${CURL_KEYS} -u ${USER}:${TOKEN} -X GET -H "Content-Type: application/json" ${JIRA_URL}/rest/api/2/search?jql=project%20%3D%20\"SHOP\"%20AND%20assignee%20%3D%20\"632b25477f85f167779d4085\"%20AND%20status%20%3D%20\"To%20Do\"%20AND%20summary%20~%20\"%5C%5C%5BDB%5C%5C%5D%20\" | jq '.issues[] | "\(.key), \(.fields.summary)"' )

[[ "${ISSUES}" == "" ]] && exit 0


# Compose arguments for cloneDb.sh and transit issues to "In progress" state
DBs=""
while read -r line; do
	line=$(echo "${line}" | sed 's/^"\(.*\)"$/\1/')
	issue=$(echo "${line}" | awk -F ',' '{print $1}')

	# Find transitions codes
	TRANSITIONS=$(curl ${CURL_KEYS} -u ${USER}:${TOKEN} ${JIRA_URL}/rest/api/2/issue/${issue}/transitions)
	inProgress=$(echo "${TRANSITIONS}" | jq -r '.transitions | map(select(.name == "In Progress")) | .[].id')
	Done=$(echo "${TRANSITIONS}" | jq -r '.transitions | map(select(.name == "Done")) | .[].id')

	# Transit issue to In progress
	${scriptDir}/send2bot.sh "<b>$(basename $0)</b> \nTransit issue ${issue} to In progress state"
	curl ${CURL_KEYS} -u ${USER}:${TOKEN} -X POST --data "{\"transition\": {\"id\":\"${inProgress}\"}}" -H "Content-Type:application/json" ${JIRA_URL}/rest/api/2/issue/${issue}/transitions
	db=$(echo "${line}" | awk '{print $4}')
	[[ "${DBs}" == "" ]] && DBs=${db} || DBs="${DBs},${db}"
done <<< "${ISSUES}"

# Start DBs cloning
${scriptDir}/cloneDb.sh "${DBs}"

[ $? -eq 0 ] || (${scriptDir}/send2bot.sh "<b>$(basename $0)</b> \nDB cloning is unsuccessful"; exit 1)

# Transit issues to Done state
while read -r line; do
        line=$(echo "${line}" | sed 's/^"\(.*\)"$/\1/')
        issue=$(echo "${line}" | awk -F ',' '{print $1}')

        # Transit issue to Done
        ${scriptDir}/send2bot.sh "<b>$(basename $0)</b> \nTransit issue ${issue} to Done state"
        curl ${CURL_KEYS} -u ${USER}:${TOKEN} -X POST --data "{\"transition\": {\"id\":\"${Done}\"}}" -H "Content-Type:application/json" ${JIRA_URL}/rest/api/2/issue/${issue}/transitions
done <<< "${ISSUES}"


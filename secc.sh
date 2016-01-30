#!/bin/bash
############################################################
##                                                        ##
##                SECC Shell Frontend - 0.0.1             ##
##                                                        ##
############################################################

#### user settings or ENV. 
#SCHEDULER_HOST="172.17.42.1"
#SCHEDULER_PORT="10509"
#SECC_CROSS="true"



#default settings

[[ -z $SECC_MODE ]] && SECC_MODE="1"
[[ -z $SECC_CROSS ]] && SECC_CROSS="false"
if [[ -n $DEBUG ]] ; then
  [[ -z $SECC_LOG ]] && SECC_LOG=/dev/stdout
else
  SECC_LOG=/dev/null  
fi
[[ -z $TMPDIR ]] && TMPDIR="/tmp"


COMPILER_PATH=$0
ARGV=$@
COMPILER=${COMPILER_PATH##*/}
RANDOM_STRING=$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM
PREPROCESSED_SOURCE_PATH="${TMPDIR}/secc-${RANDOM_STRING:0:5}"
PREPROCESSED_GZIP_PATH=${PREPROCESSED_SOURCE_PATH}_in.gz
OUTPUT_TAR_PATH=${PREPROCESSED_SOURCE_PATH}_out.tar
OPTION_ANALYZE_PATH=${PREPROCESSED_SOURCE_PATH}_option.txt
JOB_PATH=${PREPROCESSED_SOURCE_PATH}_job.txt
OUTPUT_HEADER_PATH=${PREPROCESSED_SOURCE_PATH}_header.txt

log()
{
  read INPUT
  echo "[$$] $INPUT $1" >> ${SECC_LOG}
}

deleteTempFiles()
{
  rm -rf ${PREPROCESSED_SOURCE_PATH} > /dev/null 2>&1
  rm -rf ${PREPROCESSED_GZIP_PATH}   > /dev/null 2>&1
  rm -rf ${OUTPUT_TAR_PATH}          > /dev/null 2>&1
  rm -rf ${OPTION_ANALYZE_PATH}      > /dev/null 2>&1
  rm -rf ${JOB_PATH}                 > /dev/null 2>&1
  rm -rf ${OUTPUT_HEADER_PATH}       > /dev/null 2>&1
}

passThrough()
{
  echo "passThrough - $@" | log
  deleteTempFiles
  eval "/usr/bin/${COMPILER} ${ARGV}"
  EXIT_CODE=$?
  exit ${EXIT_CODE}
}

#FIXME : better way?
printCommand()
{
  export >> ${SECC_LOG}
  echo "${COMPILER_PATH} ${ARGV}" >> ${SECC_LOG}
}

echo "--- SECC START --- "$(date) | log
[[ -n "$SECC_CMDLINE" ]] && printCommand

## basic checks
[[ -z "$1" ]] && passThrough "no arguments"
[[ -z "$SCHEDULER_HOST" ]] && passThrough "no SCHEDULER_HOST"
[[ -z "$SCHEDULER_PORT" ]] && passThrough "no SCHEDULER_PORT"

#echo $COMPILER_PATH

argv='['
for arg in $@
do
  argv+='"'${arg//\"/\\\"}'", '
done
argv=${argv/%, /}
argv+=']'


data='{"compiler":"'${COMPILER}'"
,"cwd":"'${PWD}'"
,"mode":"'${SECC_MODE}'"
,"argv":'${argv}'}'
#echo $data

#--silent | --verbose
COMMAND="curl --verbose \
--max-time 10 \
-X POST \
-H 'Content-Type: application/json' \
-H 'Accept: text/plain' \
http://$SCHEDULER_HOST:$SCHEDULER_PORT/option/analyze \
-d '${data}' \
-o '${OPTION_ANALYZE_PATH}' \
--dump-header '${OUTPUT_HEADER_PATH}' \
--noproxy ${SCHEDULER_HOST}"

echo $COMMAND | log
eval $COMMAND 2>> ${SECC_LOG}
[[ $? != 0 ]] && passThrough "error on SCHEDULER/option/analyze"
OUTPUT_HEADER_STATUS=$(cat "$OUTPUT_HEADER_PATH" | grep "HTTP/1.1 200 OK")
[[ -z "$OUTPUT_HEADER_STATUS" ]] && passThrough "bad code on SCHEDULER/option/analyze"


OPTION=$(cat ${OPTION_ANALYZE_PATH})
OPTION_argvHash=$(echo "$OPTION" | grep "argvHash=" | sed -e "s/argvHash=//")
OPTION_infile=$(echo "$OPTION" | grep "infile=" | sed -e "s/infile=//")
OPTION_preprocessedInfile=$(echo "$OPTION" | grep "preprocessedInfile=" | sed -e "s/preprocessedInfile=//")
OPTION_outfile=$(echo "$OPTION" | grep "outfile=" | sed -e "s/outfile=//")
OPTION_multipleOutfiles=$(echo "$OPTION" | grep "multipleOutfiles=" | sed -e "s/multipleOutfiles=//")
OPTION_language=$(echo "$OPTION" | grep "language=" | sed -e "s/language=//")
OPTION_useLocal=$(echo "$OPTION" | grep "useLocal=" | sed -e "s/useLocal=//")
OPTION_projectId=$(echo "$OPTION" | grep "projectId=" | sed -e "s/projectId=//")
OPTION_localArgv=($(echo "$OPTION" | grep "localArgv=" | sed -e "s/localArgv=//"))
OPTION_remoteArgv=($(echo "$OPTION" | grep "remoteArgv=" | sed -e "s/remoteArgv=//"))
OPTION_targetSpecified=$(echo "$OPTION" | grep "targetSpecified=" | sed -e "s/targetSpecified=//")
OPTION_target=$(echo "$OPTION" | grep "target=" | sed -e "s/target=//")

[[ "$OPTION_useLocal" == "true" ]] && passThrough "useLocal from SCHEDULER/option/analyze"

COMPILER_VERSION=$(echo $(/usr/bin/${COMPILER} --version))
COMPILER_DUMPMACHINE=$(/usr/bin/${COMPILER} -dumpmachine)
COMPILER_DUMPVERSION=$(/usr/bin/${COMPILER} -dumpversion)

# generator preprocessed source
COMMAND="/usr/bin/${COMPILER} ${OPTION_localArgv[@]} -o ${PREPROCESSED_SOURCE_PATH}"
PREPROCESSED=$(eval $COMMAND)
[[ $? != 0 ]] && passThrough "error on generating the preprocessed source"
# md5
if [[ "$(uname)" == "Darwin" ]]; then
  SOURCE_HASH=$(md5 -q ${PREPROCESSED_SOURCE_PATH})
else
  SOURCE_HASH=$(md5sum ${PREPROCESSED_SOURCE_PATH} | awk -F" " '{print $1}')
fi
[[ $? != 0 ]] && passThrough "error on md5 hasing"
# gzip
$(gzip --stdout --fast ${PREPROCESSED_SOURCE_PATH} > ${PREPROCESSED_GZIP_PATH})
[[ $? != 0 ]] && passThrough "error on gzip the preprocessed source"

data='{
  "systemInformation" : {
    "hostname" : "'$(uname -a | awk -F" " '{print $2}')'",
    "platform" : "'$(uname -a | awk -F" " '{print tolower($1)}')'",
    "release" : "'$(uname -a | awk -F" " '{print $3}')'",
    "arch" : "x64",
    "numCPUs" : "1",
    "port" : "10508"
  },
  "compilerInformation" : {
    "version" : "'${COMPILER_VERSION}'",
    "dumpversion" : "'${COMPILER_DUMPVERSION}'",
    "dumpmachine" : "'${COMPILER_DUMPMACHINE}'"
  },
  "mode" : "1",
  "projectId" : "'${OPTION_projectId}'",
  "cachePrefered" : false,
  "crossPrefered" : '${SECC_CROSS}',
  "sourcePath" : "'${OPTION_infile}'",
  "sourceHash" : "'${SOURCE_HASH}'",
  "argvHash" : "'${OPTION_argvHash}'"
}'

#--silent
COMMAND="curl --verbose \
-X POST \
-H 'Content-Type: application/json' \
-H 'Accept: text/plain' \
http://$SCHEDULER_HOST:$SCHEDULER_PORT/job/new \
-d '$data' \
-o '${JOB_PATH}' \
--dump-header '${OUTPUT_HEADER_PATH}' \
--noproxy ${SCHEDULER_HOST}"

echo $COMMAND | log
eval $COMMAND 2>> ${SECC_LOG}
OUTPUT_HEADER_STATUS=$(cat "$OUTPUT_HEADER_PATH" | grep "HTTP/1.1 200 OK")
[[ -z "$OUTPUT_HEADER_STATUS" ]] && passThrough "error on DAEMON's compilation(not 200)"

JOB=$(cat ${JOB_PATH})
[[ $? != 0 ]] && passThrough "error on SCHEDULER/job/new"


JOB_archiveId=$(echo "$JOB" | grep "archive/archiveId=" | awk -F"archive/archiveId=" '{print $2}')
JOB_jobId=$(echo "$JOB" | grep "jobId=" | awk -F"jobId=" '{print $2}')
JOB_daemonAddress=$(echo "$JOB" | grep "daemon/daemonAddress=" | awk -F"daemon/daemonAddress=" '{print $2}')
JOB_daemonPort=$(echo "$JOB" | grep "daemon/system/port=" | awk -F"daemon/system/port=" '{print $2}')
JOB_local=$(echo "$JOB" | grep "local=" | awk -F"local=" '{print $2}')
JOB_errorMessage=$(echo "$JOB" | grep "error/message=" | awk -F"error/message=" '{print $2}')

[[ "$JOB_local" == "true" ]] && passThrough "local from SCHEDULER/job/new" "${JOB_errorMessage}"


# echo $JOB_archiveId
# echo $JOB_jobId
# echo $JOB_daemonAddress
# echo $JOB_daemonPort

# OPTION_remoteArgv to comma seperated string
for arg in ${OPTION_remoteArgv[@]}
do
  SECC_ARGV+="$arg,"
done
SECC_ARGV=${SECC_ARGV/%,/}
#echo $SECC_ARGV

if [[ -z $OPTION_outfile ]]; then
  SOURCE_NAME=${OPTION_infile##*/}
else
  SOURCE_NAME=${OPTION_outfile##*/}
fi
SOURCE_NAME=${SOURCE_NAME%.*}


# request Compilation to Daemon --silent
COMMAND="curl --verbose \
-X POST \
--max-time 60 \
-H Content-Encoding:'gzip' \
-H secc-jobid:'${JOB_jobId}' \
-H secc-compiler:'${COMPILER}' \
-H secc-language:'${OPTION_language}' \
-H secc-argv:['$SECC_ARGV'] \
-H secc-filename:'${SOURCE_NAME}' \
-H secc-cross:'${SECC_CROSS}' \
-H secc-target:'${COMPILER_DUMPMACHINE}' \
-T '${PREPROCESSED_GZIP_PATH}' \
-o '${OUTPUT_TAR_PATH}' \
--dump-header '${OUTPUT_HEADER_PATH}' \
http://${JOB_daemonAddress}:${JOB_daemonPort}/compile/preprocessed/${JOB_archiveId} \
--noproxy ${SCHEDULER_HOST}"

echo $COMMAND | log
eval $COMMAND 2>> ${SECC_LOG}
[[ $? != 0 ]] && passThrough "error on DAEMON/compile/preprocessed/${JOB_archiveId}"

OUTPUT_HEADER=$(cat ${OUTPUT_HEADER_PATH})
OUTPUT_HEADER_SECC_CODE=$(echo "$OUTPUT_HEADER" | grep "secc-code:" | sed -e "s/secc-code://")
OUTPUT_HEADER_SECC_STDOUT=$(echo "$OUTPUT_HEADER" | grep "secc-stdout:" | sed -e "s/secc-stdout://")
OUTPUT_HEADER_SECC_STDERR=$(echo "$OUTPUT_HEADER" | grep "secc-stderr:" | sed -e "s/secc-stderr://")
OUTPUT_HEADER_STATUS=$(echo "$OUTPUT_HEADER" | grep "HTTP/1.1 200 OK")

[[ -z "$OUTPUT_HEADER_STATUS" ]] && passThrough "error on DAEMON's compilation(not 200)"
[[ "$OUTPUT_HEADER_SECC_CODE" == "0" ]] && passThrough "error on DAEMON's compilation(exit code is not 0)"
[[ -n "${OUTPUT_HEADER_SECC_STDOUT}" ]] && printf '%b' "${OUTPUT_HEADER_SECC_STDOUT//%/\\x}" > /dev/stdout
[[ -n "${OUTPUT_HEADER_SECC_STDERR}" ]] && printf '%b' "${OUTPUT_HEADER_SECC_STDERR//%/\\x}" > /dev/stderr


# target directory
[[ -n "$OPTION_outfile" ]] && OUTPUT_DIR=$(dirname $OPTION_outfile)
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR=${PWD}

# untar
COMMAND="tar xvf ${OUTPUT_TAR_PATH} --directory ${OUTPUT_DIR} 1>>${SECC_LOG} 2>&1"
echo $COMMAND | log
eval $COMMAND
[[ $? != 0 ]] && passThrough "error on untar"



# echo ${PREPROCESSED_SOURCE_PATH}
# echo ${PREPROCESSED_GZIP_PATH}
# echo ${OUTPUT_TAR_PATH}
# echo $$OUTPUT_HEADER_PATH}

# clean up
deleteTempFiles

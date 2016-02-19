#!/bin/bash
############################################################
##                                                        ##
##                SECC Shell Frontend - 0.0.6             ##
##                                                        ##
## bin utils                                              ##
##  printf, echo, date, curl, cat, grep, sed, awk         ##
##  uname, md5|md5sum                                     ##
############################################################

# ### user settings or ENV.
# SECC_ADDRESS="172.17.42.1"
# SECC_PORT="10509"

# # debug
# DEBUG="*"
# SECC_LOG="/tmp/secc.log"
# SECC_CMDLINE=0

# # mode
# SECC_CROSS=0
# SECC_CACHE=1
# #SECC_MODE="1"      # FIXME : need to implement MODE 2

#default settings
[[ -z $SECC_CROSS ]] && SECC_CROSS="0"   # default CROSS = FALSE
[[ -z $SECC_CACHE ]] && SECC_CACHE="1"   # default CACHE = TRUE
[[ -z $SECC_MODE ]] && SECC_MODE="1"     # default MODE  = 1 preprocessed
[[ -z $TMPDIR ]] && TMPDIR="/tmp"
[[ -z $SECC_PORT ]] && SECC_PORT="10509" # default PORT = 10509

if [[ $SECC_CROSS == "1" ]] ; then
  SECC_CROSS="true"
else
  SECC_CROSS="false"
fi
if [[ $SECC_CACHE == "1" ]] ; then
  SECC_CACHE="true"
else
  SECC_CACHE="false"
fi
if [[ $SECC_CMDLINE == "1" ]] ; then
  SECC_CMDLINE="true"
else
  SECC_CMDLINE="false"
fi
if [[ -n $DEBUG ]] ; then
  [[ -z $SECC_LOG ]] && SECC_LOG=/dev/stdout
else
  SECC_LOG=/dev/null  
fi

COMPILER_PATH=$0
ARGV=$(printf '%q ' "$@")  # preserve double quotes. ex, -DMMM=\"ABC\"
COMPILER=${COMPILER_PATH##*/}
RANDOM=$$                  # seed from PID
RANDOM_STRING=$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM
PREPROCESSED_SOURCE_PATH="${TMPDIR}/secc-${RANDOM_STRING:0:5}"
PREPROCESSED_GZIP_PATH=${PREPROCESSED_SOURCE_PATH}_in.gz
OUTPUT_TAR_PATH=${PREPROCESSED_SOURCE_PATH}_out.tar
OPTION_ANALYZE_PATH=${PREPROCESSED_SOURCE_PATH}_option.txt
JOB_PATH=${PREPROCESSED_SOURCE_PATH}_job.txt
OPTION_HEADER_PATH=${PREPROCESSED_SOURCE_PATH}_option_header.txt
JOB_HEADER_PATH=${PREPROCESSED_SOURCE_PATH}_job_header.txt
COMPILE_HEADER_PATH=${PREPROCESSED_SOURCE_PATH}_compile_header.txt
CACHE_HEADER_PATH=${PREPROCESSED_SOURCE_PATH}_cache_header.txt
CURL_LOG_FORMAT="[$$] code:%{http_code} type:%{content_type} upload:%{size_upload}/%{speed_upload} download:%{size_download}/%{speed_download} time:%{time_total} file:%{filename_effective}\n"

log()
{
  read -r INPUT

  # FIXME : only works under Linux
  case "$1" in
    "gray")    COLOR_PREFIX="\e[30m" ;;
    "red")     COLOR_PREFIX="\e[31m" ;;
    "green")   COLOR_PREFIX="\e[32m" ;;
    "yellow")  COLOR_PREFIX="\e[33m" ;;
    "blue")    COLOR_PREFIX="\e[34m" ;;
    "magenta") COLOR_PREFIX="\e[35m" ;;
    "cyan")    COLOR_PREFIX="\e[36m" ;;
    *)         COLOR_PREFIX="\e[39m" ;; #default(white?)
  esac

  echo -e "[\e[93m$$\e[0m] ${COLOR_PREFIX}${INPUT}\e[0m" >> ${SECC_LOG}
}

deleteTempFiles()
{
  rm -rf ${PREPROCESSED_SOURCE_PATH} > /dev/null 2>&1
  rm -rf ${PREPROCESSED_GZIP_PATH}   > /dev/null 2>&1
  rm -rf ${OUTPUT_TAR_PATH}          > /dev/null 2>&1
  rm -rf ${OPTION_ANALYZE_PATH}      > /dev/null 2>&1
  rm -rf ${JOB_PATH}                 > /dev/null 2>&1
  rm -rf ${OPTION_HEADER_PATH}       > /dev/null 2>&1
  rm -rf ${JOB_HEADER_PATH}          > /dev/null 2>&1
  rm -rf ${COMPILE_HEADER_PATH}      > /dev/null 2>&1
  rm -rf ${CACHE_HEADER_PATH}        > /dev/null 2>&1
}

passThrough()
{
  echo "passThrough : $1" | log "red"
  deleteTempFiles
  eval "/usr/bin/${COMPILER} ${ARGV}"
  EXIT_CODE=$?
  exit ${EXIT_CODE}
}

#FIXME : better way?
printCommand()
{
  export >> ${SECC_LOG}
  echo "${COMPILER_PATH} ${ARGV}" | log "magenta"
}

echo "--- SECC START --- "$(date) | log
[[ "$SECC_CMDLINE" == "true" ]] && printCommand

## basic checks
[[ -z "$1" ]] && passThrough "no arguments"
[[ -z "$SECC_ADDRESS" ]] && passThrough "no SECC_ADDRESS"
[[ $PWD == *"/CMakeFiles/"* ]] && passThrough "in CMakeFiles"   # //always passThrough in CMakeFiles 

OPTION_C_EXISTS="0"
argv='['
for arg in "$@"
do
  [[ $arg == "-c" ]] && OPTION_C_EXISTS="1";
  arg=${arg//\\/\\\\} # \
  arg=${arg//\"/\\\"} # "
  argv+='"'${arg}'", '
done
argv=${argv/%, /}
argv+=']'
[[ $OPTION_C_EXISTS == "0" ]] && passThrough "-c not exists"


data='{"compiler":"'${COMPILER}'"
,"cwd":"'${PWD}'"
,"mode":"'${SECC_MODE}'"
,"argv":'${argv}'}'
#echo $data

#--silent | --verbose
COMMAND="curl \
--max-time 10 \
-X POST \
-H 'Content-Type: application/json' \
-H 'Accept: text/plain' \
http://$SECC_ADDRESS:$SECC_PORT/option/analyze \
-d '${data}' \
-o '${OPTION_ANALYZE_PATH}' \
--dump-header '${OPTION_HEADER_PATH}' \
--noproxy ${SECC_ADDRESS} \
--write-out '${CURL_LOG_FORMAT}'"

echo $COMMAND | log "green"
eval $COMMAND 1>> ${SECC_LOG} 2> /dev/null
[[ $? != 0 ]] && passThrough "error on SCHEDULER/option/analyze"
HEADER=$(cat ${OPTION_HEADER_PATH} 2> /dev/null)
[[ $? != 0 ]] && passThrough "error on SCHEDULER/option/analyze header"     # No such file or directory
OUTPUT_HEADER_STATUS=$(echo "$HEADER" | grep "HTTP/1.1 200 OK")
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
  "cachePrefered" : '${SECC_CACHE}',
  "crossPrefered" : '${SECC_CROSS}',
  "sourcePath" : "'${OPTION_infile}'",
  "sourceHash" : "'${SOURCE_HASH}'",
  "argvHash" : "'${OPTION_argvHash}'"
}'

#--silent
COMMAND="curl \
-X POST \
-H 'Content-Type: application/json' \
-H 'Accept: text/plain' \
http://$SECC_ADDRESS:$SECC_PORT/job/new \
-d '$data' \
-o '${JOB_PATH}' \
--dump-header '${JOB_HEADER_PATH}' \
--noproxy ${SECC_ADDRESS} \
--write-out '${CURL_LOG_FORMAT}'"

echo $COMMAND | log "green"
eval $COMMAND 1>> ${SECC_LOG} 2> /dev/null
[[ $? != 0 ]] && passThrough "error on SCHEDULER/job/new curl"
HEADER=$(cat ${JOB_HEADER_PATH} 2> /dev/null)
[[ $? != 0 ]] && passThrough "error on SCHEDULER/job/new header"     # No such file or directory
OUTPUT_HEADER_STATUS=$(echo "$HEADER" | grep "HTTP/1.1 200 OK")
[[ -z "$OUTPUT_HEADER_STATUS" ]] && passThrough "error on DAEMON's compilation(not 200)"

JOB=$(cat ${JOB_PATH})
[[ $? != 0 ]] && passThrough "error on SCHEDULER/job/new"


JOB_archiveId=$(echo "$JOB" | grep "archive/archiveId=" | awk -F"archive/archiveId=" '{print $2}')
JOB_jobId=$(echo "$JOB" | grep "jobId=" | awk -F"jobId=" '{print $2}')
JOB_daemonAddress=$(echo "$JOB" | grep "daemon/daemonAddress=" | awk -F"daemon/daemonAddress=" '{print $2}')
JOB_daemonPort=$(echo "$JOB" | grep "daemon/system/port=" | awk -F"daemon/system/port=" '{print $2}')
JOB_local=$(echo "$JOB" | grep "local=" | awk -F"local=" '{print $2}')
JOB_cache=$(echo "$JOB" | grep "cache=" | awk -F"cache=" '{print $2}')
JOB_errorMessage=$(echo "$JOB" | grep "error/message=" | awk -F"error/message=" '{print $2}')

[[ "$JOB_local" == "true" ]] && passThrough "local from SCHEDULER/job/new" "${JOB_errorMessage}"


# echo $JOB_archiveId
# echo $JOB_jobId
# echo $JOB_daemonAddress
# echo $JOB_daemonPort

# try Cache if possible #oooOOooops. need to do refactoring.
if [[ "$SECC_CACHE" == "true" && "$JOB_cache" == "true" ]]; then
  CACHE_URL="http://${JOB_daemonAddress}:${JOB_daemonPort}/cache/${JOB_archiveId}/${SOURCE_HASH}/${OPTION_argvHash}"
  echo "cache is available. try URL : ${CACHE_URL}" | log "cyan"
  COMMAND="curl \
  -X GET \
  --max-time 10 \
  --compressed \
  -o '${OUTPUT_TAR_PATH}' \
  --dump-header '${CACHE_HEADER_PATH}' \
  ${CACHE_URL} \
  --noproxy ${SECC_ADDRESS} \
  --write-out '${CURL_LOG_FORMAT}'"

  echo $COMMAND | log "blue"
  eval $COMMAND 1>> ${SECC_LOG} 2> /dev/null

  if [[ $? == 0 ]]; then
    HEADER=$(cat ${CACHE_HEADER_PATH} 2> /dev/null)
    if [[ $? == 0 ]]; then
      CACHE_HEADER_SECC_CODE=$(echo "$CACHE_HEADER" | grep "secc-code:" | sed -e "s/secc-code://")
      CACHE_HEADER_SECC_STDOUT=$(echo "$CACHE_HEADER" | grep "secc-stdout:" | sed -e "s/secc-stdout://")
      CACHE_HEADER_SECC_STDERR=$(echo "$CACHE_HEADER" | grep "secc-stderr:" | sed -e "s/secc-stderr://")
      CACHE_HEADER_STATUS=$(echo "$HEADER" | grep "HTTP/1.1 200 OK")
      if [[ -n "$CACHE_HEADER_STATUS" && "$CACHE_HEADER_SECC_CODE" != "0" ]]; then
        [[ -n "${CACHE_HEADER_SECC_STDOUT}" ]] && printf '%b' "${CACHE_HEADER_SECC_STDOUT//%/\\x}" > /dev/stdout
        [[ -n "${CACHE_HEADER_SECC_STDERR}" ]] && printf '%b' "${CACHE_HEADER_SECC_STDERR//%/\\x}" > /dev/stderr

        # target directory
        [[ -n "$OPTION_outfile" ]] && OUTPUT_DIR=$(dirname $OPTION_outfile)
        [[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR=${PWD}

        # untar
        COMMAND="tar xvf ${OUTPUT_TAR_PATH} --directory ${OUTPUT_DIR} 1>>${SECC_LOG} 2>&1"
        echo $COMMAND | log "blue"
        eval $COMMAND
        if [[ $? == 0 ]]; then
          # clean up
          deleteTempFiles

          echo "--- SECC END ---" | log
          exit 0
        else
          echo "error on cache untar" | log
        fi
      else
        echo "error on DAEMON/cache/${JOB_archiveId}/${SOURCE_HASH}/${OPTION_argvHash} bad request" | log
      fi
    else
      echo "error on DAEMON/cache/${JOB_archiveId}/${SOURCE_HASH}/${OPTION_argvHash} header" | log
    fi
  else
    echo "error on DAEMON/cache/${JOB_archiveId}/${SOURCE_HASH}/${OPTION_argvHash} curl" | log
  fi
fi

# OPTION_remoteArgv to comma seperated string
for arg in ${OPTION_remoteArgv[@]}
do
  SECC_ARGV+="\"$arg\","
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
COMMAND="curl \
-X POST \
--max-time 60 \
--compressed \
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
--dump-header '${COMPILE_HEADER_PATH}' \
http://${JOB_daemonAddress}:${JOB_daemonPort}/compile/preprocessed/${JOB_archiveId} \
--noproxy ${SECC_ADDRESS} \
--write-out '${CURL_LOG_FORMAT}'"

echo $COMMAND | log "green"
eval $COMMAND 1>> ${SECC_LOG} 2> /dev/null
[[ $? != 0 ]] && passThrough "error on DAEMON/compile/preprocessed/${JOB_archiveId}"

OUTPUT_HEADER=$(cat ${COMPILE_HEADER_PATH} 2> /dev/null)
[[ $? != 0 ]] && passThrough "error on DAEMON/compile/preprocessed/${JOB_archiveId} header" # No such file or directory

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
echo $COMMAND | log "green"
eval $COMMAND
[[ $? != 0 ]] && passThrough "error on untar"



# echo ${PREPROCESSED_SOURCE_PATH}
# echo ${PREPROCESSED_GZIP_PATH}
# echo ${OUTPUT_TAR_PATH}

# clean up
deleteTempFiles

echo "--- SECC END --- " | log
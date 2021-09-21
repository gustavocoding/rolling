#!/usr/bin/env bash

set -e -o pipefail -o errtrace -o functrace

. ./lib.sh

CACHE_NAME="rolling"

usage() {
   cat << EOF
      Usage: ./do-rolling.sh [-s /path/to/source] [-t /path/to/target] [-b hotrod version] [-e entries] [-m encoding] [-c cache creation] [-r remote store creation]
      -s Path to the source server installation
      -t Path to the target server installation
      -b Hot Rod version of the source cluster (Default: '2.5')
      -e Number of entries (Default: '500000')
      -c Cache creation type in the source/target cluster, static or dynamic. (Default: 'static')
      -r Remote store creating in the target cluster: 'static' through the manipulation of the config xml or 'dynamically' adding a temp store via REST (Default: 'static')
      -m Encoding to use in the cache, e.g. "text-plain" (Default: no encoding)
      -h help
EOF
}

while getopts ":s:t:b:e:c:r:m:h" o; do
  case "${o}" in
  h)
    usage
    exit 0
    ;;
  s)
    s=${OPTARG}
    ;;
  t)
    t=${OPTARG}
    ;;
  b)
    b=${OPTARG}
    ;;
  e)
    e=${OPTARG}
    ;;
  c)
    c=${OPTARG}
    ;;
  r)
    r=${OPTARG}
    ;;
  m)
    m=${OPTARG}
    ;;
  *)
    usage
    exit 0
    ;;
  esac
done
shift $((OPTIND - 1))

if [[ -z "${s}" ]] || [[ -z "${t}" ]]; then
  usage
  exit 1
fi

SOURCE_HOME=${s}
TARGET_HOME=${t}
HOT_ROD=${b:-"2.5"}
NUM_ENTRIES=${e:-500000}
CACHE_CREATION=${c:-"static"}
STORE_CREATION=${r:-"static"}
ENCODING=${m}

VERSION_TARGET=$(rhdgVersion $TARGET_HOME)

if [ -n "$ENCODING" ]; then
  ENCODING_PARAM="-t $ENCODING"
fi

if [ -n "$STORE_CREATION" ]; then
  STORE_PARAM="-a $STORE_CREATION"
fi

disableSecurity $SOURCE_HOME
disableSecurity $TARGET_HOME

echo -e "\nSTARTING AND POPULATING A 2-NODE SOURCE CLUSTER from $SOURCE_HOME\n"

./prepare-cluster.sh -s $SOURCE_HOME -b ${HOT_ROD} -n source -r ${CACHE_CREATION} $ENCODING_PARAM

echo -e "\nSTARTING A 2-NODE TARGET CLUSTER from $TARGET_HOME\n"
./prepare-cluster.sh -s $TARGET_HOME -n target -p 2000 -l n -m 234.99.54.15 -r ${CACHE_CREATION} $ENCODING_PARAM $STORE_PARAM

if is8 $VERSION_TARGET; then
  echo -e "\nDOING ROLLING UPGRADE\n"
  ACTION=$(getRESTAction $VERSION_TARGET)
  curl -X$ACTION http://127.0.0.1:13222/rest/v2/caches/$CACHE_NAME?action=sync-data

  echo -e "\nDISCONNECTION FROM SOURCE CLUSTER\n"
  curl -X$ACTION http://127.0.0.1:13222/rest/v2/caches/$CACHE_NAME?action=disconnect-source
  curl -X$ACTION http://127.0.0.1:14222/rest/v2/caches/$CACHE_NAME?action=disconnect-source

  echo -e "\nSTOPPING SOURCE CLUSTER\n"
  kill $(jps -lmv | grep source | awk '{print $1}' | xargs)

  echo -e "\nCHECKING MIGRATED DATA\n"
  response=$(curl -s http://127.0.0.1:14222/rest/v2/caches/$CACHE_NAME?action=size)
  if [ "$response" -eq "$NUM_ENTRIES" ]; then
    echo "$CACHE_NAME cache - TEST PASSED"
  else
    echo "$CACHE_NAME cache - TEST FAILED"
  fi

else
  # Execute a rolling upgrade
  CLI=$(cliScript $TARGET_HOME)
  echo -e "\nDOING ROLLING UPGRADE\n"
  $TARGET_HOME/bin/$CLI --connect controller=127.0.0.1:11990 -c -c "/subsystem=datagrid-infinispan/cache-container=clustered/distributed-cache=$CACHE_NAME:synchronize-data(read-batch=500,write-threads=2, migrator-name=hotrod)"

  echo -e "\nDISCONNECTION FROM SOURCE CLUSTER\n"
  $TARGET_HOME/bin/$CLI --connect controller=127.0.0.1:11990 -c -c "/subsystem=datagrid-infinispan/cache-container=clustered/distributed-cache=$CACHE_NAME:disconnect-source(migrator-name=hotrod)"
  $TARGET_HOME/bin/$CLI --connect controller=127.0.0.1:12990 -c -c "/subsystem=datagrid-infinispan/cache-container=clustered/distributed-cache=$CACHE_NAME:disconnect-source(migrator-name=hotrod)"

  echo -e "\nCHECKING MIGRATED DATA\n"
  $TARGET_HOME/bin/$CLI --connect controller=127.0.0.1:11990 -c -c "/subsystem=datagrid-infinispan/cache-container=clustered/distributed-cache=$CACHE_NAME:read-attribute(name=number-of-entries)"
fi

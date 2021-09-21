#!/usr/bin/env bash
set -e  -o pipefail -o errtrace -o functrace

. ./lib.sh

function jdg6-is-ready() {
   local offset=$1
   CLI=$(cliScript $SERVER_HOME)
   $($SERVER_HOME/bin/$CLI --connect localhost:$(( 9999 + offset ))  --file=server-ready.cli | grep -q running)
}

function jdg7-is-ready() {
   local offset=$1
   CLI=$(cliScript $SERVER_HOME)
   $($SERVER_HOME/bin/$CLI --controller=localhost:$(( 9990 + offset )) -c ":read-attribute(name=server-state)" | grep -q running)
}

function jdg8-is-ready() {
   local offset=$1
   $(curl --silent --output /dev/null http://localhost:$(( 11222 + offset ))/rest/v2/cache-managers/$CACHE_NAME/health)
}

function is-ready() {
   if [ $VERSION -eq 6 ]; then
     jdg6-is-ready $1
   elif [ $VERSION -eq 7 ]; then
     jdg7-is-ready $1
   elif is8 $VERSION; then
     jdg8-is-ready $1
   fi
}

function connect-store() {
  curl -H "Content-Type: application/json" -d '{"remote-store":{"protocol-version":"'${HOT_ROD}'", "hotrod-wrapping":true,"raw-values":true,"segmented":false,"shared": true,"cache":"'${CACHE_NAME}'","remote-server":{"host":"127.0.0.1","port":11222}}}' "http://127.0.0.1:$(( 11222 + $PORT_OFFSET ))/rest/v2/caches/$CACHE_NAME/rolling-upgrade/source-connection"
}

function create-cache-rest() {
  curl -H "Content-Type: application/json" -d '{"distributed-cache":{"mode":"SYNC"}}' "http://127.0.0.1:$(( 11222 + $PORT_OFFSET ))/rest/v2/caches/$CACHE_NAME"
}

function create-cache-store-rest() {
  curl -H "Content-Type: application/json" -d '{"distributed-cache":{"mode":"SYNC","persistence":{"remote-store":{"protocol-version":"'${HOT_ROD}'","hotrod-wrapping":true,"shared": true,"raw-values":true,"segmented":false,"cache":"'$CACHE_NAME'","remote-server":{"host":"127.0.0.1","port":11222}}}}}' "http://127.0.0.1:$(( 11222 + $PORT_OFFSET ))/rest/v2/caches/$CACHE_NAME"
}

function pre-start() {
   if [ -n "$ENCODING" ]; then
      ENCODING_PARAM="-m $ENCODING"
   fi
   if [[ $CACHE_CREATION == "static" ]]; then
     if [[ $REMOTE_STORE == "static" ]]; then
          ./add-cache.sh -f $CONFIG_PATH/$CONFIG_FILE -c $CACHE_NAME -b ${HOT_ROD} $ENCODING_PARAM -r true
     else
          ./add-cache.sh -f $CONFIG_PATH/$CONFIG_FILE -c $CACHE_NAME -b ${HOT_ROD} $ENCODING_PARAM
     fi
   fi
}

function post-start() {
  if [ -n "$ENCODING" ]; then
    ENCODING_PARAM="-m $ENCODING"
  fi

  if [[ $CACHE_CREATION == "static" && $REMOTE_STORE == "dynamic" ]]; then
    connect-store
  fi

  if [[ $CACHE_CREATION == "dynamic" ]]; then
      if is8 $VERSION; then
        EXISTS=$(curl -o /dev/null -s -w "%{http_code}\n" "http://127.0.0.1:$(( 11222 + $PORT_OFFSET ))/rest/v2/caches/$CACHE_NAME")
        if [ $EXISTS -eq 200 ]; then
          echo "Cache Already existed, deleting"
          curl -XDELETE "http://127.0.0.1:$(( 11222 + $PORT_OFFSET ))/rest/v2/caches/$CACHE_NAME"
        fi
        if [[ $REMOTE_STORE == "dynamic" ]]; then
          echo -e "\nCreating cache $CACHE_NAME with store dynamically\n"
          create-cache-rest
          connect-store
        fi
        if [[ $REMOTE_STORE == "static" ]]; then
          create-cache-store-rest
        fi
        if [[ $REMOTE_STORE == "none" ]]; then
          create-cache-rest
        fi
        else
          echo "VERSION $VERSION not supported!"
          exit 1
      fi
  fi
}

function start() {
  DEBUG_PORT=$(( $2 + 2000 ))
  nohup $EXECUTABLE -c $CONFIG_FILE --debug $DEBUG_PORT -D$NODE_NAME_PROP=$1 -D$DATADIR_PROP=$SERVER_HOME/standalone/data/$1 -Djava.net.preferIPv4Stack=true -D$PORT_OFFSET_PROP=$2 -D$MULTICAST_PROP_NAME=$3 > logs/server-$1.log &
  while ! is-ready $2 2>/dev/null
  do
   echo "waiting for server to start"
   sleep 5;
  done
}
export JAVA_OPTS="-Xmx2g"

usage() {
   cat << EOF
      Usage: ./prepare-cluster.sh [-n name] [-s server home] [-b Hot Rod version] [-p port offset] [-l load data] [-m multicast address] [-e entries] [-r cache creation] [-t encoding] [-a add remote store]
    -n Cluster name (Default=cluster)
    -s Server home folder
    -b Hot Rod version (Default=2.5)
    -p Port offset (Default=0)
    -l Load data (Default=y)
    -m Multicast address (Default=234.99.54.14)
    -e Number of entries to put in the cache (Default=500000)
    -r Cache creation type in the source/target cluster, static or dynamic. (Default: 'dynamic')
    -t Encoding to use in the cache, e.g. "text-plain" (Default: no encoding)
    -a Remote store creating in the target cluster: 'static' or 'dynamic' (Default: 'none')
    -h help
EOF
}

while getopts ":n:s:c:b:p:l:m:e:r:t:a:h" o; do
    case "${o}" in
        h) usage; exit 0;;
        n)
            n=${OPTARG}
            ;;
        s)
            s=${OPTARG}
            ;;
        b)
            b=${OPTARG}
            ;;
        p)
            p=${OPTARG}
            ;;
        l)
            l=${OPTARG}
            ;;
        m)
            m=${OPTARG}
            ;;
        e)
            e=${OPTARG}
            ;;
        r)
            r=${OPTARG}
            ;;
        t)
            t=${OPTARG}
            ;;
        a)
            a=${OPTARG}
            ;;
        *)
            usage; exit 0
            ;;
    esac
done
shift $((OPTIND-1))

if [[ -z "${s}"  ]]
then
    usage
    exit 1
fi

CLUSTER_NAME=${n:-cluster}
SERVER_HOME=${s}
HOT_ROD=${b:-2.5}
PORT_OFFSET=${p:-0}
LOAD=${l:-y}
MCAST=${m:-234.99.54.14}
NUM_ENTRIES=${e:-500000}
CACHE_CREATION=${r:-"dynamic"}
ENCODING=${t}
REMOTE_STORE=${a:-"none"}

CACHE_NAME="rolling"
ALT_PORT=$(( PORT_OFFSET + 1000 ))
MULTICAST_PROP_NAME=jboss.default.multicast.address
NODE_NAME_PROP=jboss.node.name
DATADIR_PROP=jboss.server.data.dir
PORT_OFFSET_PROP=jboss.socket.binding.port-offset
EXECUTABLE=$SERVER_HOME/bin/standalone.sh
VERSION=$(rhdgVersion $SERVER_HOME)

if is8 $VERSION; then
  CONFIG_PATH=$SERVER_HOME/server/conf
else
  CONFIG_PATH=$SERVER_HOME/standalone/configuration
fi

CONFIG_FILE=clustered.xml


if is8 "$VERSION"; then
   NODE_NAME_PROP=infinispan.node.name
   DATADIR_PROP=infinispan.server.data.path
   PORT_OFFSET_PROP=infinispan.socket.binding.port-offset
   MULTICAST_PROP_NAME=jgroups.mcast_addr
   EXECUTABLE=$SERVER_HOME/bin/server.sh
   CONFIG_FILE=infinispan.xml
fi

mkdir -p logs

pre-start

start node1-$CLUSTER_NAME $PORT_OFFSET $MCAST
start node2-$CLUSTER_NAME $ALT_PORT $MCAST

post-start

createUser $SERVER_HOME user passwd-123


if [[ $LOAD = "y" ]]
then
   ./jbang bin/Load.java --entries ${NUM_ENTRIES} --write-batch 1000 --phrase-size 100 --hotrodversion ${HOT_ROD}
fi

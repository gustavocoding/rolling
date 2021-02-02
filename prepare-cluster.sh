#!/usr/bin/env bash
set -e  -o pipefail -o errtrace -o functrace

. ./lib.sh

function jdg6-is-ready() {
   local offset=$1
   $($SERVER_HOME/bin/cli.sh --connect localhost:$(( 9999 + offset ))  --file=server-ready.cli | grep -q running)
}

function jdg7-is-ready() {
   local offset=$1
    $($SERVER_HOME/bin/cli.sh --controller=localhost:$(( 9990 + offset )) -c ":read-attribute(name=server-state)" | grep -q running)
}

function jdg8-is-ready() {
   local offset=$1
   $(curl --digest -u user:passwd-123  --silent --output /dev/null http://localhost:$(( 11222 + offset ))/rest/v2/cache-managers/default/health)
}

function is-ready() {
   if [ $MAJOR -eq 6 ]; then
     jdg6-is-ready $1
   elif [ $MAJOR -eq 7 ]; then
     jdg7-is-ready $1
   elif [ $MAJOR -eq 8 ]; then
     jdg8-is-ready $1
   fi
}

function start() {
  DEBUG_PORT=$(( $2 + 2000 ))
  nohup $EXECUTABLE -c $CONFIG_FILE --debug $DEBUG_PORT -D$NODE_NAME_PROP=$1 -D$DATADIR_PROP=$SERVER_HOME/standalone/data/$1 -Djava.net.preferIPv4Stack=true -D$PORT_OFFSET_PROP=$2 -D$MULTICAST_PROP_NAME=$3 > logs/server-$1.log &
  while ! is-ready $2 2>/dev/null
  do
   echo "waiting for server to start"
   sleep 1;
  done
}
export JAVA_OPTS="-Xmx2g"

usage() {
   cat << EOF
      Usage: ./prepare-cluster.sh [-n name] [-s server home] [-c config file] [-b Hot Rod version] [-p port offset] [-l load data] [-m multicast adress]
	-n Cluster name (Default=cluster)
   	-s Server home folder
	-c Config file (Default=clustered.xml for JDG 6 or 7 and infinispan.xml for JDG 8)
        -b Hot Rod version (Default=2.5)
        -p Port offset (Default=0)
	-l Load data (Default=y)
	-m Multicast address (Default=234.99.54.14)
        -h help
EOF
}

while getopts ":s:c:b:p:l:n:m:e:h" o; do
    case "${o}" in
        h) usage; exit 0;;
        s)
            s=${OPTARG}
            ;;
        c)
            c=${OPTARG}
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
        n)
            n=${OPTARG}
            ;;
        m)
            m=${OPTARG}
            ;;
        e)
            e=${OPTARG}
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

SERVER_HOME=${s}
HOT_ROD=${b:-2.5}
NUM_ENTRIES=${e:-500000}
PORT_OFFSET=${p:-0}
ALT_PORT=$(( PORT_OFFSET + 1000 ))
LOAD=${l:-y}
CLUSTER_NAME=${n:-cluster}
MCAST=${m:-234.99.54.14}
MULTICAST_PROP_NAME=jboss.default.multicast.address
NODE_NAME_PROP=jboss.node.name
DATADIR_PROP=jboss.server.data.dir
PORT_OFFSET_PROP=jboss.socket.binding.port-offset
EXECUTABLE=$SERVER_HOME/bin/standalone.sh
DEFAULT_CFG=clustered.xml

MAJOR=$(rhdgVersion $SERVER_HOME)

if [ $MAJOR -eq 8 ]; then
   NODE_NAME_PROP=infinispan.node.name
   DATADIR_PROP=infinispan.server.data.path
   PORT_OFFSET_PROP=infinispan.socket.binding.port-offset
   MULTICAST_PROP_NAME=jgroups.mcast_addr
   EXECUTABLE=$SERVER_HOME/bin/server.sh
   DEFAULT_CFG=infinispan.xml
   $SERVER_HOME/bin/cli.sh user create user -p passwd-123 &>/dev/null
fi

CONFIG_FILE=${c:-$DEFAULT_CFG}

mkdir -p logs

start node1-$CLUSTER_NAME $PORT_OFFSET $MCAST

if [ $MAJOR -ne 8 ]; then
  $SERVER_HOME/bin/add-user.sh -u user -p passwd-123 -a &>/dev/null
fi

start node2-$CLUSTER_NAME $ALT_PORT $MCAST

if [[ $LOAD = "y" ]]
then
   ./jbang bin/Load.java --entries ${NUM_ENTRIES} --write-batch 1000 --phrase-size 100 --hotrodversion ${HOT_ROD}
fi

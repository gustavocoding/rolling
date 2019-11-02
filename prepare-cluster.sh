#!/usr/bin/env bash

set -e -o pipefail -o errtrace -o functrace

function jdg6-is-ready() {
   local offset=$1
   $($SERVER_HOME/bin/cli.sh --connect localhost:$(( 9999 + offset ))  --file=server-ready.cli | grep -q running)
}

function jdg7-is-ready() {
   local offset=$1
    $($SERVER_HOME/bin/cli.sh --controller=localhost:$(( 9990 + offset )) -c ":read-attribute(name=server-state)" | grep -q running)
}

function is-ready() {
   if $SERVER_HOME/bin/cli.sh --help | grep commands &>/dev/null; then
     jdg7-is-ready $1
   elif $SERVER_HOME/bin/cli.sh --help | grep connect &>/dev/null; then
     jdg6-is-ready $1
   fi
}

function start() {
  nohup $SERVER_HOME/bin/standalone.sh -c $CONFIG_FILE -Djboss.node.name=$1 -Djava.net.preferIPv4Stack=true -Djboss.socket.binding.port-offset=$2 -Djboss.default.multicast.address=$3 > logs/server-$1.log &
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
	-c Config file (Default=clustered.xml)
        -b Hot Rod version (Default=2.5)
        -p Port offset (Default=0)
	-l Load data (Default=y)
	-m Multicast address (Default=234.99.54.14)
        -h help
EOF
}

while getopts ":s:c:b:p:l:n:m:h" o; do
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
CONFIG_FILE=${c:-clustered.xml}
HOT_ROD=${b:-2.5}
PORT_OFFSET=${p:-0}
ALT_PORT=$(( PORT_OFFSET + 1000 ))
LOAD=${l:-y}
CLUSTER_NAME=${n:-cluster}
MCAST=${m:-234.99.54.14}

mkdir -p logs
start node1-$CLUSTER_NAME $PORT_OFFSET $MCAST
$SERVER_HOME/bin/add-user.sh -u user -p passwd-123 -a &>/dev/null

start node2-$CLUSTER_NAME $ALT_PORT $MCAST

if [[ $LOAD = "y" ]]
then
  ./bin/load.sh --entries 50000 --write-batch 1000 --phrase-size 1000 --hotrodversion ${HOT_ROD}
fi

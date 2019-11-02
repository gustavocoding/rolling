#!/usr/bin/env bash

set -e -o pipefail -o errtrace -o functrace
set -x

usage() {
   cat << EOF
      Usage: ./add-remote-store.sh [-f file] [-c cache name] [-b Hot Rod version]
      -f Path to file to add the remote store
      -c name of the cache (Default='default')
      -b Hot Rod version (Default=2.5)
      -h help
EOF
}

while getopts ":f:c:b:h" o; do
    case "${o}" in
        h) usage; exit 0;;
        f)
            f=${OPTARG}
            ;;
        c)
            c=${OPTARG}
            ;;
        b)
            b=${OPTARG}
            ;;
        *)
            usage; exit 0
            ;;
    esac
done
shift $((OPTIND-1))

if [[ -z "${f}"  ]]
then
    usage
    exit 1
fi

CONFIG_FILE=${f}
HOT_ROD=${b:-2.5}
CACHE=${c:-0}

ROOT_NS=$(cat $CONFIG_FILE | grep -oP  '(?<=<server xmlns=").*(?=">)')
CACHE_NS=$(cat $CONFIG_FILE | grep -oP '(?<=<subsystem xmlns=").*(?=" default-cache.*)')

xmlstarlet ed -L -N x="$CACHE_NS" -s "//x:distributed-cache[@name='$CACHE']" -t elem -n remote-store -v "" \
         -i //remote-store -t attr -n cache -v $CACHE \
         -i //remote-store -t attr -n socket-timeout -v 60000 \
         -i //remote-store -t attr -n tcp-no-delay -v true \
         -i //remote-store -t attr -n protocol-version -v $HOT_ROD \
         -i //remote-store -t attr -n shared -v true \
         -i //remote-store -t attr -n hotrod-wrapping -v true \
         -i //remote-store -t attr -n purge -v false \
         -i //remote-store -t attr -n passivation -v false \
         -s //remote-store -t elem -n remote-server -v "" \
         -i //remote-store/remote-server -t attr -n outbound-socket-binding -v remote-store-hotrod-server $CONFIG_FILE

xmlstarlet ed -L -N x=$ROOT_NS --update "//x:remote-destination/@host"  --value  "127.0.0.1" $CONFIG_FILE

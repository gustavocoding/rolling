#!/usr/bin/env bash

set -e -o pipefail -o errtrace -o functrace

usage() {
   cat << EOF
      Usage: ./add-cache.sh [-f file] [-c cache name] [-r add store] [-b Hot Rod version] [-m encoding]
      -f Path to file to add the cache with remote store
      -c name of the cache (Default='default')
      -r add remote store persistence (Default='false')
      -b Hot Rod version to use in the Remote Store (Default=2.5)
      -m MediaType for keys and values (Default='')
      -h help
EOF
}

while getopts ":s:f:c:r:b:m:h" o; do
    case "${o}" in
        h) usage; exit 0;;
        f)
            f=${OPTARG}
            ;;
        c)
            c=${OPTARG}
            ;;
        r)    
           r=${OPTARG}
            ;;
        b)
            b=${OPTARG}
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

if [[ -z "${f}"  ]]
then
    usage
    exit 1
fi

CONFIG_FILE=${f}
HOT_ROD=${b:-2.5}
CACHE=${c:-"default"}
MEDIA_TYPE=${m}
REMOTE_STORE=${r:-"false"}

if [[ $CONFIG_FILE =~ "clustered" ]]; then
   # Wildly server
   SCHEMA_VERSION=$(cat "$CONFIG_FILE" | grep -m1 -Eo 'urn:infinispan:server:core:[0-9]+\.[0-9]' | head -1 | awk '{split($0,a,":"); print a[length(a)]}')
   CONFIG_NS="urn:infinispan:server:core:$SCHEMA_VERSION"
else
   SCHEMA_VERSION=$(cat "$CONFIG_FILE" | grep -m1 -Eo 'urn:infinispan:config:[0-9]+\.[0-9]' | head -1 | awk '{split($0,a,":"); print a[length(a)]}')
   CONFIG_NS="urn:infinispan:config:$SCHEMA_VERSION"
fi

function exists() {
  COUNT=$(xmlstarlet sel -N x="$CONFIG_NS" -t -v "count(//x:distributed-cache[@name='$1'])" "$CONFIG_FILE")
  echo "$COUNT"
}

function delete() {
  xmlstarlet ed -L -N x="$CONFIG_NS" -d "//x:distributed-cache[@name='$CACHE']" "$CONFIG_FILE"
}

function add-media-type() {
  if [ -n "$MEDIA_TYPE" ]; then
    xmlstarlet ed -L -N x="$CONFIG_NS" -s "//x:cache-container/x:distributed-cache[@name='$CACHE']" -t elem -n encoding -v "" -i //encoding -t attr -n media-type -v "$MEDIA_TYPE" "$CONFIG_FILE"
  fi
}

function addCacheOnly() {
  xmlstarlet ed -L -N x="$CONFIG_NS" -s "(//x:cache-container)[1]" -t elem -n distributed-cache -v "" -i //distributed-cache -t attr -n mode -v "SYNC" \
       -i //distributed-cache -t attr -n name -v "$CACHE" "$CONFIG_FILE"
  add-media-type
}

function addRemoteStoreNative() {
    # Add Remote Store namespace and xsd in the root element
    REMOTE_STORE_NS="urn:infinispan:config:store:remote:$SCHEMA_VERSION"
    REMOTE_STORE_XSD="https://infinispan.org/schemas/infinispan-cachestore-remote-config-$SCHEMA_VERSION.xsd"
    HAS_REMOTE_NS=$(cat "$CONFIG_FILE" | grep -m1 -Eo 'urn:infinispan:config:store:remote:[0-9]+\.[0-9]' || echo "0")
    if [ -z "$HAS_REMOTE_NS" ]; then
      xmlstarlet ed -L -N x="$CONFIG_NS" --insert "//x:infinispan" --type attr -n xmlns:remote -v "$REMOTE_STORE_NS"  "$CONFIG_FILE"
      xmlstarlet ed -L -N x="$CONFIG_NS" --update "//x:infinispan/@xsi:schemaLocation"  -x "concat(., \"  $REMOTE_STORE_NS $REMOTE_STORE_XSD\")"  "$CONFIG_FILE"
    fi

    # Add remote store to the cache
    xmlstarlet ed -L -N x="$CONFIG_NS" -s "//x:cache-container" -t elem -n distributed-cache -v "" -i //distributed-cache -t attr -n mode -v "SYNC" \
                 -i //distributed-cache -t attr -n name -v "$CACHE" \
                 -s //distributed-cache -t elem -n persistence -v "" -s //persistence -t elem -n remote-store  -v "" \
                 -i //remote-store -t attr -n xmlns -v "$REMOTE_STORE_NS" \
                 -i //remote-store -t attr -n cache -v "$CACHE" \
                 -i //remote-store -t attr -n socket-timeout -v 60000 \
                 -i //remote-store -t attr -n tcp-no-delay -v true \
                 -i //remote-store -t attr -n protocol-version -v "$HOT_ROD" \
                 -i //remote-store -t attr -n shared -v true \
                 -i //remote-store -t attr -n hotrod-wrapping -v true \
                 -i //remote-store -t attr -n raw-values -v true \
                 -i //remote-store -t attr -n segmented -v false \
                 -s //remote-store -t elem -n remote-server -v "" \
                 -i //remote-store/remote-server -t attr -n host -v "localhost" \
                 -i //remote-store/remote-server -t attr -n port -v "11222" "$CONFIG_FILE"
      add-media-type
}

function addRemoteStoreWildfly() {
    ROOT_NS=$(cat $CONFIG_FILE | grep -oP  '(?<=<server xmlns=").*(?=">)')

    xmlstarlet ed -L -N x="$CONFIG_NS" -s "(//x:cache-container)[1]" -t elem -n distributed-cache -v "" -i //distributed-cache -t attr -n mode -v "SYNC" \
                 -i //distributed-cache -t attr -n name -v "$CACHE" \
                 -s //distributed-cache -t elem -n remote-store  -v "" \
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
}

function addRemoteStore() {
  if [[ $CONFIG_FILE =~ "clustered" ]]; then
      addRemoteStoreWildfly
  else
      addRemoteStoreNative
  fi
}


if [ $(exists "$CACHE") != "0" ]; then
  echo "Cache $CACHE already exists, deleting"
  delete
fi

if [ "$REMOTE_STORE" = "true" ]; then
  addRemoteStore
else
  addCacheOnly
fi

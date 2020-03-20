#!/usr/bin/env bash

set -e -o pipefail -o errtrace -o functrace

. ./lib.sh


usage() {
   cat << EOF
      Usage: ./do-rolling.sh [-s source server home] [-t target server home] [-b source server Hot Rod version]
      -s Path to the source server installation
      -t Path to the target server installation
      -b Hot Rod version of the source cluster (Default: '2.5')
      -h help
EOF
}

while getopts ":s:t:b:h" o; do
    case "${o}" in
        h) usage; exit 0;;
        s)
            s=${OPTARG}
            ;;
        t)
            t=${OPTARG}
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

if [[ -z "${s}"  ]] || [[ -z "${t}"  ]]
then
    usage
    exit 1
fi

SOURCE_HOME=${s}
TARGET_HOME=${t}
HOT_ROD=${b:-"2.5"}

MAJOR_SOURCE=$(rhdgVersion $SOURCE_HOME)
MAJOR_TARGET=$(rhdgVersion $TARGET_HOME)

TARGET_CFG_DIR=$TARGET_HOME/standalone/configuration/

echo -e "\nSTARTING AND POPULATING A 2-NODE SOURCE CLUSTER from $SOURCE_HOME\n"
./prepare-cluster.sh -s $SOURCE_HOME -b ${HOT_ROD} -n source 


if [ $MAJOR_TARGET -ne 8 ]; then
   TARGET_CONF=clustered-rolling.xml
   echo -e "\nADDING REMOTE STORE CONFIG TO TARGET CLUSTER AT ${TARGET_CFG_DIR}${TARGET_CONF}\n"
   rm -f $TARGET_CFG_DIR/$TARGET_CONF
   cp $TARGET_CFG_DIR/clustered.xml $TARGET_CFG_DIR/$TARGET_CONF
   ./add-remote-store.sh -f $TARGET_CFG_DIR/$TARGET_CONF -c default -b ${HOT_ROD}
fi

echo -e "\nSTARTING A 2-NODE TARGET CLUSTER from $TARGET_HOME\n"
./prepare-cluster.sh -n target -s $TARGET_HOME -c $TARGET_CONF -p 2000 -l n -m 234.99.54.15

# Execute a rolling upgrade
echo -e "\nDOING ROLLING UPGRADE\n"
$TARGET_HOME/bin/cli.sh --connect controller=127.0.0.1:11990 -c -c "/subsystem=datagrid-infinispan/cache-container=clustered/distributed-cache=default:synchronize-data(read-batch=500, write-threads=2, migrator-name=hotrod)"

echo -e "\nDISCONNECTION FROM SOURCE CLUSTER\n"
$TARGET_HOME/bin/cli.sh --connect controller=127.0.0.1:11990 -c -c "/subsystem=datagrid-infinispan/cache-container=clustered/distributed-cache=default:disconnect-source(migrator-name=hotrod)"
$TARGET_HOME/bin/cli.sh --connect controller=127.0.0.1:12990 -c -c "/subsystem=datagrid-infinispan/cache-container=clustered/distributed-cache=default:disconnect-source(migrator-name=hotrod)"

echo -e "\nCHECKING MIGRATED DATA\n"
$TARGET_HOME/bin/cli.sh --connect controller=127.0.0.1:11990 -c -c "/subsystem=datagrid-infinispan/cache-container=clustered/distributed-cache=default:read-attribute(name=number-of-entries)"




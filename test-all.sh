####
#
# Sample script to test all migrations from 7.3.8 to 8.x versions.
# Download and extract all servers to a folder and change the DOWNLOAD_FOLDER variable below
#
###

set -e
DOWNLOAD_FOLDER=/home/servers/

function migrate() {
   local source=$1
   local target=$2
   ./kill.sh
   ./do-rolling.sh -s $1 -t $2 
}

# Same version migration
migrate $DOWNLOAD_FOLDER/jboss-datagrid-7.3.8-server $DOWNLOAD_FOLDER/jboss-datagrid-7.3.8-server 
migrate $DOWNLOAD_FOLDER/redhat-datagrid-8.0.1-server $DOWNLOAD_FOLDER/redhat-datagrid-8.0.1-server
migrate $DOWNLOAD_FOLDER/redhat-datagrid-8.1.1-server $DOWNLOAD_FOLDER/redhat-datagrid-8.1.1-server
migrate $DOWNLOAD_FOLDER/redhat-datagrid-8.2.0-server $DOWNLOAD_FOLDER/redhat-datagrid-8.2.0-server

# Migration from 7.3.8
migrate $DOWNLOAD_FOLDER/jboss-datagrid-7.3.8-server $DOWNLOAD_FOLDER/redhat-datagrid-8.0.1-server 
migrate $DOWNLOAD_FOLDER/jboss-datagrid-7.3.8-server $DOWNLOAD_FOLDER/redhat-datagrid-8.1.1-server 
migrate $DOWNLOAD_FOLDER/jboss-datagrid-7.3.8-server $DOWNLOAD_FOLDER/redhat-datagrid-8.2.0-server 

# Migration from 8.0.1
migrate $DOWNLOAD_FOLDER/redhat-datagrid-8.0.1-server $DOWNLOAD_FOLDER/redhat-datagrid-8.1.1-server
migrate $DOWNLOAD_FOLDER/redhat-datagrid-8.0.1-server $DOWNLOAD_FOLDER/redhat-datagrid-8.2.0-server

# Migration from 8.1.1
migrate $DOWNLOAD_FOLDER/redhat-datagrid-8.1.1-server $DOWNLOAD_FOLDER/redhat-datagrid-8.2.0-server


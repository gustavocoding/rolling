### TESTING ROLLING UPGRADES FOR JDG/RHDG

Simple and automated way to test a rolling upgrade between two JDG/RHDG versions.
Supported versions are: ```6.6.2```, ```7.0.x```, ```7.1.x```, ```7.2.x```, ```7.3.x```,```8.0x```

#### Requirements

* xmlstarlet
 
    ```dnf install xmlstarlet```

* sdkman: 

    ```curl -s "https://get.sdkman.io" | bash```
 
* java 8:

    ```sdk use java 8.0.252-amzn```
    
* scala

    ```sdk use scala 2.11.0```
    
* Memory: At least 10GB RAM to hold a total of 4 servers with their data
    
#### Usage

Download and extract the JDG/RHDG versions that will be used as source and target of the migration.

Execute the script:

```
./do-rolling.sh -s jdg-6.6.2-home/ -t jdg-7.1.0-home/
```

This will create a 2-node cluster of JDG-6.6.2, load some data, then creates a 2-node cluster of JDG 7.1.x
and will copy the data from the source to the target cluster, using the Default Hot Rod version ```2.5``` for the source cluster (the minimum version a cluster must have to support rolling upgrades).

A successful run should print:

```
STARTING AND POPULATING A 2-NODE SOURCE CLUSTER from servers/infinispan-server-6.4.2-redhat-SNAPSHOT

waiting for server to start
waiting for server to start

Loading 50000 entries with write batch size of 1000 and phrase size of 1000

Nov 02, 2019 9:24:02 AM org.infinispan.client.hotrod.impl.protocol.Codec20 readNewTopologyAndHash
INFO: ISPN004006: localhost:11222 sent new topology view (id=2, age=0) containing 2 addresses: [127.0.0.1:11222, 127.0.0.1:12222]

ADDING REMOTE STORE CONFIG TO TARGET CLUSTER AT servers/infinispan-server-8.4.2.Final-redhat-1/standalone/configuration/clustered-rolling.xml

STARTING A 2-NODE TARGET CLUSTER from servers/infinispan-server-8.4.2.Final-redhat-1

waiting for server to start
waiting for server to start

DOING ROLLING UPGRADE

{"outcome" => "success"}

DISCONNECTION FROM SOURCE CLUSTER

{"outcome" => "success"}

CHECKING MIGRATED DATA

{
    "outcome" => "success",
    "result" => 50000
}
```

#### Destroying the servers

The  ```kill.sh``` script will stop all servers in the source and target clusters

#### Logs

One log file will be created with the ```stdout``` of each server in the ```logs``` folder:

* server-node1-source.log
* server-node2-source.log
* server-node1-target.log
* server-node2-target.log

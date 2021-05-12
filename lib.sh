function rhdgVersion() {
 VER=0
 if $1/bin/server.sh --help 2>/dev/null | grep -q -E "12\."; then
    VER=8.2
 elif $1/bin/server.sh --help 2>/dev/null | grep -q -E "11\."; then
    VER=8.1
 elif $1/bin/server.sh --help 2>/dev/null | grep -q -E "10\."; then
    VER=8.0
 elif $1/bin/cli.sh --help 2>/dev/null| grep -q commands; then
    VER=7
 elif $1/bin/ispn-cli.sh --help 2>/dev/null| grep -q commands; then
    VER=7
 elif $1/bin/cli.sh --help 2>/dev/null| grep -q connect; then
   VER=6
 fi
 echo $VER
}

function cliScript() {
    CLI="cli.sh"
    if [ -f $1/bin/ispn-cli.sh ]; then
      CLI="ispn-cli.sh"
    fi
    echo $CLI
}

function is8() {
  if [ ${1:0:1} = "8" ]
  then
    return 0;
  else
    return 1;
  fi
}

function getRESTAction() {
    if is82OrLater $1; then
      echo "POST"
    else
      echo "GET"
    fi
}

function disableSecurity() {
  local VERSION=$(rhdgVersion $1)
  if is81OrLater $VERSION; then
    sed -i 's|security-realm="default"||' $1/server/conf/infinispan.xml
    sed -i 's|<authorization/>||' $1/server/conf/infinispan.xml
  fi
}

function is81OrLater() {
  major=${1:0:1}
  minor=${1:2:3}
  if [ "$major" = "8" ] && [ $minor -ge 1 ]
  then
    return 0;
  else
    return 1;
  fi
}

function is82OrLater() {
  major=${1:0:1}
  minor=${1:2:3}
  if [ "$major" = "8" ] && [ $minor -ge 2 ]
  then
    return 0;
  else
    return 1;
  fi
}

function createUser() {
  local HOME=$1
  local USER=$2
  local PASS=$3
  local VERSION=$(rhdgVersion $HOME)
  if is81OrLater $VERSION; then
    $HOME/bin/cli.sh user create $USER -p $PASS -g admin &>/dev/null
  else
    if is8 $VERSION; then
      $HOME/bin/user-tool.sh -u $USER -p $PASS -g admin -b
    else
       $HOME/bin/add-user.sh -u $USER -p $PASS -a &>/dev/null
    fi
  fi
}
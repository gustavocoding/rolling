function rhdgVersion() {
 MAJOR=0
 if $1/bin/server.sh --help &>/dev/null; then
    MAJOR=8
 elif $1/bin/cli.sh --help | grep commands &>/dev/null; then
    MAJOR=7
 elif $1/bin/cli.sh --help | grep connect &>/dev/null; then
   MAJOR=6
 fi
 echo $MAJOR
}

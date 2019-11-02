jcmd $(pgrep -f modules) GC.run
jstat -gcutil $(pgrep -f modules) 1000

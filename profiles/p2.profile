# Papercage Firejail Profile
noroot
private

# Explicitly allow loopback protocols
protocol unix,inet

# Whitelists
whitelist /opt/ai-bin
whitelist /opt/ai-agent/workspace
whitelist /opt/ai-agent/sockets
noblacklist /opt/ai-agent/sockets

# Hardening
caps.drop all
seccomp
nonewprivs

# Binaries
private-bin bash,sh,ls,cat,git,python3,node,npm,pytest,claude,socat,tail,grep,sed,awk,sleep,rm,mkdir,which,id,whoami,env,stty,iputils-ping

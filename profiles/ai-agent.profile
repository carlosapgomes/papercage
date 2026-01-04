# Papercage Firejail Profile
noroot
net none
private

# Whitelists
# Simplified Whitelists in ai-agent.profile
whitelist /opt/ai-bin
whitelist /opt/ai-agent/workspace
whitelist /opt/ai-agent/sockets
noblacklist /opt/ai-agent/sockets
# whitelist /opt/ai-bin
# whitelist /opt/ai-agent/workspace
# whitelist /opt/ai-agent/sockets
# whitelist /run/isoproxy/isoproxy.sock
# whitelist /opt/ai-agent/sockets/isoproxy.sock
# noblacklist /opt/ai-agent/sockets
# noblacklist /run/isoproxy

# Hardening
caps.drop all
seccomp
nonewprivs

# Minimal Toolbox for Python/Node/Pip
private-bin bash,sh,ls,cat,git,python3,node,npm,pytest,claude,socat,tail,stdbuf,grep,sed,awk,tr,sleep,rm,mkdir,pkill,which,id,whoami,env,stty


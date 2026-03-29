sudo nft add table inet zttato
sudo nft add chain inet zttato output { type filter hook output priority 0 \; }

sudo nft add rule inet zttato output tcp dport 443 accept
sudo nft add rule inet zttato output drop

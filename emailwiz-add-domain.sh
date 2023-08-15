#!/bin/bash

# Request domain name
read -p "Enter domain name: " domain

# Create SSL certificate for mail subdomain
sudo certbot certonly --standalone -d mail.$domain

# Add lines to dovecot.conf file
sudo tee -a /etc/dovecot/dovecot.conf <<EOF
# mail.$domain
local_name mail.$domain {
    ssl_cert = </etc/letsencrypt/live/mail.$domain/fullchain.pem
    ssl_key = </etc/letsencrypt/live/mail.$domain/privkey.pem
}
EOF

# Add line to vmail_ssl.map file
sudo tee -a /etc/postfix/vmail_ssl.map <<EOF
mail.$domain /etc/letsencrypt/live/mail.$domain/privkey.pem /etc/letsencrypt/live/mail.$domain/fullchain.pem
EOF

# Generate DKIM key
sudo mkdir -p "/etc/postfix/dkim/$domain"
sudo opendkim-genkey -D "/etc/postfix/dkim/$domain" -d "$domain" -s "mail.$domain"
sudo chgrp -R opendkim /etc/postfix/dkim/*
sudo chmod -R g+r /etc/postfix/dkim/*

# Add line to keytable file
sudo tee -a /etc/postfix/dkim/keytable <<EOF
mail._domainkey.$domain $domain:mail:/etc/postfix/dkim/$domain/mail.private
EOF

# Add line to signingtable file
sudo tee -a /etc/postfix/dkim/signingtable <<EOF
*@${domain} mail._domainkey.${domain}
EOF

# Apply changes and restart services
sudo postmap /etc/postfix/virtual
sudo postmap -F /etc/postfix/vmail_ssl.map
sudo systemctl restart postfix
sudo systemctl restart dovecot
sudo systemctl restart opendkim

# Show DKIM record to add to DNS server
subdom="mail"
pval="$(tr -d '\n' <"/etc/postfix/dkim/$domain/$subdom.txt" | sed "s/k=rsa.* \"p=/k=rsa; p=/;s/\"\s*\"//;s/\"\s*).*//" | grep -o 'p=.*')"
echo "$subdom._domainkey.$domain   TXT     v=DKIM1; k=rsa; $pval"

# Show SPF record to add to DNS server
echo "$domain        TXT     v=spf1 mx a:mail.$domain -all"

# Show DMARC record to add to DNS server
echo "_dmarc		IN	TXT	\"v=DMARC1; p=none; rua=mailto:dmarc@$domain; fo=1\""

echo "Done!"

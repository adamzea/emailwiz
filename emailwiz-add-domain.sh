#!/bin/sh

echo "Be sure to make an A record for your new mail.example.tld domain that points to the IP address of this server in your DNS server."
# Request domain name
read -p "Enter domain name to add: " domain

# Create SSL certificate for mail subdomain
sudo certbot -d "mail.$domain" certonly --register-unsafely-without-email --agree-tos

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
mail._domainkey.$domain $domain:mail:/etc/postfix/dkim/$domain/mail.$domain.private
EOF

# Replace "." in the domain with "\." to create domain-pcre 
domain_pcre=$(echo $domain | sed 's/\./\\./g') 
# Add the line to /etc/postfix/login_maps.pcre 
sudo tee -a /etc/postfix/login_maps.pcre <<EOF 
/^(.*)@$domain_pcre$/ \${1}
EOF

# Add line to signingtable file
sudo tee -a /etc/postfix/dkim/signingtable <<EOF
*@${domain} mail._domainkey.${domain}
EOF

# Add line to /etc/postfix/main.cf
# sudo tee -a /etc/postfix/main.cf <<EOF virtual_alias_domains = ${domain}
# EOF
# Edit the /etc/postfix/main.cf file
# Find the line that says "virtual_alias_domains ="
# Add the requested domain name to the end of that line
sed -i "/^virtual_alias_domains =/ s/$/ $domain/" /etc/postfix/main.cf



# Apply changes and restart services
sudo postmap /etc/postfix/virtual
sudo postmap -F /etc/postfix/vmail_ssl.map
sudo systemctl restart postfix
sudo systemctl restart dovecot
sudo systemctl restart opendkim

# Add deploy hook for certbot renewals to apply to Postfix 
# Create the reload-postfix.sh file
echo '#!/bin/bash' > /etc/letsencrypt/renewal-hooks/deploy/reload-postfix.sh
echo '' >> /etc/letsencrypt/renewal-hooks/deploy/reload-postfix.sh
# Add the desired commands
echo 'postmap -F /etc/postfix/vmail_ssl.map' >> /etc/letsencrypt/renewal-hooks/deploy/reload-postfix.sh
echo 'systemctl restart postfix && systemctl restart dovecot && systemctl restart opendkim' >> /etc/letsencrypt/renewal-hooks/deploy/reload-postfix.sh
# Make the script executable
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-postfix.sh

echo "Script 'reload-postfix.sh' has been created and configured."

# Show DKIM record to add to DNS server
subdom="mail"
pval="$(tr -d '\n' <"/etc/postfix/dkim/$domain/$subdom.$domain.txt" | sed "s/k=rsa.* \"p=/k=rsa; p=/;s/\"\s*\"//;s/\"\s*).*//" | grep -o 'p=.*')"
echo "$subdom._domainkey.$domain   TXT     v=DKIM1; k=rsa; $pval"

# Show SPF record to add to DNS server
echo "$domain        TXT     v=spf1 mx a:mail.$domain -all"

# Show DMARC record to add to DNS server
echo "_dmarc		IN	TXT	\"v=DMARC1; p=none; rua=mailto:dmarc@$domain; fo=1\""

echo "Done! Add the above records to your DNS server."

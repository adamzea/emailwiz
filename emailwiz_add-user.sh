#!/bin/bash

echo "Enter username:"
read username

useradd -m -G mail $username

echo "Enter password:"
passwd $username

echo "Enter email address:"
read email

echo "$email $username" >> /etc/postfix/virtual

postmap /etc/postfix/virtual
systemctl restart postfix

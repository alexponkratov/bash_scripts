#! /usr/bin/bash

cp /home/ponkratov/newcert/* /etc/letsencrypt/archive/mx1.vondelmarketing.com/
rm /home/ponkratov/newcert/*
chown -R root:root /etc/letsencrypt/archive/mx1.vondelmarketing.com
systemctl restart postfix dovecot

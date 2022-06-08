#! /bin/bash

dpkg-reconfigure tzdata
apt update && apt upgrade
apt install mc
cp /usr/share/mc/syntax/sh.syntax /usr/share/mc/syntax/unknown.syntax
wget https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_6.0-1+debian11_all.deb
dpkg -i zabbix-release_6.0-1+debian11_all.deb
apt update && apt upgrade
apt install zabbix-agent2
systemctl restart zabbix-agent2


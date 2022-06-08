#!/bin/bash

source ./variables.sh

if [ $# -lt 1 ]; then
    DOMAIN_NAME=$(whiptail --title "Параметры скрипта" --inputbox "Введите имя почтового домена" 8 60 domain_name.local 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [ $exitstatus = 0 ]; then
        echo "Скрипт произведет настройку почтового домена:" $DOMAIN_NAME
    else
        echo "Работа скрипта прервана."
        exit 1
    fi

    PARAMS=$(whiptail --title "Настроить следующие параметры для домена $DOMAIN_NAME" --checklist \
        "Выберете параметры для настройки:" 15 100 6 \
        "A" "Browser-based IMAP client (Roundcube)" ON \
        "B" "Сгенерировать DKIM key" ON \
        "C" "Добавить адреса агрегаторов входящей и исходящей почты    " ON \
        "D" "Добавить стандартные алиасы для почтового сервера" ON \
        "E" "Добавить домен $DOMAIN_NAME в БД postfix" ON 3>&1 1>&2 2>&3)
        exitstatus=$?
    if [ $exitstatus = 0 ]; then
	echo "Будет выполнена настройка следующий параметров для домена $DOMAIN_NAME:"
        for i in $PARAMS
         do
            if [ $i == "\"A\"" ]; then
                echo " - Установлен Web-baased IMAP клиент Roundcube. Адрес сайта: https://mail.$DOMAIN_NAME"
                INSTALL_ROUNDCUBE="Yes"
            fi
            if [ $i == "\"B\"" ]; then
                echo " - Будет сгенерирован DomainKey Identified Mail. Добавьте его в TXT-запись mail.__domainkey.$DOMAIN_NAME вашего DNS сервера."
                DKIM_KEY="Yes"
            fi
            if [ $i == "\"C\"" ]; then
                echo " - Будут добавлены ящики для сбора входящей и исходящей почты (all_in@$DOMAIN_NAME, all_out@$DOMAIN_NAME)"
                ALL_IN_OUT="Yes"
            fi
            if [ $i == "\"E\"" ]; then
                echo " - Домен $DOMAIN_NAME будет добавлен в БД postfix"
                ADD_DB_RECORD="Yes"
            fi
            if [ $i == "\"D\"" ]; then
                echo " - Будут добавлены стандартые алиасы для почтового сервера."
                ADD_ALIASES="Yes"
            fi
        done
    else
        echo "Работа скрипта прервана."
	exit 1
    fi
else
    echo "Скрипт производит подключение почтового домена к серверу."
    echo "Запускается без параметров: ./add-domain.sh."
    exit 1
fi


#
# Create mailbox directory
#
mkdir -p $MAILBOX_DIR/$DOMAIN_NAME
chown vmail:vmail $MAILBOX_DIR/$DOMAIN_NAME

#
# Make a site dir and copy roundcube web-mail engine
#
if [ "$INSTALL_ROUNDCUBE" = "Yes" ]; then 
    mkdir -p $SITEDIR/mail.$DOMAIN_NAME/{logs,www} 
    echo -e "Copy Roundcube site for mail\n"
    tar xf ./addDomain_files/roundcube_site_template.tar.gz -C /web/sites/mail.$DOMAIN_NAME
    sed -i "s/%Domain%/$DOMAIN_NAME/g" /web/sites/mail.$DOMAIN_NAME/www/config/config.inc.php
    chown -R www-data:www-data $SITEDIR/mail.$DOMAIN_NAME
    chmod -R 760 $SITEDIR/mail.$DOMAIN_NAME/www

#
# Copy apache configuration file for site and restart service
#
    echo -e "\nCopy Apache configuration file and restart Apache\n"
    cp ./addDomain_files/roundcube-site.conf /etc/apache2/sites-available/mail.$DOMAIN_NAME.conf
    sed -i "s/%Domain%/$DOMAIN_NAME/g" /etc/apache2/sites-available/mail.$DOMAIN_NAME.conf
    a2ensite mail.$DOMAIN_NAME.conf
    apache2ctl configtest
    systemctl reload apache2
    echo -e "Site web-mail $DOMAIN_NAME is ready.\n"
fi    

#
# Generate DKIM key and update postfix configuration file
#
if [ "$DKIM_KEY" = "Yes" ]; then 
    echo "Generate DKIM kyes"
    cd /etc/postfix/dkim
    opendkim-genkey -D /etc/postfix/dkim/ -d $DOMAIN_NAME -s mail
    mv mail.private mail.$DOMAIN_NAME.private
    mv mail.txt mail.$DOMAIN_NAME.txt
    echo *@$DOMAIN_NAME mail._domainkey.$DOMAIN_NAME >> signingtable
    echo mail._domainkey.$DOMAIN_NAME $DOMAIN_NAME:mail:/etc/postfix/dkim/mail.$DOMAIN_NAME.private >> keytable
    echo KeyFile            /etc/postfix/dkim/mail.$DOMAIN_NAME.private >> /etc/opendkim.conf
    chown -R root:opendkim /etc/postfix/dkim
    chmod u=rw,g=r,o= /etc/postfix/dkim/*
    echo -e "\nGenerate DKIM data is done. Plaese update DNS record. Add TXT record email._domainkey.$DOMAIN_NAME with text:\n"
    cat /etc/postfix/dkim/mail.$DOMAIN_NAME.txt
fi

if [ "$ALL_IN_OUT" = "Yes" ]; then 
    if [ -w $RBM_FILE ]; then
	echo "# $RBM_FILE .... OK"
	echo "" >> $RBM_FILE
	echo "@$DOMAIN_NAME all_in@$DOMAIN_NAME" >> $RBM_FILE
    else
	echo "# Error: $RBM_FILE not exist or write disable"
	exit 1
    fi

    if [ -w $SMB_FILE ]; then
	echo "# $SMB_FILE .... OK"
	echo "" >> $SMB_FILE
	echo "@$DOMAIN_NAME all_out@$DOMAIN_NAME" >> $SMB_FILE
    else
	echo "# Error: $SMB_FILE not exist or write disable"
	exit 1
    fi
fi

#
# Add domain to postfix DB and create aliases
#

if [ "$ADD_DB_RECORD" = "Yes" ]; then
mysql -u$DB_USER -p$DB_PASSWORD -D $DB_NAME << EOF
INSERT INTO domain (\`domain\`, \`description\`, \`aliases\`, \`mailboxes\`, \`maxquota\`, \`quota\`, \`transport\`, \`backupmx\`, \`created\`, \`modified\`, \`active\`, \`password_expiry\`)
VALUES ("$DOMAIN_NAME", "$DOMAIN_NAME", 0, 0, 10, 2048, "virtual", 0, "2022-01-01 00:00:01", "2022-01-01 00:00:01", 1, 0);
EOF
echo "Add record about $DOMAIN_NAME in table \"postfix\""
fi

if [ "$ADD_ALIASES" = "Yes" ]; then
mysql -u$DB_USER -p$DB_PASSWORD -D $DB_NAME << EOF
INSERT INTO alias (\`address\`, \`goto\`, \`domain\`, \`created\`, \`modified\`, \`active\`) VALUES
("all_in@$DOMAIN_NAME", "all_in@$DOMAIN_NAME", "$DOMAIN_NAME", "2022-01-01 00:00:01", "2022-01-01 00:00:01", 1),
("all_out@$DOMAIN_NAME", "all_out@$DOMAIN_NAME", "$DOMAIN_NAME", "2022-01-01 00:00:01", "2022-01-01 00:00:01", 1),
("@$DOMAIN_NAME", 'support@vondelmarketing.com', "$DOMAIN_NAME", "2022-01-01 00:00:01", "2022-01-01 00:00:01", 1);
INSERT INTO mailbox (\`username\`, \`password\`, \`name\`, \`maildir\`, \`quota\`, \`local_part\`, \`domain\`, \`created\`, \`modified\`, \`active\`, \`phone\`, \`email_other\`, \`token\`, \`token_validity\`, \`password_expiry\`) VALUES
("all_in@$DOMAIN_NAME", '$1$0214129b$tr7WtyB2GBLPrXxQt.EUA0', '', "$DOMAIN_NAME/all_in@$DOMAIN_NAME/", 0, 'all_in', "$DOMAIN_NAME", '2022-01-01 00:00:01', '2022-01-01 00:00:01', 1, '', '', '', '2022-01-01 00:00:01', '2050-01-01 00:00:00'),
("all_out@$DOMAIN_NAME", '$1$1c04752d$CQUc.ByMKUAr.MnIUMBGc/', '', "$DOMAIN_NAME/all_out@$DOMAIN_NAME/", 0, 'all_out', "$DOMAIN_NAME", '2022-01-01 00:00:01', '2022-01-01 00:00:01', 1, '', '', '', '2022-01-01 00:00:01', '2050-01-01 00:00:00');
EOF
echo "Add standart mail aliases and catch-all mailbox"
fi


#
# Restart postfix, dovecot and dkim services
#
postmap /etc/postfix/relay_recipients \
        /etc/postfix/transport \
        /etc/postfix/recipients \
        /etc/postfix/recipient_bcc_maps \
        /etc/postfix/tls_policy_maps \
        /etc/postfix/sender_bcc_maps \
        /etc/postfix/lists/white_client_ip \
        /etc/postfix/lists/black_client_ip \
        /etc/postfix/lists/white_client \
        /etc/postfix/lists/black_client \
        /etc/postfix/lists/white_helo \
        /etc/postfix/lists/block_dsl \
        /etc/postfix/lists/mx_access

systemctl restart opendkim.service
systemctl restart postfix
systemctl restart dovecot
echo -e "Mail services restarted.\n"

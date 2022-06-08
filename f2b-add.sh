#!/bin/bash

fail2ban-client -vvv set postfix-sasl banip $1
fail2ban-client status postfix-sasl

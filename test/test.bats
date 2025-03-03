#!/usr/bin/env bats

if [ "${PATH#*/usr/local/hestia/bin*}" = "$PATH" ]; then
    . /etc/profile.d/hestia.sh
fi

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'


function random() {
    head /dev/urandom | tr -dc 0-9 | head -c$1
}

function setup() {
    # echo "# Setup_file" > &3
    if [ $BATS_TEST_NUMBER = 1 ]; then
        echo 'user=test-5285' > /tmp/hestia-test-env.sh
        echo 'user2=test-5286' >> /tmp/hestia-test-env.sh
        echo 'userbk=testbk-5285' >> /tmp/hestia-test-env.sh
        echo 'userpass1=test-5285' >> /tmp/hestia-test-env.sh
        echo 'userpass2=t3st-p4ssw0rd' >> /tmp/hestia-test-env.sh
        echo 'HESTIA=/usr/local/hestia' >> /tmp/hestia-test-env.sh
        echo 'domain=test-5285.hestiacp.com' >> /tmp/hestia-test-env.sh
        echo 'domainuk=test-5285.hestiacp.com.uk' >> /tmp/hestia-test-env.sh
        echo 'rootdomain=testhestiacp.com' >> /tmp/hestia-test-env.sh
        echo 'subdomain=cdn.testhestiacp.com' >> /tmp/hestia-test-env.sh
        echo 'database=test-5285_database' >> /tmp/hestia-test-env.sh
        echo 'dbuser=test-5285_dbuser' >> /tmp/hestia-test-env.sh
        echo 'pguser=test5290' >> /tmp/hestia-test-env.sh
        echo 'pgdatabase=test5290_database' >> /tmp/hestia-test-env.sh
        echo 'pgdbuser=test5290_dbuser' >> /tmp/hestia-test-env.sh
    fi

    source /tmp/hestia-test-env.sh
    source $HESTIA/func/main.sh
    source $HESTIA/conf/hestia.conf
    source $HESTIA/func/ip.sh
}

function validate_web_domain() {
    local user=$1
    local domain=$2
    local webproof=$3
    local webpath=${4}

    refute [ -z "$user" ]
    refute [ -z "$domain" ]
    refute [ -z "$webproof" ]

    source $HESTIA/func/ip.sh

    run v-list-web-domain $user $domain
    assert_success

    USER_DATA=$HESTIA/data/users/$user
    local domain_ip=$(get_object_value 'web' 'DOMAIN' "$domain" '$IP')
    SSL=$(get_object_value 'web' 'DOMAIN' "$domain" '$SSL')
    domain_ip=$(get_real_ip "$domain_ip")

    if [ ! -z $webpath ]; then
        domain_docroot=$(get_object_value 'web' 'DOMAIN' "$domain" '$CUSTOM_DOCROOT')
        if [ -n "$domain_docroot" ] && [ -d "$domain_docroot" ]; then
            assert_file_exist "${domain_docroot}/${webpath}"
        else
            assert_file_exist "${HOMEDIR}/${user}/web/${domain}/public_html/${webpath}"
        fi
    fi

    # Test HTTP
    # Curl hates UTF domains so convert them to ascci. 
    domain_idn=$(idn -a $domain)
    run curl --location --silent --show-error --insecure --resolve "${domain_idn}:80:${domain_ip}" "http://${domain_idn}/${webpath}"
    assert_success
    assert_output --partial "$webproof"

    # Test HTTPS
    if [ "$SSL" = "yes" ]; then
        run v-list-web-domain-ssl $user $domain
        assert_success

        run curl --location --silent --show-error --insecure --resolve "${domain_idn}:443:${domain_ip}" "https://${domain_idn}/${webpath}"
        assert_success
        assert_output --partial "$webproof"
    fi
}

function validate_headers_domain() {
  local user=$1
  local domain=$2
  local webproof=$3
  
  refute [ -z "$user" ]
  refute [ -z "$domain" ]
  refute [ -z "$webproof" ]
  
  source $HESTIA/func/ip.sh
  
  run v-list-web-domain $user $domain
  assert_success
  
  USER_DATA=$HESTIA/data/users/$user
  local domain_ip=$(get_object_value 'web' 'DOMAIN' "$domain" '$IP')
  SSL=$(get_object_value 'web' 'DOMAIN' "$domain" '$SSL')
  domain_ip=$(get_real_ip "$domain_ip")
  
  # Test HTTP with  code redirect for some reasons due to 301 redirect it fails
  curl -i --resolve "${domain}:80:${domain_ip}" "http://${domain}"
  assert_success
  assert_output --partial "$webproof"
  
}

function validate_mail_domain() {
    local user=$1
    local domain=$2

    refute [ -z "$user" ]
    refute [ -z "$domain" ]

    run v-list-mail-domain $user $domain
    assert_success

    assert_dir_exist $HOMEDIR/$user/mail/$domain
    assert_dir_exist $HOMEDIR/$user/conf/mail/$domain

    assert_file_exist $HOMEDIR/$user/conf/mail/$domain/aliases
    assert_file_exist $HOMEDIR/$user/conf/mail/$domain/antispam
    assert_file_exist $HOMEDIR/$user/conf/mail/$domain/antivirus
    assert_file_exist $HOMEDIR/$user/conf/mail/$domain/fwd_only
    assert_file_exist $HOMEDIR/$user/conf/mail/$domain/ip
    assert_file_exist $HOMEDIR/$user/conf/mail/$domain/passwd
}

function validate_webmail_domain() {
    local user=$1
    local domain=$2
    local webproof=$3
    local webpath=${4}

    refute [ -z "$user" ]
    refute [ -z "$domain" ]
    refute [ -z "$webproof" ]

    source $HESTIA/func/ip.sh

    USER_DATA=$HESTIA/data/users/$user
    local domain_ip=$(get_object_value 'web' 'DOMAIN' "$domain" '$IP')
    SSL=$(get_object_value 'mail' 'DOMAIN' "$domain" '$SSL')
    domain_ip=$(get_real_ip "$domain_ip")

    if [ ! -z "$webpath" ]; then
        assert_file_exist /var/lib/roundcube/$webpath
    fi
    
    if [ "$SSL" = "no" ]; then 
        # Test HTTP
        run curl --location --silent --show-error --insecure  --resolve "webmail.${domain}:80:${domain_ip}" "http://webmail.${domain}/${webpath}"
        assert_success
        assert_output --partial "$webproof"
            
        # Test HTTP
        run curl  --location --silent --show-error --insecure --resolve "mail.${domain}:80:${domain_ip}" "http://mail.${domain}/${webpath}"
        assert_success
        assert_output --partial "$webproof"
    fi

    # Test HTTPS
    if [ "$SSL" = "yes" ]; then
        # Test HTTP with 301 redirect for some reasons due to 301 redirect it fails
        run curl --silent --show-error --insecure --resolve "webmail.${domain}:80:${domain_ip}" "http://webmail.${domain}/${webpath}"
        assert_success
        assert_output --partial "301 Moved Permanently"

        # Test HTTP with 301 redirect for some reasons due to 301 redirect it fails
        run curl --silent --show-error --insecure --resolve "mail.${domain}:80:${domain_ip}" "http://mail.${domain}/${webpath}"
        assert_success
        assert_output --partial "301 Moved Permanently"
                
        run v-list-mail-domain-ssl $user $domain
        assert_success
    
        run curl --location --silent --show-error --insecure --resolve "webmail.${domain}:443:${domain_ip}" "https://webmail.${domain}/${webpath}"
        assert_success
        assert_output --partial "$webproof"
    
        run curl --location --silent --show-error --insecure --resolve "mail.${domain}:443:${domain_ip}" "https://mail.${domain}/${webpath}"
        assert_success
        assert_output --partial "$webproof"
    fi
}

function validate_database(){
    local type=$1
    local database=$2
    local dbuser=$3
    local password=$4
    
    host_str=$(grep "HOST='localhost'" $HESTIA/conf/$type.conf)
    parse_object_kv_list "$host_str"
    if [ -z $PORT ]; then PORT=3306; fi
    
    refute [ -z "$HOST" ]
    refute [ -z "$PORT" ]
    refute [ -z "$database" ]
    refute [ -z "$dbuser" ]
    refute [ -z "$password" ]
    
    
    if [ "$type" = "mysql" ]; then 
      # Create an connection to verify correct username / password has been set correctly
      tmpfile=$(mktemp /tmp/mysql.XXXXXX)
      echo "[client]">$tmpfile
      echo "host='$HOST'" >> $tmpfile
      echo "user='$dbuser'" >> $tmpfile
      echo "password='$password'" >> $tmpfile
      echo "port='$PORT'" >> $tmpfile
      chmod 600 $tmpfile
      
      sql_tmp=$(mktemp /tmp/query.XXXXXX)
      echo "show databases;" > $sql_tmp
      run mysql --defaults-file=$tmpfile < "$sql_tmp"
      
      assert_success
      assert_output --partial "$database"
      
      rm -f "$sql_tmp"
      rm -f "$tmpfile"
    else
      
      echo "*:*:*:$dbuser:$password" > /root/.pgpass
      chmod 600 /root/.pgpass
      run export PGPASSWORD="$password" | psql -h $HOST -U "$dbuser" -p $PORT -d "$database" --no-password  -c "\l"
      assert_success
      rm /root/.pgpass
    fi
}

function check_ip_banned(){
  local ip=$1
  local chain=$2
  
  run grep "IP='$ip' CHAIN='$chain'" $HESTIA/data/firewall/banlist.conf
  assert_success
  assert_output --partial "$ip"
}

function check_ip_not_banned(){
  local ip=$1
  local chain=$2
  run grep "IP='$ip' CHAIN='$chain'" $HESTIA/data/firewall/banlist.conf
  assert_failure E_ARGS
  refute_output
}


#----------------------------------------------------------#
#                           IP                             #
#----------------------------------------------------------#

@test "Check reverse Dns validation" {
    # 1. PTR record for a IP should return a hostname(reverse) which in turn must resolve to the same IP addr(forward). (Full circle)
    #  `-> not implemented in `is_ip_rdns_valid` yet and also not tested here
    # 2. Reject rPTR records that match generic dynamic IP pool patterns

    local ip="54.200.1.22"
    local rdns="ec2-54-200-1-22.us-west-2.compute.amazonaws.com"
    run is_ip_rdns_valid "$ip"
    assert_failure
    refute_output

    local rdns="ec2.54.200.1.22.us-west-2.compute.amazonaws.com"
    run is_ip_rdns_valid "$ip"
    assert_failure
    refute_output

    local rdns="ec2-22-1-200-54.us-west-2.compute.amazonaws.com"
    run is_ip_rdns_valid "$ip"
    assert_failure
    refute_output

    local rdns="ec2.22.1.200.54.us-west-2.compute.amazonaws.com"
    run is_ip_rdns_valid "$ip"
    assert_failure
    refute_output

    local rdns="ec2-200-54-1-22.us-west-2.compute.amazonaws.com"
    run is_ip_rdns_valid "$ip"
    assert_failure
    refute_output

    local rdns="panel-22.mydomain.tld"
    run is_ip_rdns_valid "$ip"
    assert_success
    assert_output "$rdns"

    local rdns="mail.mydomain.tld"
    run is_ip_rdns_valid "$ip"
    assert_success
    assert_output "$rdns"

    local rdns="mydomain.tld"
    run is_ip_rdns_valid "$ip"
    assert_success
    assert_output "$rdns"

}

#----------------------------------------------------------#
#                         User                             #
#----------------------------------------------------------#

@test "Add new user" {
    run v-add-user $user $user $user@hestiacp.com default "Super Test"
    assert_success
    refute_output
}

@test "Change user password" {
    run v-change-user-password "$user" t3st-p4ssw0rd
    assert_success
    refute_output
}

@test "Change user email" {
    run v-change-user-contact "$user" tester@hestiacp.com
    assert_success
    refute_output
}

@test "Change user contact invalid email " {
    run v-change-user-contact "$user" testerhestiacp.com
    assert_failure $E_INVALID
    assert_output --partial 'Error: invalid email format'
}

@test "Change user name" {
    run v-change-user-name "$user" "New name"
    assert_success
    refute_output
}

@test "Change user shell" {
    run v-change-user-shell $user bash
    assert_success
    refute_output
}

@test "Change user invalid shell" {
    run v-change-user-shell $user bashinvalid
    assert_failure $E_INVALID
    assert_output --partial 'shell bashinvalid is not valid'
}

@test "Change user default ns" {
    run v-change-user-ns $user ns0.com ns1.com ns2.com ns3.com
    assert_success
    refute_output

    run v-list-user-ns "$user" plain
    assert_success
    assert_output --partial 'ns0.com'
}

#----------------------------------------------------------#
#                         Cron                             #
#----------------------------------------------------------#

@test "Cron: Add cron job" {
    run v-add-cron-job $user 1 1 1 1 1 echo
    assert_success
    refute_output
}

@test "Cron: Suspend cron job" {
    run v-suspend-cron-job $user 1
    assert_success
    refute_output
}

@test "Cron: Unsuspend cron job" {
    run v-unsuspend-cron-job $user 1
    assert_success
    refute_output
}

@test "Cron: Delete cron job" {
    run v-delete-cron-job $user 1
    assert_success
    refute_output
}

@test "Cron: Add cron job (duplicate)" {
    run v-add-cron-job $user 1 1 1 1 1 echo 1
    assert_success
    refute_output

    run v-add-cron-job $user 1 1 1 1 1 echo 1
    assert_failure $E_EXISTS
    assert_output --partial 'JOB=1 already exists'
}

@test "Cron: Second cron job" {
    run v-add-cron-job $user 2 2 2 2 2 echo 2
    assert_success
    refute_output
}

@test "Cron: Two cron jobs must be listed" {
    run v-list-cron-jobs $user csv
    assert_success
    assert_line --partial '1,1,1,1,1,"echo",no'
    assert_line --partial '2,2,2,2,2,"echo",no'
}

@test "Cron: rebuild" {
    run v-rebuild-cron-jobs $user
    assert_success
    refute_output
}

#----------------------------------------------------------#
#                          IP                              #
#----------------------------------------------------------#

@test "Ip: Add new ip on first interface" {
    interface=$(v-list-sys-interfaces plain | head -n 1)
    run ip link show dev $interface
    assert_success

    local a2_rpaf="/etc/$WEB_SYSTEM/mods-enabled/rpaf.conf"
    local a2_remoteip="/etc/$WEB_SYSTEM/mods-enabled/remoteip.conf"

    # Save initial state
    echo "interface=${interface}" >> /tmp/hestia-test-env.sh
    [ -f "$a2_rpaf" ]     && file_hash1=$(cat $a2_rpaf     |md5sum |cut -d" " -f1) && echo "a2_rpaf_hash='${file_hash1}'"     >> /tmp/hestia-test-env.sh
    [ -f "$a2_remoteip" ] && file_hash2=$(cat $a2_remoteip |md5sum |cut -d" " -f1) && echo "a2_remoteip_hash='${file_hash2}'" >> /tmp/hestia-test-env.sh


    local ip="198.18.0.12"
    run v-add-sys-ip $ip 255.255.255.255 $interface $user
    assert_success
    refute_output

    assert_file_exist /etc/$WEB_SYSTEM/conf.d/$ip.conf
    assert_file_exist $HESTIA/data/ips/$ip
    assert_file_contains $HESTIA/data/ips/$ip "OWNER='$user'"
    assert_file_contains $HESTIA/data/ips/$ip "INTERFACE='$interface'"

    if [ -n "$PROXY_SYSTEM" ]; then
        assert_file_exist /etc/$PROXY_SYSTEM/conf.d/$ip.conf
        [ -f "$a2_rpaf" ] && assert_file_contains "$a2_rpaf" "RPAFproxy_ips.*$ip\b"
        [ -f "$a2_remoteip" ] && assert_file_contains "$a2_remoteip" "RemoteIPInternalProxy $ip\$"
    fi

}

@test "Ip: Add ip (duplicate)" {
    run v-add-sys-ip 198.18.0.12 255.255.255.255 $interface $user
    assert_failure $E_EXISTS
}

@test "Ip: Add extra ip" {
    local ip="198.18.0.121"
    run v-add-sys-ip $ip 255.255.255.255 $interface $user
    assert_success
    refute_output

    assert_file_exist /etc/$WEB_SYSTEM/conf.d/$ip.conf
    assert_file_exist $HESTIA/data/ips/$ip
    assert_file_contains $HESTIA/data/ips/$ip "OWNER='$user'"
    assert_file_contains $HESTIA/data/ips/$ip "INTERFACE='$interface'"

    if [ -n "$PROXY_SYSTEM" ]; then
        assert_file_exist /etc/$PROXY_SYSTEM/conf.d/$ip.conf
        local a2_rpaf="/etc/$WEB_SYSTEM/mods-enabled/rpaf.conf"
        [ -f "$a2_rpaf" ] && assert_file_contains "$a2_rpaf" "RPAFproxy_ips.*$ip\b"

        local a2_remoteip="/etc/$WEB_SYSTEM/mods-enabled/remoteip.conf"
        [ -f "$a2_remoteip" ] && assert_file_contains "$a2_remoteip" "RemoteIPInternalProxy $ip\$"
    fi
}

@test "Ip: Change Helo" {
    local ip="198.18.0.121"
    run v-change-sys-ip-helo 198.18.0.121 dev.hestiacp.com
    assert_success
    refute_output
    assert_file_contains /etc/exim4/mailhelo.conf "198.18.0.121:dev.hestiacp.com"
}

@test "Ip: Delete ips" {
    local ip="198.18.0.12"
    run v-delete-sys-ip $ip
    assert_success
    refute_output

    assert_file_not_exist /etc/$WEB_SYSTEM/conf.d/$ip.conf
    assert_file_not_exist $HESTIA/data/ips/$ip


    ip="198.18.0.121"
    run v-delete-sys-ip $ip
    assert_success
    refute_output

    assert_file_not_exist /etc/$WEB_SYSTEM/conf.d/$ip.conf
    assert_file_not_exist $HESTIA/data/ips/$ip

    if [ -n "$PROXY_SYSTEM" ]; then
        assert_file_not_exist /etc/$PROXY_SYSTEM/conf.d/$ip.conf
    fi

    # remoteip and rpaf config hashes must match the initial one
    if [ ! -z "$a2_rpaf_hash" ]; then
        local a2_rpaf="/etc/$WEB_SYSTEM/mods-enabled/rpaf.conf"
        file_hash=$(cat $a2_rpaf |md5sum |cut -d" " -f1)
        assert_equal "$file_hash" "$a2_rpaf_hash"
    fi
    if [ ! -z "$a2_remoteip_hash" ]; then
        local a2_remoteip="/etc/$WEB_SYSTEM/mods-enabled/remoteip.conf"
        file_hash=$(cat $a2_remoteip |md5sum |cut -d" " -f1)
        assert_equal "$file_hash" "$a2_remoteip_hash"
    fi
}

@test "Ip: Add IP for rest of the test" {
    local ip="198.18.0.125"
    run v-add-sys-ip $ip 255.255.255.255 $interface $user
    assert_success
    refute_output

    assert_file_exist /etc/$WEB_SYSTEM/conf.d/$ip.conf
    assert_file_exist $HESTIA/data/ips/$ip
    assert_file_contains $HESTIA/data/ips/$ip "OWNER='$user'"
    assert_file_contains $HESTIA/data/ips/$ip "INTERFACE='$interface'"

    if [ -n "$PROXY_SYSTEM" ]; then
        assert_file_exist /etc/$PROXY_SYSTEM/conf.d/$ip.conf
        local a2_rpaf="/etc/$WEB_SYSTEM/mods-enabled/rpaf.conf"
        [ -f "$a2_rpaf" ] && assert_file_contains "$a2_rpaf" "RPAFproxy_ips.*$ip\b"

        local a2_remoteip="/etc/$WEB_SYSTEM/mods-enabled/remoteip.conf"
        [ -f "$a2_remoteip" ] && assert_file_contains "$a2_remoteip" "RemoteIPInternalProxy $ip\$"
    fi
}

#----------------------------------------------------------#
#                         WEB                              #
#----------------------------------------------------------#

@test "WEB: Add web domain" {
    run v-add-web-domain $user $domain 198.18.0.125
    assert_success
    refute_output

    echo -e "<?php\necho 'Hestia Test:'.(4*3);" > $HOMEDIR/$user/web/$domain/public_html/php-test.php
    validate_web_domain $user $domain 'Hestia Test:12' 'php-test.php'
    rm $HOMEDIR/$user/web/$domain/public_html/php-test.php
}

@test "WEB: Add web domain (duplicate)" {
    run v-add-web-domain $user $domain 198.18.0.125
    assert_failure $E_EXISTS
}

@test "WEB: Add web domain alias" {
    run v-add-web-domain-alias $user $domain v3.$domain
    assert_success
    refute_output
}

@test "WEB: Add web domain alias (duplicate)" {
    run v-add-web-domain-alias $user $domain v3.$domain
    assert_failure $E_EXISTS
}

@test "WEB: Add web domain wildcard alias" {
    run v-add-web-domain-alias $user $domain "*.$domain"
    assert_success
    refute_output
}

@test "WEB: Delete web domain wildcard alias" {
    run v-delete-web-domain-alias $user $domain "*.$domain"
    assert_success
    refute_output
}

@test "WEB: Add web domain stats" {
    run v-add-web-domain-stats $user $domain awstats
    assert_success
    refute_output
}

@test "WEB: Add web domain stats user" {
    skip
    run v-add-web-domain-stats-user $user $domain test m3g4p4ssw0rd
    assert_success
    refute_output
}

@test "WEB: Suspend web domain" {
    run v-suspend-web-domain $user $domain
    assert_success
    refute_output

    validate_web_domain $user $domain 'This site is currently suspended'
}

@test "WEB: Unsuspend web domain" {
    run v-unsuspend-web-domain $user $domain
    assert_success
    refute_output

    echo -e "<?php\necho 'Hestia Test:'.(4*3);" > $HOMEDIR/$user/web/$domain/public_html/php-test.php
    validate_web_domain $user $domain 'Hestia Test:12' 'php-test.php'
    rm $HOMEDIR/$user/web/$domain/public_html/php-test.php
}

@test "WEB: Add redirect to www.domain.com" {
    run v-add-web-domain-redirect $user $domain www.$domain 301
    assert_success
    refute_output 
  
    run validate_headers_domain $user $domain "301"
}

@test "WEB: Delete redirect to www.domain.com" {
    run v-delete-web-domain-redirect $user $domain
    assert_success
    refute_output 
}

@test "WEB: Enable Fast CGI Cache" {
    if [ "$WEB_SYSTEM" != "nginx" ]; then 
      skip "FastCGI cache is not supported"
    fi
    
    run v-add-fastcgi-cache $user $domain '1m' yes
    assert_success
    refute_output
    
    echo -e "<?php\necho 'Hestia Test:'.(4*3);" > $HOMEDIR/$user/web/$domain/public_html/php-test.php
    run validate_headers_domain $user $domain "Miss"
    run validate_headers_domain $user $domain "Hit"
    rm $HOMEDIR/$user/web/$domain/public_html/php-test.php
}

@test "WEB: Disable Fast CGI Cache" {
    if [ "$WEB_SYSTEM" != "nginx" ]; then 
      skip "FastCGI cache is not supported"
    fi
    run v-delete-fastcgi-cache $user $domain '1m' yes
    assert_success
    refute_output
}


@test "WEB: Generate Self signed certificate" {
    ssl=$(v-generate-ssl-cert "$domain" "info@$domain" US CA "Orange County" HestiaCP IT "mail.$domain" | tail -n1 | awk '{print $2}')
    mv $ssl/$domain.crt /tmp/$domain.crt
    mv $ssl/$domain.key /tmp/$domain.key
}

@test "WEB: Add ssl" {
    # Use self signed certificates during last test
    run v-add-web-domain-ssl $user $domain /tmp
    assert_success
    refute_output
}

@test "WEB: Rebuild web domain" {
    run v-rebuild-web-domains $user
    assert_success
    refute_output
}

#----------------------------------------------------------#
#                         IDN                              #
#----------------------------------------------------------#

@test "WEB: Add IDN domain UTF idn-tést.eu" {
   run v-add-web-domain $user idn-tést.eu 198.18.0.125
   assert_success
   refute_output
   
   echo -e "<?php\necho 'Hestia Test:'.(4*3);" > $HOMEDIR/$user/web/idn-tést.eu/public_html/php-test.php
   validate_web_domain $user idn-tést.eu 'Hestia Test:12' 'php-test.php'
   rm $HOMEDIR/$user/web/idn-tést.eu/public_html/php-test.php
}

@test "WEB: Add IDN domain ASCII idn-tést.eu" {
 # Expected to fail due to utf exists
 run v-add-web-domain $user $( idn -a idn-tést.eu) 198.18.0.125
 assert_failure $E_EXISTS

}

@test "WEB: Delete IDN domain idn-tést.eu" {
 run v-delete-web-domain $user idn-tést.eu
 assert_success
 refute_output
}
 
@test "WEB: Add IDN domain UTF bløst.com" {
 run v-add-web-domain $user bløst.com 198.18.0.125
 assert_success
 refute_output
}

@test "WEB: Delete IDN domain bløst.com" {
 run v-delete-web-domain $user bløst.com
 assert_success
 refute_output
}

#----------------------------------------------------------#
#                      MULTIPHP                            #
#----------------------------------------------------------#

@test "Multiphp: Default php Backend version" {
    def_phpver=$(multiphp_default_version)
    multi_domain="multiphp.${domain}"

    run v-add-web-domain $user $multi_domain 198.18.0.125
    assert_success
    refute_output

    echo -e "<?php\necho PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" > "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
    validate_web_domain $user $multi_domain "$def_phpver" 'php-test.php'
    rm "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"

}

@test "Multiphp: Change backend version - PHP v5.6" {
    test_phpver='5.6'
    multi_domain="multiphp.${domain}"

    if [ ! -d "/etc/php/${test_phpver}/fpm/pool.d/" ]; then
        skip "PHP ${test_phpver} not installed"
    fi

    run v-change-web-domain-backend-tpl $user $multi_domain 'PHP-5_6' 'yes'
    assert_success
    refute_output

    # Changing web backend will create a php-fpm pool config in the corresponding php folder
    assert_file_exist "/etc/php/${test_phpver}/fpm/pool.d/${multi_domain}.conf"

    # A single php-fpm pool config file must be present
    num_fpm_config_files="$(find -L /etc/php/ -name "${multi_domain}.conf" | wc -l)"
    assert_equal "$num_fpm_config_files" '1'

    echo -e "<?php\necho 'hestia-multiphptest:'.PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" > "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
    validate_web_domain $user $multi_domain "hestia-multiphptest:$test_phpver" 'php-test.php'
    rm "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
}

@test "Multiphp: Change backend version - PHP v7.0" {
    test_phpver='7.0'
    multi_domain="multiphp.${domain}"

    if [ ! -d "/etc/php/${test_phpver}/fpm/pool.d/" ]; then
        skip "PHP ${test_phpver} not installed"
    fi

    run v-change-web-domain-backend-tpl $user $multi_domain 'PHP-7_0' 'yes'
    assert_success
    refute_output

    # Changing web backend will create a php-fpm pool config in the corresponding php folder
    assert_file_exist "/etc/php/${test_phpver}/fpm/pool.d/${multi_domain}.conf"

    # A single php-fpm pool config file must be present
    num_fpm_config_files="$(find -L /etc/php/ -name "${multi_domain}.conf" | wc -l)"
    assert_equal "$num_fpm_config_files" '1'

    echo -e "<?php\necho 'hestia-multiphptest:'.PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" > "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
    validate_web_domain $user $multi_domain "hestia-multiphptest:$test_phpver" 'php-test.php'
    rm "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
}

@test "Multiphp: Change backend version - PHP v7.1" {
    test_phpver='7.1'
    multi_domain="multiphp.${domain}"

    if [ ! -d "/etc/php/${test_phpver}/fpm/pool.d/" ]; then
        skip "PHP ${test_phpver} not installed"
    fi

    run v-change-web-domain-backend-tpl $user $multi_domain 'PHP-7_1' 'yes'
    assert_success
    refute_output

    # Changing web backend will create a php-fpm pool config in the corresponding php folder
    assert_file_exist "/etc/php/${test_phpver}/fpm/pool.d/${multi_domain}.conf"

    # A single php-fpm pool config file must be present
    num_fpm_config_files="$(find -L /etc/php/ -name "${multi_domain}.conf" | wc -l)"
    assert_equal "$num_fpm_config_files" '1'

    echo -e "<?php\necho 'hestia-multiphptest:'.PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" > "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
    validate_web_domain $user $multi_domain "hestia-multiphptest:$test_phpver" 'php-test.php'
    rm "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
}

@test "Multiphp: Change backend version - PHP v7.2" {
    test_phpver='7.2'
    multi_domain="multiphp.${domain}"

    if [ ! -d "/etc/php/${test_phpver}/fpm/pool.d/" ]; then
        skip "PHP ${test_phpver} not installed"
    fi

    run v-change-web-domain-backend-tpl $user $multi_domain 'PHP-7_2' 'yes'
    assert_success
    refute_output

    # Changing web backend will create a php-fpm pool config in the corresponding php folder
    assert_file_exist "/etc/php/${test_phpver}/fpm/pool.d/${multi_domain}.conf"

    # A single php-fpm pool config file must be present
    num_fpm_config_files="$(find -L /etc/php/ -name "${multi_domain}.conf" | wc -l)"
    assert_equal "$num_fpm_config_files" '1'

    echo -e "<?php\necho 'hestia-multiphptest:'.PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" > "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
    validate_web_domain $user $multi_domain "hestia-multiphptest:$test_phpver" 'php-test.php'
    rm "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
}

@test "Multiphp: Change backend version - PHP v7.3" {
    test_phpver='7.3'
    multi_domain="multiphp.${domain}"

    if [ ! -d "/etc/php/${test_phpver}/fpm/pool.d/" ]; then
        skip "PHP ${test_phpver} not installed"
    fi

    run v-change-web-domain-backend-tpl $user $multi_domain 'PHP-7_3' 'yes'
    assert_success
    refute_output

    # Changing web backend will create a php-fpm pool config in the corresponding php folder
    assert_file_exist "/etc/php/${test_phpver}/fpm/pool.d/${multi_domain}.conf"

    # A single php-fpm pool config file must be present
    num_fpm_config_files="$(find -L /etc/php/ -name "${multi_domain}.conf" | wc -l)"
    assert_equal "$num_fpm_config_files" '1'

    echo -e "<?php\necho 'hestia-multiphptest:'.PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" > "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
    validate_web_domain $user $multi_domain "hestia-multiphptest:$test_phpver" 'php-test.php'
    rm "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
}

@test "Multiphp: Change backend version - PHP v7.4" {
    test_phpver='7.4'
    multi_domain="multiphp.${domain}"

    if [ ! -d "/etc/php/${test_phpver}/fpm/pool.d/" ]; then
        skip "PHP ${test_phpver} not installed"
    fi

    run v-change-web-domain-backend-tpl $user $multi_domain 'PHP-7_4' 'yes'
    assert_success
    refute_output

    # Changing web backend will create a php-fpm pool config in the corresponding php folder
    assert_file_exist "/etc/php/${test_phpver}/fpm/pool.d/${multi_domain}.conf"

    # A single php-fpm pool config file must be present
    num_fpm_config_files="$(find -L /etc/php/ -name "${multi_domain}.conf" | wc -l)"
    assert_equal "$num_fpm_config_files" '1'

    echo -e "<?php\necho 'hestia-multiphptest:'.PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" > "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
    validate_web_domain $user $multi_domain "hestia-multiphptest:$test_phpver" 'php-test.php'
    rm "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
}

@test "Multiphp: Change backend version - PHP v8.0" {
    test_phpver='8.0'
    multi_domain="multiphp.${domain}"

    if [ ! -d "/etc/php/${test_phpver}/fpm/pool.d/" ]; then
        skip "PHP ${test_phpver} not installed"
    fi

    run v-change-web-domain-backend-tpl $user $multi_domain 'PHP-8_0' 'yes'
    assert_success
    refute_output

    # Changing web backend will create a php-fpm pool config in the corresponding php folder
    assert_file_exist "/etc/php/${test_phpver}/fpm/pool.d/${multi_domain}.conf"

    # A single php-fpm pool config file must be present
    num_fpm_config_files="$(find -L /etc/php/ -name "${multi_domain}.conf" | wc -l)"
    assert_equal "$num_fpm_config_files" '1'

    echo -e "<?php\necho 'hestia-multiphptest:'.PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" > "$HOMEDIR/$user/web/$multi_domain/public_html/php-test.php"
    validate_web_domain $user $multi_domain "hestia-multiphptest:$test_phpver" 'php-test.php'
    rm $HOMEDIR/$user/web/$multi_domain/public_html/php-test.php
}

@test "Multiphp: Cleanup" {
    multi_domain="multiphp.${domain}"

    run v-delete-web-domain $user $multi_domain 'yes'
    assert_success
    refute_output

    # No php-fpm pool config file must be present
    num_fpm_config_files="$(find -L /etc/php/ -name "${multi_domain}.conf" | wc -l)"
    assert_equal "$num_fpm_config_files" '0'
}


#----------------------------------------------------------#
#                     CUSTOM DOCROOT                       #
#----------------------------------------------------------#

@test "Docroot: Self Subfolder" {
    docroot1_domain="docroot1.${domain}"

    run v-add-web-domain $user $docroot1_domain 198.18.0.125
    assert_success
    refute_output

    run v-add-fs-directory $user "$HOMEDIR/$user/web/$docroot1_domain/public_html/public/"
    assert_success
    refute_output

    run v-change-web-domain-docroot $user "$docroot1_domain" "$docroot1_domain" "/public"
    assert_success
    refute_output

    echo -e '<?php\necho "self-sub-".$_SERVER["HTTP_HOST"];' > "$HOMEDIR/$user/web/$docroot1_domain/public_html/public/php-test.php"
    validate_web_domain $user $docroot1_domain "self-sub-${docroot1_domain}" 'php-test.php'
    rm "$HOMEDIR/$user/web/$docroot1_domain/public_html/public/php-test.php"
}

@test "Docroot: Other domain subfolder" {
    docroot1_domain="docroot1.${domain}"
    docroot2_domain="docroot2.${domain}"

    run v-add-web-domain $user $docroot2_domain 198.18.0.125
    assert_success
    refute_output

    run v-add-fs-directory $user "$HOMEDIR/$user/web/$docroot2_domain/public_html/public/"
    assert_success
    refute_output

    run v-change-web-domain-docroot $user "$docroot1_domain" "$docroot2_domain" "/public"
    assert_success
    refute_output

    echo -e '<?php\necho "doc2-sub-".$_SERVER["HTTP_HOST"];' > "$HOMEDIR/$user/web/$docroot2_domain/public_html/public/php-test.php"
    validate_web_domain $user $docroot1_domain "doc2-sub-${docroot1_domain}" 'php-test.php'
    rm "$HOMEDIR/$user/web/$docroot2_domain/public_html/public/php-test.php"
}

@test "Docroot: Other domain root folder" {
    docroot1_domain="docroot1.${domain}"
    docroot2_domain="docroot2.${domain}"

    run v-change-web-domain-docroot $user "$docroot1_domain" "$docroot2_domain"
    assert_success
    refute_output

    echo -e '<?php\necho "doc2-root-".$_SERVER["HTTP_HOST"];' > "$HOMEDIR/$user/web/$docroot2_domain/public_html/php-test.php"
    validate_web_domain $user $docroot1_domain "doc2-root-${docroot1_domain}" 'php-test.php'
    rm "$HOMEDIR/$user/web/$docroot2_domain/public_html/php-test.php"
}

@test "Docroot: Reset" {
    docroot1_domain="docroot1.${domain}"

    run v-change-web-domain-docroot $user "$docroot1_domain" "default"
    assert_success
    refute_output

    echo -e '<?php\necho "doc1-root-".$_SERVER["HTTP_HOST"];' > "$HOMEDIR/$user/web/$docroot1_domain/public_html/php-test.php"
    validate_web_domain $user $docroot1_domain "doc1-root-${docroot1_domain}" 'php-test.php'
    rm "$HOMEDIR/$user/web/$docroot1_domain/public_html/php-test.php"
}

@test "Docroot: Cleanup" {
    docroot1_domain="docroot1.${domain}"
    docroot2_domain="docroot2.${domain}"

    run v-delete-web-domain $user $docroot1_domain
    assert_success
    refute_output

    run v-delete-web-domain $user $docroot2_domain
    assert_success
    refute_output
}

#----------------------------------------------------------#
#                         DNS                              #
#----------------------------------------------------------#

@test "DNS: Add domain" {
    run v-add-dns-domain $user $domain 198.18.0.125
    assert_success
    refute_output
}

@test "DNS: Add domain (duplicate)" {
    run v-add-dns-domain $user $domain 198.18.0.125
    assert_failure $E_EXISTS
}

@test "DNS: Add domain record" {
    run v-add-dns-record $user $domain test A 198.18.0.125 20
    assert_success
    refute_output
}

@test "DNS: Delete domain record" {
    run v-delete-dns-record $user $domain 20
    assert_success
    refute_output
}

@test "DNS: Delete missing domain record" {
    run v-delete-dns-record $user $domain 20
    assert_failure $E_NOTEXIST
}

@test "DNS: Change domain expire date" {
    run v-change-dns-domain-exp $user $domain 2020-01-01
    assert_success
    refute_output
}

@test "DNS: Change domain ip" {
    run v-change-dns-domain-ip $user $domain 127.0.0.1
    assert_success
    refute_output
}

@test "DNS: Suspend domain" {
    run v-suspend-dns-domain $user $domain
    assert_success
    refute_output
}

@test "DNS: Unsuspend domain" {
    run v-unsuspend-dns-domain $user $domain
    assert_success
    refute_output
}

@test "DNS: Rebuild" {
    run v-rebuild-dns-domains $user
    assert_success
    refute_output
}

#----------------------------------------------------------#
#                         MAIL                             #
#----------------------------------------------------------#

@test "MAIL: Add domain" {
    run v-add-mail-domain $user $domain
    assert_success
    refute_output
    
    validate_mail_domain $user $domain
}

@test "MAIL: Add mail domain webmail client (Roundcube)" {
    run v-add-mail-domain-webmail $user $domain "roundcube" "yes"
    assert_success
    refute_output

    # echo -e "<?php\necho 'Server: ' . \$_SERVER['SERVER_SOFTWARE'];" > /var/lib/roundcube/check_server.php
    validate_webmail_domain $user $domain 'Welcome to Roundcube Webmail'
    # rm /var/lib/roundcube/check_server.php
}

@test "Mail: Add SSL to mail domain" {
    # Use generated certificates during WEB Generate Self signed certificate  
    run v-add-mail-domain-ssl $user $domain /tmp
    assert_success
    refute_output
    
    validate_webmail_domain $user $domain 'Welcome to Roundcube Webmail'
}

@test "MAIL: Add mail domain webmail client (Rainloop)" {
    if [ -z "$(echo $WEBMAIL_SYSTEM | grep -w "rainloop")" ]; then 
        skip "Webmail client Rainloop not installed"
    fi
    run v-add-mail-domain-webmail $user $domain "rainloop" "yes"
    assert_success
    refute_output
    validate_mail_domain $user $domain
    
    validate_webmail_domain $user $domain 'RainLoop Webmail'
}    

@test "MAIL: Disable webmail client" {
    run v-add-mail-domain-webmail $user $domain "disabled" "yes"
    assert_success
    refute_output
    validate_mail_domain $user $domain
    
    validate_webmail_domain $user $domain 'Success!'
} 

@test "MAIL: Add domain (duplicate)" {
    run v-add-mail-domain $user $domain
    assert_failure $E_EXISTS
}

@test "MAIL: Add account" {
    run v-add-mail-account $user $domain test t3st-p4ssw0rd
    assert_success
    refute_output
}

@test "MAIL: Add account (duplicate)" {
    run v-add-mail-account $user $domain test t3st-p4ssw0rd
    assert_failure $E_EXISTS
}

@test "MAIL: Delete account" {
    run v-delete-mail-account $user $domain test
    assert_success
    refute_output
}

@test "MAIL: Delete missing account" {
    run v-delete-mail-account $user $domain test
    assert_failure $E_NOTEXIST
}

@test "MAIL: Rebuild mail domain" {
    run v-rebuild-mail-domains $user
    assert_success
    refute_output
}

#----------------------------------------------------------#
#    Limit possibilities adding different owner domain     #
#----------------------------------------------------------#

@test "Allow Users: User can't add user.user2.com " {
    # Case: admin company.ltd
    # users should not be allowed to add user.company.ltd
    run v-add-user $user2 $user2 $user@hestiacp.com default "Super Test"
    assert_success
    refute_output
    
    run v-add-web-domain $user2 $rootdomain 
    assert_success
    refute_output
    
    run v-add-web-domain $user $subdomain
    assert_failure $E_EXISTS
}

@test "Allow Users: User can't add user.user2.com as alias" {
    run v-add-web-domain-alias $user $domain $subdomain
    assert_failure $E_EXISTS
}

@test "Allow Users: User can't add user.user2.com as mail domain" {
    run v-add-mail-domain $user $subdomain
    assert_failure $E_EXISTS
}

@test "Allow Users: User can't add user.user2.com as dns domain" {
    run v-add-dns-domain $user $subdomain 198.18.0.125
    assert_failure $E_EXISTS
}

@test "Allow Users: Set Allow users" {
    # Allow user to yes allows
    # Case: admin company.ltd
    # users are allowed to add user.company.ltd
    run v-add-web-domain-allow-users $user2 $rootdomain
    assert_success
    refute_output
}

@test "Allow Users: User can add user.user2.com" {
    run v-add-web-domain $user $subdomain
    assert_success
    refute_output
}

@test "Allow Users: User can add user.user2.com as alias" {
    run v-delete-web-domain $user $subdomain
    assert_success
    refute_output
    
    run v-add-web-domain-alias $user $domain $subdomain
    assert_success
    refute_output
}

@test "Allow Users: User can add user.user2.com as mail domain" {
    run v-add-mail-domain $user $subdomain
    assert_success
    refute_output
}

@test "Allow Users: User can add user.user2.com as dns domain" {
    run v-add-dns-domain $user $subdomain 198.18.0.125
    assert_success
    refute_output
}

@test "Allow Users: Cleanup tests" {
    run v-delete-dns-domain $user $subdomain
    assert_success
    refute_output

    run v-delete-mail-domain $user $subdomain
    assert_success
    refute_output
}


@test "Allow Users: Set Allow users no" {
    run v-delete-web-domain-alias $user $domain $subdomain 
    assert_success
    refute_output
    
    run v-delete-web-domain-allow-users $user2 $rootdomain
    assert_success
    refute_output
}

@test "Allow Users: User can't add user.user2.com again" {
    run v-add-web-domain $user $subdomain
    assert_failure $E_EXISTS
}

@test "Allow Users: user2 can add user.user2.com again" {
    run v-add-web-domain $user2 $subdomain
    assert_success
    refute_output

    run v-delete-user $user2
    assert_success
    refute_output
}

#----------------------------------------------------------#
#                         DB                               #
#----------------------------------------------------------#

@test "MYSQL: Add database" {
    run v-add-database $user database dbuser 1234 mysql
    assert_success
    refute_output
    # validate_database mysql database_name database_user password
    validate_database mysql $database $dbuser 1234
}
@test "MYSQL: Add Database (Duplicate)" {
    run v-add-database $user database dbuser 1234 mysql
    assert_failure $E_EXISTS
}

@test "MYSQL: Rebuild Database" {
    run v-rebuild-database $user $database
    assert_success
    refute_output 
}

@test "MYSQL: Change database user password" {
    run v-change-database-password $user $database 123456
    assert_success
    refute_output 
    
    validate_database mysql $database $dbuser 123456
}

@test "MYSQL: Change database user" {
    run v-change-database-user $user $database database
    assert_success
    refute_output 
    validate_database mysql $database $database 123456
}

@test "MYSQL: Suspend database" {
    run v-suspend-database $user $database
    assert_success
    refute_output
}

@test "MYSQL: Unsuspend database" {
    run v-unsuspend-database $user $database
    assert_success
    refute_output
}

@test "MYSQL: Delete database" {
    run v-delete-database $user $database
    assert_success
    refute_output 
}

@test "MYSQL: Delete missing database" {
    run v-delete-database $user $database
    assert_failure $E_NOTEXIST
}

@test "PGSQL: Add database invalid user" {
  if [ -z "$(echo $DB_SYSTEM | grep -w "pgsql")" ]; then 
    skip "PostGreSQL is not installed"
  fi
  run v-add-database "$user" "database" "dbuser" "1234ABCD" "pgsql"
  assert_failure $E_INVALID
}

@test "PGSQL: Add database" {
  if [ -z "$(echo $DB_SYSTEM | grep -w "pgsql")" ]; then 
    skip "PostGreSQL is not installed"
  fi
  run v-add-user $pguser $pguser $user@hestiacp.com default "Super Test"
  run v-add-database "$pguser" "database" "dbuser" "1234ABCD" "pgsql"
  assert_success
  refute_output
  
  validate_database pgsql $pgdatabase $pgdbuser "1234ABCD"
}

@test "PGSQL: Add Database (Duplicate)" {
  if [ -z "$(echo $DB_SYSTEM | grep -w "pgsql")" ]; then 
    skip "PostGreSQL is not installed"
  fi
  run v-add-database "$pguser" "database" "dbuser" "1234ABCD" "pgsql"
  assert_failure $E_EXISTS
}

@test "PGSQL: Rebuild Database" {
  if [ -z "$(echo $DB_SYSTEM | grep -w "pgsql")" ]; then 
    skip "PostGreSQL is not installed"
  fi
  run v-rebuild-database $pguser $pgdatabase
  assert_success
  refute_output 
}

@test "PGSQL: Change database user password" {
  if [ -z "$(echo $DB_SYSTEM | grep -w "pgsql")" ]; then 
    skip "PostGreSQL is not installed"
  fi
  run v-change-database-password $pguser $pgdatabase "123456"
  assert_success
  refute_output 
  
  validate_database pgsql $pgdatabase $pgdbuser "123456"
}

@test "PGSQL: Suspend database" {
  if [ -z "$(echo $DB_SYSTEM | grep -w "pgsql")" ]; then 
    skip "PostGreSQL is not installed"
  fi
  run v-suspend-database $pguser $pgdatabase
  assert_success
  refute_output
}

@test "PGSQL: Unsuspend database" {
  if [ -z "$(echo $DB_SYSTEM | grep -w "pgsql")" ]; then 
    skip "PostGreSQL is not installed"
  fi
  run v-unsuspend-database $pguser $pgdatabase
  assert_success
  refute_output
}

@test "PGSQL: Change database user" {
  if [ -z "$(echo $DB_SYSTEM | grep -w "pgsql")" ]; then 
    skip "PostGreSQL is not installed"
  fi
  skip
  run v-change-database-user $pguser $pgdatabase database
  assert_success
  refute_output 
  validate_database pgsql $pgdatabase $pgdatabase 123456
}


@test "PGSQL: Delete database" {
  if [ -z "$(echo $DB_SYSTEM | grep -w "pgsql")" ]; then  
    skip "PostGreSQL is not installed"
  fi
  run v-delete-database $pguser $pgdatabase
  assert_success
  refute_output 
}

@test "PGSQL: Delete missing database" {
  if [ -z "$(echo $DB_SYSTEM | grep -w "pgsql")" ]; then 
    skip "PostGreSQL is not installed"
  fi
  run v-delete-database $pguser $pgdatabase
  assert_failure $E_NOTEXIST
  run v-delete-user $pguser
}

#----------------------------------------------------------#
#                         System                           #
#----------------------------------------------------------#
@test "System: Set/Enable SMTP account for internal mail" {
  run v-add-sys-smtp $domain 587 STARTTLS info@$domain 1234-test noreply@$domain
  assert_success
  refute_output
}

@test "System: Disable SMTP account for internal mail" {
  run v-delete-sys-smtp
  assert_success
  refute_output
}

#----------------------------------------------------------#
#                        Firewall                          #
#----------------------------------------------------------#

@test "Firewall: Add ip to banlist" {
  run v-add-firewall-ban '1.2.3.4' 'HESTIA'
  assert_success
  refute_output
  
  check_ip_banned '1.2.3.4' 'HESTIA'
}

@test "Firewall: Delete ip to banlist" {
  run v-delete-firewall-ban '1.2.3.4' 'HESTIA'
  assert_success
  refute_output
  check_ip_not_banned '1.2.3.4' 'HESTIA'
}

@test "Firewall: Add ip to banlist for ALL" {
  run v-add-firewall-ban '1.2.3.4' 'HESTIA'
  assert_success
  refute_output
  run v-add-firewall-ban '1.2.3.4' 'MAIL'
  assert_success
  refute_output
  check_ip_banned '1.2.3.4' 'HESTIA'
}

@test "Firewall: Delete ip to banlist CHAIN = ALL" {
  run v-delete-firewall-ban '1.2.3.4' 'ALL'
  assert_success
  refute_output
  check_ip_not_banned '1.2.3.4' 'HESTIA'
}

@test "Test Whitelist Fail2ban" {

echo   "1.2.3.4" >> $HESTIA/data/firewall/excludes.conf
run v-add-firewall-ban '1.2.3.4' 'HESTIA'
rm $HESTIA/data/firewall/excludes.conf
check_ip_not_banned '1.2.3.4' 'HESTIA'
}

#----------------------------------------------------------#
#                         CLEANUP                          #
#----------------------------------------------------------#

@test "Mail: Delete domain" {
    # skip
    run v-delete-mail-domain $user $domain
    assert_success
    refute_output
}

@test "DNS: Delete domain" {
    # skip
    run v-delete-dns-domain $user $domain
    assert_success
    refute_output
}

@test "WEB: Delete domain" {
    # skip
    run v-delete-web-domain $user $domain
    assert_success
    refute_output
}

@test "Delete user" {
    run v-delete-user $user
    assert_success
    refute_output
}

@test "Ip: Delete the test IP" {
    run v-delete-sys-ip 198.18.0.125
    assert_success
    refute_output
}

@test 'assert()' {
  touch '/var/log/test.log'
  assert [ -e '/var/log/test.log' ]
}

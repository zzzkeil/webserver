#!/bin/bash

# visual text settings
RED="\e[31m"
GREEN="\e[32m"
GRAY="\e[37m"
YELLOW="\e[93m"

REDB="\e[41m"
GREENB="\e[42m"
GRAYB="\e[47m"
ENDCOLOR="\e[0m"


clear
echo -e " ${GRAYB}##############################################################################${ENDCOLOR}"
echo -e " ${GRAYB}#${ENDCOLOR} ${GREEN}Script to add a new website to your nginx webserver                        ${ENDCOLOR}${GRAYB}#${ENDCOLOR}"
echo -e " ${GRAYB}#${ENDCOLOR} ${GREEN}1. You need to check your DNS settings for your domain                     ${ENDCOLOR}${GRAYB}#${ENDCOLOR}"
echo -e " ${GRAYB}#${ENDCOLOR} ${GREEN}2. You need a email for letsencrypt setup                                  ${ENDCOLOR}${GRAYB}#${ENDCOLOR}"
echo -e " ${GRAYB}##############################################################################${ENDCOLOR}"
echo ""
echo ""
echo ""
echo  -e "                    ${RED}To EXIT this script press any key${ENDCOLOR}"
echo ""
echo  -e "                            ${GREEN}Press [Y] to begin${ENDCOLOR}"
read -p "" -n 1 -r
echo ""
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi
#
### root check
if [[ "$EUID" -ne 0 ]]; then
	echo -e "${RED}Sorry, you need to run this as root${ENDCOLOR}"
	exit 1
fi



### site data
read -p "sitename: " -e -i example.domain sitename
read -p "siteuser: " -e -i user-$sitename siteuser
randomkeyuser=$(</dev/urandom tr -dc 'A-Za-z0-9._' | head -c 32  ; echo)
read -p "userpass: " -e -i $randomkeyuser userpass
################################################# WIP
randomkey1=$(date +%s | cut -c 3-)
randomkey2=$(</dev/urandom tr -dc 'A-Za-z0-9._' | head -c 32  ; echo)
read -p "sql databasename: " -e -i db$randomkey1 databasename
read -p "sql databaseuser: " -e -i dbuser$randomkey1 databaseuser
read -p "sql databaseuserpasswd: " -e -i $randomkey2 databaseuserpasswd


mariadb -uroot <<EOF
CREATE DATABASE $databasename CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER '$databaseuser'@'localhost' identified by '$databaseuserpasswd';
GRANT ALL PRIVILEGES on $databasename.* to '$databaseuser'@'localhost' identified by '$databaseuserpasswd';
FLUSH privileges;
EOF


###########################################################


###create sftp user
useradd -g www-data -m -d /home/$sitename -s /sbin/nologin $siteuser
echo "$siteuser:$userpass" | chpasswd
cp /etc/ssh/sshd_config /root/script_backupfiles/sshd_config.bak01
echo "
Match User $siteuser
   AuthenticationMethods password
   PubkeyAuthentication no
   PasswordAuthentication yes
   ChrootDirectory %h
   ForceCommand internal-sftp
   AllowTcpForwarding no
   X11Forwarding no
   " >> /etc/ssh/sshd_config

chown root: /home/$sitename
chmod 755 /home/$sitename
   
###create folders and files
mkdir /home/$sitename/html
chmod 775 /home/$sitename/html

echo "
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="index.css">
  <title>$sitename</title>
</head>
<body>
<div class="bg"></div>
<div class="bg bg2"></div>
<div class="bg bg3"></div>
<div class="content">
<h1>Wellcome to $sitename</h1>
<p>This is a placeholder<p>
<p>I'll be back, soon .....<p>
</div>
</body>
</html>
" > /home/$sitename/html/index.html


echo "
<?php
phpinfo();
?>
" > /home/$sitename/html/checkphp.php


echo "
html {
  height:100%;
}

body {
  margin:0;
}

.bg {
  animation:slide 10s ease-in-out infinite alternate;
  background-image: linear-gradient(-60deg, #6c3 50%, #09f 50%);
  bottom:0;
  left:-50%;
  opacity:.5;
  position:fixed;
  right:-50%;
  top:0;
  z-index:-1;
}

.bg2 {
  animation-direction:alternate-reverse;
  animation-duration:20s;
}

.bg3 {
  animation-duration:35s;
}

.content {
  background-color:rgba(255,255,255,.8);
  border-radius:.25em;
  box-shadow:0 0 .25em rgba(0,0,0,.25);
  box-sizing:border-box;
  left:50%;
  padding:10vmin;
  position:fixed;
  text-align:center;
  top:50%;
  transform:translate(-50%, -50%);
}

h1 {
  font-family:monospace;
}

@keyframes slide {
  0% {
    transform:translateX(-25%);
  }
  100% {
    transform:translateX(25%);
  }
}
" > /home/$sitename/html/index.css 
chown -R $siteuser:www-data /home/$sitename/html


###prepare NGINX for Site and SSL
echo "server {
server_name $sitename;
listen 80;
listen [::]:80;
location ^~ /.well-known/acme-challenge {
proxy_pass http://127.0.0.1:81;
proxy_set_header Host \$host;
}
}
" > /etc/nginx/conf.d/$sitename.conf


###restart nginx
/usr/sbin/service nginx restart


### ??????ß  letsencrypt   aktuell ?????
certbot certonly -a webroot --webroot-path=/var/www/letsencrypt --agree-tos --register-unsafely-without-email --key-type ecdsa --elliptic-curve secp384r1 -d $sitename
#certbot certonly -a webroot --webroot-path=/var/www/letsencrypt --register-unsafely-without-email --rsa-key-size 4096 -d $sitename -d www.$sitename
#certbot certonly --dry-run -a webroot --webroot-path=/var/www/letsencrypt --rsa-key-size 4096 -d $sitename

###
function copy4SSL() {
cp /etc/nginx/conf.d/$sitename.conf /etc/nginx/conf.d/$sitename.conf.orig
cp /etc/nginx/ssl.conf /etc/nginx/ssl.conf.orig
rm /root/script_backupfiles/sshd_config.bak01
}
###
function errorSSL() {
userdel $siteuser
rm /etc/ssh/sshd_config 
mv /root/script_backupfiles/sshd_config.bak01 /etc/ssh/sshd_config 
systemctl restart sshd.service
rm -r /home/$sitename
rm /etc/nginx/conf.d/$sitename.conf
/usr/sbin/service nginx restart


echo -e " ${REDB}##############################################################################${ENDCOLOR}"
echo -e " ${REDB}#${ENDCOLOR}${RED}             *** ERROR while requesting your certificate(s) ***             ${ENDCOLOR}${REDB}#${ENDCOLOR}"
echo -e " ${REDB}##############################################################################${ENDCOLOR}"
echo -e ""
echo -e " ${YELLOW}##############################################################################${ENDCOLOR}"
echo -e " ${YELLOW}#${ENDCOLOR} Verify that both ports (80 + 443) are forwarded to this server!            ${ENDCOLOR}${YELLOW}#${ENDCOLOR}"
echo -e " ${YELLOW}#${ENDCOLOR} Verify, your DNS points to your IP !                                       ${ENDCOLOR}${YELLOW}#${ENDCOLOR}"
echo -e " ${YELLOW}#${ENDCOLOR} See the logfile /var/log/letsencrypt/letsencrypt.log                       ${ENDCOLOR}${YELLOW}#${ENDCOLOR}"
echo -e " ${YELLOW}#${ENDCOLOR} Then retry...                                                              ${ENDCOLOR}${YELLOW}#${ENDCOLOR}"
echo -e " ${YELLOW}##############################################################################${ENDCOLOR}"
echo ""
exit
}

if [ ! -d "/etc/letsencrypt/live/$sitename" ]; then
errorSSL
else
copy4SSL
mv /etc/nginx/conf.d/$sitename.conf /etc/nginx/conf.d/$sitename.conf.bak
touch /etc/nginx/conf.d/$sitename.conf
cat <<EOF >/etc/nginx/conf.d/$sitename.conf
server {
server_name $sitename www.$sitename;
listen 80;
listen [::]:80;
location ^~ /.well-known/acme-challenge {
proxy_pass http://127.0.0.1:81;
proxy_set_header Host \$host;
}
location / {
return 301 https://\$host\$request_uri;
}
}
server {
server_name $sitename www.$sitename;
listen 443 ssl;
listen [::]:443 ssl;
http2 on;
root /home/$sitename/html;
index index.php index.html index.htm;
location / {
		try_files \$uri \$uri/ =404;
	}

location ~ \.php$ {
    include fastcgi_params;
    fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
}

# letsencrypt for $sitename
ssl_certificate /etc/letsencrypt/live/$sitename/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/$sitename/privkey.pem;
ssl_trusted_certificate /etc/letsencrypt/live/$sitename/chain.pem;
#
# logs
access_log /var/log/nginx/$sitename.access.log;
error_log /var/log/nginx/$sitename.error.log warn;
#
}
EOF
sed -i "s/server_name.*;/server_name $sitename;/" /etc/nginx/conf.d/$sitename.conf
sed -i s/\#\ssl/\ssl/g /etc/nginx/ssl.conf
fi


systemctl restart nginx.service
systemctl restart sshd.service


echo "
$sitename
Adminname : $siteuser
Adminpassword : $userpass
Databasename : db$randomkey1
Databaseuser : dbuser$randomkey1
Databaseuserpasswd : $randomkey2 
#

" >> /root/website_user_list.txt


echo -e " ${GRAYB}##############################################################################${ENDCOLOR}"
echo -e " ${GRAYB}#${ENDCOLOR} ${GREEN}Done. Test your site now.                                                  ${ENDCOLOR}${GRAYB}#${ENDCOLOR}"
echo -e " ${GRAYB}##############################################################################${ENDCOLOR}"


### CleanUp
cat /dev/null > ~/.bash_history && history -c && history -w
exit 0

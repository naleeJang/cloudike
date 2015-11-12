#!/usr/bin/env bash

# ``cloudike-install.sh`` 
# Created by 2015.08.21 NaleeJang

# Make sure umask is sane
umask 022

# Not all distros have sbin in PATH for regular users.
PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin

# Keep track of the Cloudike directory
TOP_DIR=$(cd $(dirname "$0") && pwd)

# Import Configurations file
source $TOP_DIR/cloudikerc

#log
VERBOSE=true

# Hostname
HOST_NAME=$(hostname)

# Host IP
HOST_IP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
HOSTIP=${HOSTIP:-$HOST_IP}

echo $HOSTIP

# Add hostname to hosts file
for (( i = 0 ; i < ${#HOST_IP_LIST[@]} ; i++ )) ; do
  # check hosts's hostname 
  HOSTNAME_CHK=$(cat /etc/hosts | grep ${HOST_NAME_LIST[$i]})

  # if without host's hostname, add hostname to hosts file
  if ! [ -n "$HOSTNAME_CHK" ]; then
    echo "${HOST_IP_LIST[$i]}   ${HOST_NMAE_LIST[$i]}" >> /etc/hosts
  fi
done

# check hosts's hostname 
HOSTNAME_CHK=$(cat /etc/hosts | grep $HOST_NAME)

# if without host's hostname, add hostname to hosts file
if ! [ -n "$HOSTNAME_CHK" ]; then
echo "$HOSTIP   $HOST_NAME" >> /etc/hosts
fi

# check root
if [ `whoami` != "root" ]; then
	echo "It must access root account"
	exit 0
fi

# Configure OS Check
#------------------
if [[ -r /etc/redhat-release ]]; then
   if [[ -n "`grep \"CentOS\" /etc/redhat-release`" ]]; then
      ver=`sed -e 's/^.* \(.*\) (\(.*\)).*$/\1/' /etc/redhat-release`
      if [[ $ver="6.4" || $ver="6.5" || $ver="6.6" || $ver="6.7" ]]; then
        echo "Your CentOS is $ver"
      else
         echo "You Can't install cloudike. Cloudike can install CentOS6.5"
         exit 0
      fi
   else
      echo "You Can't install cloudike. Cloudike can install CentOS6.5"
      exit 0
   fi
else
   echo "You Can't install cloudike. Cloudike can install CentOS6.5"
   exit 0
fi

# Set Up Script Execution
# -----------------------

# Kill background processes on exit
trap clean EXIT
clean() {
    local r=$?
    kill >/dev/null 2>&1 $(jobs -p)
    exit $r
}


# Exit on any errors so that errors don't compound
trap failed ERR
failed() {
    local r=$?
    kill >/dev/null 2>&1 $(jobs -p)
    set +o xtrace
    exit $r
}

# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following along as the install occurs.
set -o xtrace


# Prepare Install Packages
# ========================

# System update
echo "System Update\n"
yum -y update

# Configuration SELINUX
echo "Configuration SELINUX\n"
sed -i -e 's/^SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
setenforce 0

if [[ -n "`grep \"net.core.somaxconn\" /etc/sysctl.conf`" ]]; then
  echo "already adding somaxconn"
else 
  echo 'net.core.somaxconn = 2048' >> /etc/sysctl.conf 
  sysctl -p
fi

rm -f /etc/localtime && cp /usr/share/zoneinfo/UTC /etc/localtime

# Install Common RPM
echo "Install Common RPM\n"
[[ "$(rpm -qa | grep epel-release)" ]] || rpm -Uvh http://ftp.linux.ncsu.edu/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
[[ "$(rpm -qa | grep rpmfusion)" ]] || yum -y localinstall --nogpgcheck http://download1.rpmfusion.org/free/el/updates/6/x86_64/rpmfusion-free-release-6-1.noarch.rpm http://download1.rpmfusion.org/nonfree/el/updates/6/x86_64/rpmfusion-nonfree-release-6-1.noarch.rpm
[[ -f "remi-release-6.rpm" ]] || wget http://rpms.famillecollet.com/enterprise/remi-release-6.rpm
[[ "$(rpm -qa | grep remi-release)" ]] || rpm -Uvh remi-release-6*.rpm

# Configure Nginx with Repository
echo "Configure Nginx with Repository\n"
if [ $NGINX_YN = y ]; then
   echo '[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=0
enabled=1' > /etc/yum.repos.d/nginx.repo
fi

# Configure Mongodb with Repository
echo "Configure Mongodb with Repository\n"
if [ $MONGODB_YN = y ]; then
   echo '[mongodb]
name=MongoDB Repository
baseurl=http://downloads-distro.mongodb.org/repo/redhat/os/x86_64/
gpgcheck=0
enabled=1' > /etc/yum.repos.d/mongodb.repo
fi

# Install Common Tools
echo "Install Common Tools\n"
yum clean all
yum -y install ntp vim bash-completion mc dstat wget screen man telnet
chkconfig ntpd on

# Configure Cloudike with Repository
echo "Configure Cloudike with Repository\n"
echo "[cloudike]
name=Cloudike repo
baseurl=${REPO_URL:-http://${HOSTIP}}
enabled=0
gpgcheck=0" > /etc/yum.repos.d/cloudike.repo


# Install Nginx
echo "Install Nginx\n"
if [ $NGINX_YN = y ]; then
   yum install nginx -y
   
   chkconfig nginx on

   # Configure nginx
   echo 'user  nginx;
worker_processes  4;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile        on; 
    tcp_nopush      on; 
    tcp_nodelay     on; 
    server_tokens   off;
    gzip            on; 
    gzip_static     on; 
    gzip_comp_level 5;
    gzip_min_length 1024;
    keepalive_timeout  65;
    include /etc/nginx/conf.d/*.conf;
}
' > /etc/nginx/nginx.conf

   rm -rf /etc/nginx/conf.d/*
fi


# Configure REPO
echo "Configure REPO\n"
if [ $REPO_YN = y ]; then
   echo 'server {
        listen 8088;
        server_name repo;
        charset utf-8;
        access_log  /var/log/nginx/repo.access.log  main;
        location / {
                root /var/www/repo;
                autoindex on;
        }
}
' > /etc/nginx/conf.d/repo.conf

   mkdir -p /var/www/repo

   cd /var/www/repo
   for value in "${CLOUIKD_RPM_LIST[@]}"; do
      [[ -f $value ]] || wget http://salt.cloudike.biz/$value
   done
   if [ ! -f librsync1-0.9.7-1.1.x86_64.rpm ]; then
      wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home:/dibo2010/CentOS_CentOS-6/x86_64/librsync1-0.9.7-1.1.x86_64.rpm
   fi
   [[ -f "LibreOffice_4.4.5_Linux_x86-64_rpm.tar.gz" ]] || wget http://104.155.216.65:8088/LibreOffice_4.4.5_Linux_x86-64_rpm.tar.gz
   [[ -f "LibreOffice_4.4.5_Linux_x86-64_rpm_langpack_ko.tar.gz" ]] || wget http://104.155.216.65:8088/LibreOffice_4.4.5_Linux_x86-64_rpm_langpack_ko.tar.gz
   
   yum install -y createrepo

   createrepo .
   chmod +x .
   chmod +x repodata
   service nginx start
   cd $TOP_DIR
fi

## repo edit hosts ##
sed -i 's/enabled=0/enabled=1/' /etc/yum.repos.d/cloudike.repo


#
# Install Mongodb
echo "Install Mongodb\n"
if [ $MONGODB_YN = y ]; then
  yum install mongodb-org -y
      
  MONGO_RUN=$(ps -ef | grep mongod | grep -v grep | awk '{print $2}')
  if [[ -n "$MONGO_RUN" ]]; then
     service mongod restart
  else 
     chkconfig mongod on
     service mongod start
  fi
   
fi

## rabbitmq hosts ##
echo "Install rabbitMQ\n"
if [ $RABBITMQ_YN = y ]; then
  [[ -f "erlang-solutions-1.0-1.noarch.rpm" ]] || wget http://packages.erlang-solutions.com/erlang-solutions-1.0-1.noarch.rpm
  [[ "$(rpm -qa | grep erlang-solutions)" ]] || rpm -Uvh erlang-solutions-1.0-1.noarch.rpm
  [[ "$(rpm -qa | grep erlang)" ]] || yum install erlang-17.4-1.el6 -y

  [[ "$(rpm -qa | grep rabbitmq-server)" ]] || rpm --import http://www.rabbitmq.com/rabbitmq-signing-key-public.asc
  [[ "$(rpm -qa | grep rabbitmq-server)" ]] || wget http://www.rabbitmq.com/releases/rabbitmq-server/v3.4.4/rabbitmq-server-3.4.4-1.noarch.rpm
  [[ "$(rpm -qa | grep rabbitmq-server)" ]] || yum install rabbitmq-server-3.4.4-1.noarch.rpm -y 
  
  echo '[
  {kernel,
    [
      {inet_dist_listen_min, 65530},
      {inet_dist_listen_max, 65535},
      {heartbeat, 40},
      {cluster_partition_handling, pause_minority}
    ]
  },
  {rabbit, 
    [
      {loopback_users, []}
    ]
  }
].' > /etc/rabbitmq/rabbitmq.config
 
  RABBIT_RUN=$(ps -ef | grep rabbitmq | grep -v grep | awk '{print $2}')
  if [[ -n "$RABBIT_RUN" ]]; then
         service rabbitmq-server restart
  else
         chkconfig rabbitmq-server on
         service rabbitmq-server start
  fi
  
  [[ "$(rabbitmqctl list_vhosts | grep mountbit)" ]] || rabbitmqctl set_policy ha-all "^ha\." '{"ha-mode":"all"}'
  [[ "$(rabbitmqctl list_vhosts | grep mountbit)" ]] || rabbitmqctl add_vhost mountbit
  [[ "$(rabbitmqctl list_vhosts | grep mountbit)" ]] || rabbitmqctl set_permissions -p mountbit guest ".*" ".*" ".*"
  [[ "$(rabbitmq-plugins list | grep rabbitmq_management | grep E)" ]] || rabbitmq-plugins enable rabbitmq_management
  [[ "$(rabbitmqctl list_users | grep cloudike-admin)" ]] || rabbitmqctl add_user cloudike-admin admin123
  [[ "$(rabbitmqctl list_users | grep cloudike-admin | grep administrator)" ]] || rabbitmqctl set_user_tags cloudike-admin administrator
  
  service rabbitmq-server restart
fi

echo "Install and Configuration Cloudike common packages"
if [[ $BACKEND_YN = y || $WORKER_YN = y || $FRONTEND_YN = y || $UPDATE_YN = y || $WEBDAV_YN = y ]]; then
  yum install python27 supervisor python-setuptools python27-setuptools python27-gunicorn python27-gevent libjpeg libtiff freetype python-psutil python-yaml -y
  yum install uwsgi-plugin-python27 uwsgi-plugin-syslog ${REPO_URL}uwsgi-1.9.18.2-1.el6.x86_64.rpm ${REPO_URL}uwsgi-plugin-common-1.9.18.2-1.el6.x86_64.rpm -y

  echo 'user  nginx;
worker_processes  4;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile        on; 
    tcp_nopush      on; 
    tcp_nodelay     on; 
    server_tokens   off;
    gzip            on; 
    gzip_static     on; 
    gzip_comp_level 5;
    gzip_min_length 1024;
    keepalive_timeout  65;
    include /etc/nginx/conf.d/*.conf;
}
' > /etc/nginx/nginx.conf
  
  echo '[unix_http_server]
file=/var/tmp/supervisor.sock
chmod=0777
[supervisord]
logfile=/var/log/supervisor/supervisord.log
logfile_maxbytes=50MB
logfile_backups=10
loglevel=info
pidfile=/var/run/supervisord.pid
nodaemon=false
minfds=1024
minprocs=200
user=backend
childlogdir = /var/log/supervisor
[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
[supervisorctl]
serverurl=unix:///var/tmp/supervisor.sock
[include]
files = /etc/supervisord.d/*.conf' > /etc/supervisord.conf
  
fi

echo "Install and Configuration Backend"
if [ $BACKEND_YN = y ]; then
  WGET_BACK_CK="cloudike-backend-clx-0.1-1443084860.el6.x86_64.rpm"
  WGET_SYNC_CK="librsync1-0.9.7-1.1.x86_64.rpm"
  WGET_XSLT_CK="libxslt-1.1.26-2.el6_3.1.x86_64.rpm"
  WGET_YAML_CK="libyaml-0.1.3-4.el6_6.x86_64.rpm"

  # rpm 파일 체크후 없으면 wget으로 rpm 파일 다운로드
  [[ -f $WGET_BACK_CK ]] || wget ${REPO_URL}cloudike-backend-clx-0.1-1443084860.el6.x86_64.rpm
  [[ -f $WGET_SYNC_CK ]] || wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home:/dibo2010/CentOS_CentOS-6/x86_64/librsync1-0.9.7-1.1.x86_64.rpm
  [[ -f $WGET_XSLT_CK ]] || wget ftp://rpmfind.net/linux/centos/6.7/os/x86_64/Packages/libxslt-1.1.26-2.el6_3.1.x86_64.rpm
  [[ -f $WGET_YAML_CK ]] || wget ftp://rpmfind.net/linux/centos/6.7/os/x86_64/Packages/libyaml-0.1.3-4.el6_6.x86_64.rpm
  
  INSTALL_SYNC_CK="librsync1-0.9.7-1.1.x86_64"
  INSTALL_XSLT_CK="libxslt-1.1.26-2.el6_3.1.x86_64"
  INSTALL_YAML_CK="libyaml-0.1.3-4.el6_6.x86_64"
  INSTALL_BACK_CK="cloudike-backend-clx-0.1-1443084860.el6.x86_64"
  
  # rpm 파일 설치 여부 확인 후 설치를 안했을 경우에만 설치
  [[ "$(rpm -qa | grep $INSTALL_SYNC_CK)" ]] || rpm -Uvh librsync1-0.9.7-1.1.x86_64.rpm
  [[ "$(rpm -qa | grep $INSTALL_XSLT_CK)" ]] || rpm -Uvh libxslt-1.1.26-2.el6_3.1.x86_64.rpm
  [[ "$(rpm -qa | grep $INSTALL_YAML_CK)" ]] || rpm -Uvh libyaml-0.1.3-4.el6_6.x86_64.rpm
  [[ "$(rpm -qa | grep $INSTALL_BACK_CK)" ]] || rpm -Uvh cloudike-backend-clx-0.1-1443084860.el6.x86_64.rpm
  
  # backend 사용자 계정이 있는지 체크한 후 없으면 사용자 계정 생성
  [[ "$(awk -F':' '{ print $1}' /etc/passwd | grep backend)" ]] || useradd --no-create-home --shell /bin/false backend
  chown backend:backend -R /var/www/backend
  chown backend:backend -R /var/log/supervisor/
  chkconfig supervisord on

  echo '[uwsgi]
plugin = python
disable-logging
uwsgi-socket = /var/www/backend/var/run/uwsgi_cpu.sock
socket-protocol = uwsgi
listen = 1024
socket-timeout = 20
chmod-socket = 666
wsgi-file = /var/www/backend/bin/django_wsgi.py
master
processes = 20
harakiri = 30
max-requests = 500
max-worker-lifetime = 3600' > /etc/uwsgi.d/uwsgi_cpu.ini

  echo '[program:notifications]
command = /var/www/backend/bin/notifications
process_name = notifications
directory = /var/www/backend
priority = 10
redirect_stderr = true
autostart = true
user = backend
stopsignal = KILL
[program:uwsgi_cpu]
command = uwsgi --ini /etc/uwsgi.d/uwsgi_cpu.ini
process_name = uwsgi_cpu
directory = /var/www/backend
priority = 20
redirect_stderr = true
autostart = true
user = backend
stopsignal = INT
stopwaitsecs = 300
killasgroup = true' > /etc/supervisord.d/backend.conf

  echo "features:
  email_notifications: True
  sharing: True
  links: True
  mount: False
  purge: False
auth:
  plugins:
    ktauth:
        enabled: false 
    email:
      enabled: true
    phone:
      enabled: true
      send_sms_url: http://smsc.ru/sys/send.php?login=user&psw=pass&phones=%(phone)s&mes=%(message)s
    mdoauth:
      enabled: false
    oauth:
      enabled: true
      service_name: test
      consumer_key: a1bc0db3c613c24e965a2398ac1ebdcc
      consumer_secret: e233254421ad7e202cefeb0d24d97f6cb77ecc5a08000e15e0175f1df1250554
      request_token_url: http://api.$DOMAIN_NAME/api/1/oauth/request_token/
      access_token_url: http://api.$DOMAIN_NAME/api/1/oauth/access_token/
      authorize_url: http://$DOMAIN_NAME/api/1/oauth/authorize/
      base_url: http://$DOMAIN_NAME/
      signature_method: HMAC-SHA1
      host: api.$DOMAIN_NAME
      callback_urls:
        default:  http://$DOMAIN_NAME/api/1/accounts/oauth_confirm/
        shdgfuvhwsguih: http://localhost:3000/oauth_verifier/
        #dima_stable_frontend: http://$DOMAIN_NAME/oauth_verifier/
        dima_stable_frontend: /oauth_verifier/
        #biz_cloudike: http://$DOMAIN_NAME/oauth_verifier/
      oauth_callback: http://$DOMAIN_NAME/ 
      for_testing:
        assert_counts: 3
        time_to_wait_after_assert_fail: 1
        oauth_callback: http://localhost:3000/oauth_verifier/
    ldap:
      enabled: false
#      server: 144.76.254.122
#      port: 389
oauth:
  http: true
  auth_page:
    enabled: true
    url: http://$DOMAIN_NAME/
  clients:
    backend:
      consumer_key: a1bc0db3c613c24e965a2398ac1ebdcc
      consumer_secret: e233254421ad7e202cefeb0d24d97f6cb77ecc5a08000e15e0175f1df1250554
web_frontend:
  base_url: 
  domain_for_emails: $DOMAIN_NAME
  default_user_lang: $DEFATULT_LANG
  urls:
    accounts_approve: /#/signup/approve?hash=%s
mail_settings:
  smtp_port: 25
  sender:
    name: Mountbit
    email: no-reply@$DOMAIN_NAME
storages:
  config_storage: mongodb  # (default, mongodb, simple)
  default_user_quota: 2147483648 #2 Gb
  default_fs:
    type: mongofs
    storage:
      api_version: $SWIFT_VERSION
      type: $STORAGE_TYPE
      username: $SWIFT_ID
      password: $SWIFT_PW
      tenant_name: $SWIFT_TENANT
      auth_url: $SWIFT_AUTH_URL
      container: $SWIFT_CONTAINER
    cache:
      tree:
        persistent_timeout: -1
        non_persistent_timeout: -1
mountbit:
  extrdata_check_configs: False
  trash_path: /trash
django:
  admins:
    0:
      - Some admin
      - admin@mail.com
    1:
      - Some admin1
      - admin1@mail.com
tasks:
  broker_url: amqp://guest:guest@127.0.0.1:55672/mountbit
notifications:
  transport: amqp  # (thrift, zmq, amqp)
max_queues: 10 
" > /var/www/backend/etc/mountbit/mountbit.yaml

  chown backend /var/www/backend/etc/mountbit/mountbit.yaml

  echo 'server {
        listen 81;
        server_name backend;
        access_log /var/log/nginx/backend_access.log main;
        error_log /var/log/nginx/backend_error.log;
        charset utf-8;
        client_max_body_size 200m;
        uwsgi_read_timeout 240;
                
        location /api {
                include uwsgi_params;
                uwsgi_param SCRIPT_NAME "";
                uwsgi_param SERVER_NAME "backend.domain.com";
                uwsgi_pass unix:///var/www/backend/var/run/uwsgi_cpu.sock;
                uwsgi_connect_timeout 50;
                uwsgi_read_timeout    50;
                uwsgi_send_timeout    50;
        }
        location /subscribe {
                proxy_pass http://127.0.0.1:9090;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
                proxy_read_timeout 86400s;
        }
        location / {
                return 200;
        }
}' > /etc/nginx/conf.d/backend.conf  

fi

echo "Install and Configuration Frontend"
if [ $FRONTEND_YN = y ]; then
  yum install cloudike-frontend2new-clx -y

  echo 'server {
        listen 82;
        server_name frontend;
        charset utf-8;
        access_log  /var/log/nginx/frontend-access.log  main;
        error_log  /var/log/nginx/frontend-error.log;
        location /assets/ {
                root /var/www/mountbit-frontend2_new;
        }
        location /oauth_verifier/ {
                add_header 'Content-Type' 'text/html';
                default_type text/html;
                return 200;
        }
        location / {
                root /var/www/mountbit-frontend2_new;
                if ( !-e $request_filename ) {
                        rewrite "^.*$" /index.html;
                }
        }
}' > /etc/nginx/conf.d/frontend.conf

  sed -i -e "s/https:\/\/cloudike.biz/http:\/\/$DOMAIN_NAME/g" /var/www/mountbit-frontend2_new/index.html
  sed -i -e "s/https:\/\/api.cloudike.biz/http:\/\/api.$DOMAIN_NAME/g" /var/www/mountbit-frontend2_new/index.html
  sed -i -e "s/wss:\/\/api.cloudike.biz/ws:\/\/api.$DOMAIN_NAME/g" /var/www/mountbit-frontend2_new/index.html
  sed -i -e "s/https:\/\/webdav.cloudike.biz/http:\/\/webdav.$DOMAIN_NAME/g" /var/www/mountbit-frontend2_new/index.html
  sed -i -e "s/cloudike.biz/$DOMAIN_NAME/g" /var/www/mountbit-frontend2_new/index.html

  sed -i -e "s/https:\/\/cloudike.biz/http:\/\/$DOMAIN_NAME/g" /var/www/mountbit-frontend2_new/assets/ng-cloudike-2.1.30.js
  sed -i -e "s/https:\/\/api.cloudike.biz/http:\/\/api.$DOMAIN_NAME/g" /var/www/mountbit-frontend2_new/assets/ng-cloudike-2.1.30.js
  sed -i -e "s/wss:\/\/api.cloudike.biz/ws:\/\/api.$DOMAIN_NAME/g" /var/www/mountbit-frontend2_new/assets/ng-cloudike-2.1.30.js
  sed -i -e "s/https:\/\/webdav.cloudike.biz/http:\/\/webdav.$DOMAIN_NAME/g" /var/www/mountbit-frontend2_new/assets/ng-cloudike-2.1.30.js
  sed -i -e "s/cloudike.biz/$DOMAIN_NAME/g" /var/www/mountbit-frontend2_new/assets/ng-cloudike-2.1.30.js
fi

echo "Install and Configuration Worker"
if [ $WORKER_YN = y ]; then
  echo '[program:celery]
command = /var/www/backend/bin/celery -A mountbit.backend worker -n backend.%%h -Ofair
process_name = celery
directory = /var/www/backend
priority = 30
redirect_stderr = true
autostart = true
stopwaitsecs = 300
killasgroup = true
[program:celery_beat]
command = /var/www/backend/bin/celery -A mountbit.backend beat
process_name = celery_beat
directory = /var/www/backend
priority = 40
redirect_stderr = true
autostart = true
stopwaitsecs = 300
killasgroup = true
[program:celery_images]
command = /var/www/backend/bin/celery -A mountbit.backend worker -Q images -n backend.images.%%h --concurrency=3 -Ofair
process_name = celery_images
directory = /var/www/backend
priority = 50
redirect_stderr = true
autostart = true
user = backend
stopwaitsecs = 300
killasgroup = true
stopsignal = INT
autorestart = true
[program:celery_videos]
command = /var/www/backend/bin/celery -A mountbit.backend worker -Q videos -n backend.videos.%%h --concurrency=1 -Ofair
process_name = celery_videos
directory = /var/www/backend
priority = 60
redirect_stderr = true
autostart = true
user = backend
stopwaitsecs = 300
killasgroup = true
stopsignal = INT
autorestart = true
[program:celery_default]
command = /var/www/backend/bin/celery -A mountbit.backend worker -Q default -n backend.default.%%h --concurrency=1 -Ofair
process_name = celery_default
directory = /var/www/backend
priority = 70
redirect_stderr = true
autostart = true
user = backend
stopwaitsecs = 300
killasgroup = true
stopsignal = INT
autorestart = true
[program:celery_add_public_link_to_storage]
command = /var/www/backend/bin/celery -A mountbit.backend worker -Q add_public_link_to_storage -n backend.add_public_link_to_storage.%%h --concurrency=1 -Ofair
process_name = celery_add_public_link_to_storage
directory = /var/www/backend
priority = 105
redirect_stderr = true
autostart = true
user = backend
stopwaitsecs = 300
killasgroup = true
stopsignal = INT
autorestart = true
[program:celery_metadata_full_listing_task]
command = /var/www/backend/bin/celery -A mountbit.backend worker -Q metadata_full_listing_task -n backend.metadata_full_listing_task.%%h --concurrency=1 -Ofair
process_name = celery_metadata_full_listing_task
directory = /var/www/backend
priority = 110
redirect_stderr = true
autostart = true
user = backend
stopwaitsecs = 300
killasgroup = true
stopsignal = INT
autorestart = true
[program:celery_zipdir]
command = /var/www/backend/bin/celery -A mountbit.backend worker -Q zipdir -n backend.zipdir.%%h --concurrency=1 -Ofair
process_name = celery_zipdir
directory = /var/www/backend
priority = 115
redirect_stderr = true
autostart = true
user = backend
stopwaitsecs = 300
killasgroup = true
stopsignal = INT
autorestart = true
[program:celery_remove_archives]
command = /var/www/backend/bin/celery -A mountbit.backend worker -Q remove_archives -n backend.remove_archives.%%h --concurrency=1 -Ofair
process_name = celery_remove_archives
directory = /var/www/backend
priority = 120
redirect_stderr = true
autostart = true
user = backend
stopwaitsecs = 300
killasgroup = true
autorestart = true
program:celery_documents]
command = /var/www/backend/bin/celery -A mountbit.backend worker -Q documents -n backend.documents.%%h --concurrency=1 -Ofair
process_name = celery_documents
environment = HOME="/tmp"
priority = 140
redirect_stderr = true
autostart = true
directory = /var/www/backend
user = backend
stopwaitsecs = 600
killasgroup = true
stopsignal = INT
autorestart = true
[program:celery_pdfs]
command = /var/www/backend/bin/celery -A mountbit.backend worker -Q pdfs -n backend.pdfs.%%h --concurrency=1 -Ofair
process_name = celery_pdfs
directory = /var/www/backend
environment = HOME="/tmp"
user = backend
stopwaitsecs = 600
killasgroup = true
priority = 150
redirect_stderr = true
autostart = true
stopsignal = INT
autorestart = true
[program:celery_transcoding]
command = /var/www/backend/bin/celery -A mountbit.backend worker -Q transcoding -n backend.transcoding.%%h --concurrency=3 -Ofair
process_name = celery_transcoding
directory = /var/www/backend/
environment = HOME="/tmp"
user = backend
stopwaitsecs = 600
killasgroup = true
priority = 160
redirect_stderr = true
autostart = true
stopsignal = INT
autorestart = true
[program:celery_recreate_extradata]
command = /var/www/backend/bin/celery -A mountbit.backend worker -Q recreate_extradata -n backend.recreate_extradata.%%h --concurrency=1 -Ofair
process_name = celery_recreate_extradata
directory = /var/www/backend/
environment = HOME="/tmp"
user = backend
stopwaitsecs = 600
killasgroup = true
priority = 170
redirect_stderr = true
autostart = true
stopsignal = INT
autorestart = true
[program:celery_recreate_timeline]
command = /var/www/backend/bin/celery -A mountbit.backend worker -Q backend.timeline -n backend.timeline.%%h --concurrency=1 -Ofair
process_name = celery_recreate_timeline
directory = /var/www/backend/
environment = HOME="/tmp"
user = backend
stopwaitsecs = 600
killasgroup = true
priority = 180
redirect_stderr = true
autostart = true
stopsignal = INT
autorestart = true
[program:celery_trash]
command = /var/www/backend/bin/celery -A mountbit.backend worker -Q trash_restore,trash_clear -n backend.trash.%%h --concurrency=1 -Ofair
process_name = celery_trash
directory = /var/www/backend/
environment = HOME="/tmp"
user = backend
stopwaitsecs = 600
killasgroup = true
priority = 190
redirect_stderr = true
autostart = true
stopsignal = INT
autorestart = true
' > /etc/supervisord.d/worker.conf

  wget -qO- https://raw.githubusercontent.com/dagwieers/unoconv/master/unoconv > /usr/local/bin/unoconv 
  chmod +x /usr/local/bin/unoconv

  yum install libXinerama libGL libGLU cups-libs -y

  [[ -f "LibreOffice_4.4.5_Linux_x86-64_rpm.tar.gz" ]] || wget ${REPO_URL}LibreOffice_4.4.5_Linux_x86-64_rpm.tar.gz
  [[ -f "LibreOffice_4.4.5_Linux_x86-64_rpm_langpack_ko.tar.gz" ]] || wget ${REPO_URL}LibreOffice_4.4.5_Linux_x86-64_rpm_langpack_ko.tar.gz
  [[ -f "LibreOffice_4.4.5_Linux_x86-64_rpm.tar.gz" ]] && tar xvfz LibreOffice_4.4.5_Linux_x86-64_rpm.tar.gz
  [[ -f "LibreOffice_4.4.5_Linux_x86-64_rpm_langpack_ko.tar.gz" ]] && tar xvfz LibreOffice_4.4.5_Linux_x86-64_rpm_langpack_ko.tar.gz
  [[ -d "LibreOffice_4.4.5.2_Linux_x86-64_rpm" ]] && mv LibreOffice_4.4.5.2_Linux_x86-64_rpm_langpack_ko/RPMS/* LibreOffice_4.4.5.2_Linux_x86-64_rpm/RPMS/
  [[ -d "LibreOffice_4.4.5.2_Linux_x86-64_rpm_langpack_ko" ]] && rm -rf LibreOffice_4.4.5.2_Linux_x86-64_rpm_langpack_ko/
  [[ "$(rpm -qa | grep libreoffice)" ]] && yum install LibreOffice_4.4.5.2_Linux_x86-64_rpm/RPMS/*.rpm -y
  yum install ffmpeg -y

  cat <<EOF > /usr/local/sbin/pskiller.py
#!/usr/bin/env python
# -*- coding: utf-8 -*-
import psutil
import sys
import time
import yaml
import signal
from optparse import OptionParser
signals = {
    'SIGHUP':  1,
    'SIGINT':  2,
    'SIGQUIT': 3,
    'SIGILL':  4,
    'SIGABRT': 6,
    'SIGFPE':  8,
    'SIGKILL': 9,
    'SIGUSR1': 10,
    'SIGSEGV': 11,
    'SIGUSR2': 12,
    'SIGPIPE': 13,
    'SIGALRM': 14,
    'SIGTERM': 15
}
def main():
    parser = OptionParser()
    parser.add_option('-c', '--config', action='store', dest='config', default='/usr/local/etc/pskiller.yaml', help='Path to config')
    (options, args) = parser.parse_args()
    try:
        stream = file(options.config, 'r');
    except IOError as e:
        print e
        return e.errno
    except Exception as e:
        print e
        return 1
    programs = yaml.load(stream)
    arr = []
    for program in programs:
        arr.append(program)
        try:
            if programs[program]['signal'] in signals:
                programs[program]['digsignal'] = signals[programs[program]['signal']]
            else:
                programs[program]['digsignal'] = 15
        except:
            programs[program]['signal'] = 15
        try:
            programs[program]['maxlife']
        except:
            programs[program]['maxlife'] = 600
    now = time.time()
    processes = psutil.get_pid_list()
    for pid in processes:
        try:
            process = psutil.Process(pid)
            worktime = int(now - process.create_time)
            program = process.name.split(' ')[0]
            if (program in arr) and (worktime > programs[program]['maxlife']):
                print 'Kill process "%s" with signal %s' % (program, programs[program]['signal'])
                process.send_signal(programs[program]['digsignal'])
        except:
            continue
    return 0
# start script
if __name__ == "__main__":
    sys.exit(main())
EOF

  chmod +x /usr/local/sbin/pskiller.py

  echo "ffmpeg:
  signal: SIGKILL
  maxlife: 1810
ffprobe:
  signal: SIGKILL
  maxlife: 30
soffice.bin:
  signal: SIGTERM
  maxlife: 70
gs:
  signal: SIGTERM
  maxlife: 600
" > /usr/local/etc/pskiller.yaml

  echo "*/1 * * * * root /usr/local/sbin/pskiller.py" > /etc/cron.d/pskiller
fi

echo "Install and Configuration Update"
if [ $UPDATE_YN = y ]; then
  echo 'server {
        listen 84;
        server_name updates;
        charset utf-8;
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Credentials true;
        add_header Access-Control-Allow-Headers DNT,X-Mx-ReqToken,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Mountbit-Auth,Web-frontend,Mountbit-User-Agent,Mountbit-Request-Id;
        add_header Access-Control-Allow-Methods GET,POST,OPTIONS;
        access_log  /var/log/nginx/updates_access.log  main;
        error_log  /var/log/nginx/updates_error.log;
        location / {
        if ($request_method = 'OPTIONS') {
                add_header Access-Control-Max-Age 1728000;
                add_header Content-Type "text/plain charset=UTF-8";
                add_header Content-Length 0;
                return 204;
        }       
                root /var/www/updates/updates;
                autoindex on;
        }
}
' > /etc/nginx/conf.d/updates.conf

  mkdir -p /var/www/updates/updates
fi

echo "Install and Configuration Webdav"
if [ $WEBDAV_YN = y ]; then
  yum install cloudike-webdav-clx -y

  echo '[program:webdav]
command = /var/www/mountbit-webdav/bin/gunicorn -b unix:/tmp/mountbit-webdav.sock -k gevent wsgi:application
process_name = gunicorn
directory = /var/www/mountbit-webdav
priority = 10
redirect_stderr = true
autostart = true
user = backend' > /etc/supervisord.d/webdav.conf

  echo '[main]
project = cloudike
[backend_api]
be_host = api.$DOMAIN_NAME
be_protocol = http
be_api_version = 1
[syslog_logging]
syslog_logging_enable = 1
syslog_logging_address = /dev/log
syslog_logging_facility = 16
[other]
dir_for_temporary_uploadable_files = /tmp
' > /var/www/mountbit-webdav/etc/settings.ini

  echo 'server {
        listen 83;
        server_name webdav;
        access_log /var/log/nginx/webdav_access.log;
        error_log /var/log/nginx/webdav_error.log;
        charset utf-8;
        client_max_body_size 200m;
        uwsgi_read_timeout 240;
        location / {
                proxy_pass http://unix:/tmp/mountbit-webdav.sock;
        }
}' > /etc/nginx/conf.d/webdav.conf

fi

echo "Install and Configuration Admin"
if [ $ADMIN_YN = y ]; then
  yum install cloudike-admin-biz -y

  echo "[program:uwsgi]
command = uwsgi -x /var/www/web-admin/etc/uwsgi/uwsgi.xml
process_name = uwsgi
directory = /var/www/web-admin
priority = 20
redirect_stderr = true
autostart = true
user = backend
stopsignal = INT
" > /etc/supervisord.d/admin.conf

  echo "<uwsgi>
    <plugin>python</plugin>
    <socket>/tmp/mountbit-web-admin_uwsgi.sock</socket>
    <socket-timeout>20</socket-timeout>
    <chmod-socket>666</chmod-socket>
    <file>/var/www/web-admin/bin/uwsgi.py</file>
    <processes>10</processes>
    <listen>10</listen>
    <master/>
    <disable-logging/>
</uwsgi>" > /var/www/web-admin/etc/uwsgi/uwsgi.xml

  echo "DEBUG: True
SECRET_KEY: foobarbaz
PLATFORM_NAME: clx
DEFAULT_PAGE: grafics_index
USER_AGENT: web-admin
METRIC_REGIONS: True
backend: http://api.$DOMAIN_NAME
frontend: http://$DOMAIN_NAME
billing: http://billing.$DOMAIN_NAME
select_choices:
    login_types:
        -
          - email
          - email
        -
          - phone
          - phone
    slug_types:
      -
        - default
        - default
      -
        - manual
        - manual
      -
        - bonus
        - bonus
      -
        - system
        - system
menu:
    -
      - grafics_index
      - System metrics
      - [index]
    -
      - users_index
      - Users
      - []
    -
      - companies_index
      - Companies
      - []
    -
      - soft_index
      - Soft
      - [soft_version_index, soft_update_index]
    -
      - key_value
      - Key-Value storage
      - []
    -
      - billing_index
      - Billing
      - [billing_services_index, billing_promo_index]
    -
      - feedback_index
      - Feedback
      - []
billing_menu:
    -
      endpoints: [billing_services_index , billing_index]
      url_for: billing_services_index
      name: Services
    -
      endpoints: [billing_promo_index]
      url_for: billing_promo_index
      name: Promo 
" > /var/www/web-admin/etc/admin.yaml

  echo 'server {
        listen 85;
        server_name admin;
        access_log /var/log/nginx/admin_access.log;
        error_log /var/log/nginx/admin_error.log;
        charset utf-8;
        client_max_body_size 200m;
        uwsgi_read_timeout 240;
        location / {
                include uwsgi_params;
                uwsgi_param SCRIPT_NAME "";
                uwsgi_pass unix:///tmp/mountbit-web-admin_uwsgi.sock;
                uwsgi_connect_timeout 50;
                uwsgi_read_timeout    50;
                uwsgi_send_timeout    50;
        }
}' > /etc/nginx/conf.d/admin.conf
  
  # Create Admin Account
  #/var/www/backend/bin/manage.py create_admin

fi

echo "Install and Configuration Haproxy"
if [ $HAPROXY_YN = y ]; then
  yum install haproxy -y

  chkconfig haproxy on

  echo "global
    log         127.0.0.1 local6 info
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     10000
    user        haproxy
    group       haproxy
    daemon
defaults
    mode                    http
    log                     global
    option                  httplog 
    option                  dontlognull
    option                  redispatch
    retries                 3
    timeout connect         5s
    timeout client          1m
    timeout server          1m
    maxconn                 9000
listen rabbitmq_cluster 127.0.0.1:55672
    mode tcp
    option tcplog
    balance roundrobin
    server node_rabbitmq1 $HOST_NAME:5672 check inter 5000 rise 2 fall 3
frontend cloudike
    bind 0.0.0.0:80
    option httpclose
    option forwardfor
    option accept-invalid-http-request
    acl acl_cors_options method OPTIONS
    acl acl_backend hdr(host) -i api.$DOMAIN_NAME
    acl acl_backend_through_frontend base_beg -i $DOMAIN_NAME/api/
    acl acl_backend_through_frontend_ws base_beg -i $DOMAIN_NAME/subscribe
    acl acl_frontend hdr(host) -i $DOMAIN_NAME
    acl acl_webdav hdr(host) -i webdav.$DOMAIN_NAME
    acl acl_updates hdr(host) -i updates.$DOMAIN_NAME
    acl acl_admin hdr(host) -i admin.$DOMAIN_NAME
    use_backend backend_cors_options if acl_cors_options acl_backend
    use_backend backend_cors_options if acl_cors_options acl_frontend
    use_backend backend_backend if acl_backend
    use_backend backend_backend if acl_backend_through_frontend
    use_backend backend_backend if acl_backend_through_frontend_ws
    use_backend backend_frontend if acl_frontend
    use_backend backend_webdav if acl_webdav
    use_backend backend_updates if acl_updates
    use_backend backend_admin if acl_admin
    default_backend backend_frontend
frontend cloudike_https
    #bind 0.0.0.0:443 ssl crt /etc/haproxy/domain.com.full.pem ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-RSA-RC4-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES128-SHA:AES256-SHA256:AES256-SHA:RC4-SHA no-sslv3
    bind 0.0.0.0:443
    option httpclose
    option forwardfor
    option accept-invalid-http-request
    #rspadd Strict-Transport-Security:\ max-age=31536000;\ includeSubdomains
    acl acl_cors_options method OPTIONS
    acl acl_backend hdr(host) -i api.$DOMAIN_NAME
    acl acl_backend_through_frontend base_beg -i $DOMAIN_NAME/api/
    acl acl_backend_through_frontend_ws base_beg -i $DOMAIN_NAME/subscribe
    acl acl_frontend hdr(host) -i $DOMAIN_NAME
    acl acl_webdav hdr(host) -i webdav.$DOMAIN_NAME
    acl acl_updates hdr(host) -i updates.$DOMAIN_NAME
    acl acl_admin hdr(host) -i admin.$DOMAIN_NAME
    use_backend backend_cors_options if acl_cors_options acl_backend
    use_backend backend_cors_options if acl_cors_options acl_frontend
    use_backend backend_backend if acl_backend
    use_backend backend_backend if acl_backend_through_frontend
    use_backend backend_backend if acl_backend_through_frontend_ws
    use_backend backend_frontend if acl_frontend
    use_backend backend_webdav if acl_webdav
    use_backend backend_updates if acl_updates
    use_backend backend_admin if acl_admin
    default_backend backend_frontend
backend backend_cors_options
    errorfile 503 /etc/haproxy/503_options.txt
backend backend_backend
    rspadd Access-Control-Allow-Origin:\ *
    rspadd Access-Control-Allow-Credentials:\ true
    rspadd Access-Control-Allow-Headers:\ DNT,X-Mx-ReqToken,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Mountbit-Auth,Web-frontend,Mountbit-User-Agent,Mountbit-Request-Id
    rspadd Access-Control-Allow-Methods:\ GET,POST,OPTIONS
    balance roundrobin
    server node_cloudike1 $HOST_NAME:81 check inter 5000 rise 2 fall 3
backend backend_frontend
    rspadd Access-Control-Allow-Origin:\ *
    rspadd Access-Control-Allow-Credentials:\ true
    rspadd Access-Control-Allow-Headers:\ DNT,X-Mx-ReqToken,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Mountbit-Auth,Web-frontend,Mountbit-User-Agent,Mountbit-Request-Id
    rspadd Access-Control-Allow-Methods:\ GET,POST,OPTIONS
    balance roundrobin
    server node_cloudike1 $HOST_NAME:82 check inter 5000 rise 2 fall 3
backend backend_webdav
    mode http
    balance roundrobin
    server node_cloudike1 $HOST_NAME:83 check inter 5000 rise 2 fall 3
backend backend_updates
    balance roundrobin
    server node_cloudike1 $HOST_NAME:84 check inter 5000 rise 2 fall 3
backend backend_admin
    balance roundrobin
    server node_cloudike1 $HOST_NAME:85 check inter 5000 rise 2 fall 3" > /etc/haproxy/haproxy.cfg


  echo "HTTP/1.1 204 No Content
Connection: close 
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Access-Control-Allow-Headers: DNT,X-Mx-ReqToken,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Mountbit-Auth,Web-frontend,Mountbit-User-Agent,Mountbit-Request-Id
Access-Control-Allow-Methods: GET, POST, OPTIONS
Access-Control-Max-Age: 1728000
Content-Length: 0" > /etc/haproxy/503_options.txt
  
  service nginx restart
  service supervisord start

  HA_RUN_CK=$(ps -ef | grep haproxy | grep -v grep | awk '{print $2}')
  if [[ $HA_RUN_CK ]]; then
    service haproxy restart
  else 
    service haproxy start
  fi
fi

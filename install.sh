#!/bin/bash

start_dir=$(pwd)

# 用户、用户组、项目目录定义
www_user="www-data"
www_group="www-data"
www_dir="/data/www"

install_dir="/usr/local"
dl_dir="/usr/local/src"
#dl_dir=${start_dir}/src
#if ! test -d ${dl_dir}; then
#	mkdir -p ${dl_dir}
#fi

php_dir=$install_dir/php7
nginx_dir=$install_dir/nginx
nginx_log_dir=/var/log/nginx
mysql_dir=${install_dir}/mysql
mysql_data_dir=/var/mysql/data

mysql_sock=/tmp/mysql.sock

nginx_version="1.10.3"
php_version="7.1.20"
mysql_version="5.7.20"


function init() {
	# 时间语言设置
	# 创建所需的用户跟用户组
	groupadd $www_group
	useradd -s /sbin/nologin -g $www_group $www_user
	# 创建 $www_dir 目录
	mkdir -p $www_dir
	chown -R $www_user:$www_group $www_dir

	# 创建 nginx 日志目录
	mkdir -p $nginx_log_dir
	chown -R $www_user:$www_group $nginx_log_dir
}

function init_yum() {
	yum -y install gcc gcc- c++ wget vim pcre-devel php-mcrypt libmcrypt-devel libxml2 libxml2-devel openssl openssl-devel curl-devel libjpeg-devel libpng-devel freetype-devel libmcrypt-devel libmemcached phpmemcached
}

function install_php() {
	local php_v="php-${php_version}"
	local php_conf_dir=$php_dir/etc
	cd $dl_dir
	if ! test -e ${php_v}.tar.gz; then
		wget http://us3.php.net/distributions/${php_v}.tar.gz
	fi
	if ! test -d ${php_v}; then
		tar -xvf ${php_v}.tar.gz	
	fi
	cd ${php_v}
	./configure \
		--prefix=${php_dir} \
		--with-config-file-path=${php_conf_dir} \
		--with-mcrypt=/usr/include \
		--with-mysqli=mysqlnd \
		--with-pdo-mysql=mysqlnd \
		--with-mysql-sock=${mysql_sock} \
		--enable-mysqlnd \
		--with-gd \
		--with-iconv \
		--with-zlib \
		--enable-bcmath \
		--enable-shmop \
		--enable-sysvsem \
		--enable-inline-optimization \
		--enable-mbregex \
		--enable-fpm \
		--enable-mbstring \
		--enable-ftp \
		--enable-gd-native-ttf \
		--with-openssl \
		--enable-pcntl \
		--enable-sockets \
		--with-xmlrpc \
		--enable-zip \
		--enable-soap \
		--with-gettext \
		--with-curl \
		--with-jpeg-dir \
		--with-freetype-dir \
		--with-libmemcached-dir=/usr/local/libmemcached
	make && make install
	#make install
	echo "starting configure"
	rm -rf ${php_conf_dir}/php-fpm.d/www.conf
	rm -rf ${php_conf_dir}/php-fpm.d/www.conf
	rm -rf ${php_conf_dir}/php-fpm.conf
	cp ${start_dir}/php/www.conf.default ${php_conf_dir}/php-fpm.d/www.conf
	cp ${start_dir}/php/php.ini.default ${php_conf_dir}/php.ini
	cp ${start_dir}/php/php-fpm.conf.default ${php_conf_dir}/php-fpm.conf

	# systemctl
	echo -e "[Unit]
Description=The PHP FastCGI Process Manager
After=syslog.target network.target

[Service]
Type=simple
PIDFile=${php_dir}/var/run/php-fpm.pid
ExecStart=${php_dir}/sbin/php-fpm --nodaemonize --fpm-config ${php_conf_dir}/php-fpm.conf
ExecReload=/bin/kill -USR2 \$MAINPID
ExecStop=/bin/kill -SIGINT \$MAINPID

[Install]
WantedBy=multi-user.target" > /usr/lib/systemd/system/php-fpm.service
	
	# 环境变量
	echo -e "if ! echo \${PATH} | /bin/grep -q ${php_dir}/bin ; then
	PATH=${php_dir}/bin:\${PATH}
fi" > /etc/profile.d/php.sh

	echo -e "if ( \"\${path}\" !~ *${php_dir}/bin* ) then
set path = ( ${php_dir}/bin $path )
endif" > /etc/profile.d/php.csh

	#echo -e "\nexport PATH=$PATH:${php_dir}/bin" >> /etc/profile
	source /etc/profile
	# 开机自启
	systemctl enable php-fpm.service
	systemctl start php-fpm.service

	echo -e "<?php\n  phpinfo();" > ${www_dir}/index.php
	echo "PHP installed success!!!"
	# rm 安装包
	rm -rf $dl_dir/$php_v.tar.gz
	rm -rf $dl_dir/$php_v

}

function install_nginx()
{
	local nginx_conf=${nginx_dir}/conf
	local nginx_v=nginx-${nginx_version}
	cd ${dl_dir}
	if ! test -e ${nginx_v}.tar.gz ; then
		wget "http://nginx.org/download/${nginx_v}.tar.gz"
	fi
	if ! test -w ${nginx_v}; then
		tar -xvf ${nginx_v}.tar.gz
	fi
	cd ${nginx_v}

	./configure \
	--prefix=$nginx_dir \
	--with-http_ssl_module \
	--with-http_realip_module \
	--with-http_addition_module \
	--with-http_sub_module \
	--with-http_dav_module \
	--with-http_flv_module \
	--with-http_mp4_module \
	--with-http_gunzip_module \
	--with-http_gzip_static_module \
	--with-http_random_index_module \
	--with-http_secure_link_module \
	--with-http_stub_status_module \
	--with-http_auth_request_module \
	--with-threads \
	--with-stream \
	--with-stream_ssl_module \
	--with-http_slice_module \
	--with-mail \
	--with-mail_ssl_module \
	--with-file-aio \
	--with-http_v2_module \
	--with-ipv6 \
	--with-pcre

	make && make install

	echo -e "[Unit]
Description=nginx.service
After=network.target

[Service]
Type=forking
ExecStart=${nginx_dir}/sbin/nginx
ExecReload=${nginx_dir}/sbin/nginx -s reload
ExecStop=${nginx_dir}/sbin/nginx -s stop
PrivateTmp=true

[Install]
WantedBy=multi-user.target" > /usr/lib/systemd/system/nginx.service

	#echo -e "\nexport PATH=$PATH:${nginx_dir}/sbin" >> /etc/profile
	echo -e "if ! echo \${PATH} | /bin/grep -q ${nginx_dir}/sbin ; then
	PATH=${nginx_dir}/sbin:\${PATH}
fi" > /etc/profile.d/nginx.sh

	echo -e "if ( \"\${path}\" !~ *${nginx_dir}/sbin* ) then
set path = ( ${nginx_dir}/sbin $path )
endif" > /etc/profile.d/nginx.csh

	source /etc/profile

 	mkdir ${nginx_dir}/conf/vhost
	cp ${start_dir}/nginx/default.conf ${nginx_dir}/conf/nginx.conf
	cp ${start_dir}/nginx/vhost.conf ${nginx_dir}/conf/vhost
	#自启
    systemctl enable nginx.service
    systemctl start nginx.service
	nginx -s reload

	echo "<center>hello world ------nginx!<center>" > ${www_dir}/index.html
	# rm
	rm -rf ${dl_dir}/nginx-${nginx_version}.tar.gz
	rm -rf ${dl_dir}/nginx-${nginx_version}

}

function install_mysql() {
	local data_dir=$mysql_data_dir
	local mysql_v=mysql-${mysql_version}
	# boost dir
	local boost_dir=${install_dir}/boost_1_59_0
	yum -y install gcc cmake make gcc-c++ ncurses-devel openssl-devel bison ncurses chkconfig lsof
	yum -y install perl-GD

	cd ${dl_dir}

	if ! test -e ${mysql_v}.tar.gz; then
		wget https://cdn.mysql.com//Downloads/MySQL-5.7/${mysql_v}.tar.gz
	fi
	if ! test -d ${mysql_v}; then
		tar -zxvf ${mysql_v}.tar.gz
	fi

	# boost >= 1.59
	if ! test -e boost_1_59_0.tar.gz; then
		wget https://sourceforge.net/projects/boost/files/boost/1.59.0/boost_1_59_0.tar.gz
	fi
	if ! test -d ${boost_dir}; then
		tar -zxvf boost_1_59_0.tar.gz
		mv boost_1_59_0 ${boost_dir}
	fi
	useradd -r -U mysql -M -d ${data_dir} -s /sbin/nologin

	# 创建所需要的目录
	mkdir -p /var/mysql/
	mkdir -p /var/mysql/data/
	mkdir -p /var/mysql/log/
	touch /var/mysql/log/error.log
	chown -R mysql:mysql /var/mysql

	mkdir -p /var/log/mariadb
	touch /var/log/mariadb/mariadb.log
	chown -R mysql:mysql /var/log/mariadb

	cd $mysql_v
	cmake . -DCMAKE_INSTALL_PREFIX=${mysql_dir} -DMYSQL_DATADIR=${data_dir} -DWITH_BOOST=${boost_dir} -DMYSQL_TCP_PORT=3306 -DMYSQL_UNIX_ADDR=${mysql_sock} -DDEFAULT_CHARSET=utf8 -DDEFAULT_COLLATION=utf8_general_ci -DWITH_EXTRA_CHARSETS:STRING=all -DWITH_MYISAM_STORAGE_ENGINE=1 -DWITH_INNOBASE_STORAGE_ENGINE=1 -DWITH_READLINE=1 -DENABLED_LOCAL_INFILE=1 -DWITH_MEMORY_STORAGE_ENGINE=1 -DMYSQL_USER=mysql

	make
	make install

	# 配置 my.cnf datadir socket
	src_arr=("datadir=.*" "socket=.*")
	target=("datadir=${data_dir}" "socket=${mysql_sock}")

	for (( i = 0; i < ${#src_arr[*]}; i++ )); do
		#echo ${src_arr[${i}]}
		#echo ${target[${i}]}
		sed -i "s!${src_arr[$i]}!${target[$i]}!" /etc/my.cnf
	done
	# 再 socket=.* 的下一行配置 my.cnf 日志文件，pid-file
	sed -i '/socket=.*/a\log_error=/var/mysql/log/error.log\npid-file=/var/mysql/mysql.pid' /etc/my.cnf

	# /etc/init.d/mysqld start | stop | restart 启动
	cp ${mysql_dir}/support-files/mysql.server /etc/init.d/mysqld
	
	# 将MySQL数据库的动态链接库共享至系统链接库
	ln -s ${mysql_dir}/lib/libmysqlclient.so.20 /usr/lib/libmysqlclient.so.20

	# 环境变量
	echo -e "if ! echo \${PATH} | /bin/grep -q ${mysql_dir}/bin ; then
	PATH=${mysql_dir}/bin:\${PATH}
fi" > /etc/profile.d/mysql.sh

	echo -e "if ( \"\${path}\" !~ *${mysql_dir}/bin* ) then
set path = ( ${mysql_dir}/bin $path )
endif" > /etc/profile.d/mysql.csh
	
	source /etc/profile.d/mysql.sh
	#/etc/profile

	chkconfig --add mysqld
	chkconfig --level 345 mysqld on
	rm -rf $data_dir/*
	# 初始化 mysql root 密码为空
	mysqld --initialize-insecure --user=mysql --basedir=$mysql_dir --datadir=$data_dir

	/etc/init.d/mysqld restart
}

function install_tamalloc() {
	cd $dl_dir
	wget http://download.savannah.gnu.org/releases/libunwind/libunwind-1.1.tar.gz   
	tar -zxvf libunwind-1.1.tar.gz
	cd libunwind-1.1/
	CFLAGS=-fPIC ./configure
	make CFLAGS=-fPIC
	make CFLAGS=-fPIC install

	cd $dl_dir
	wget https://github.com/gperftools/gperftools/releases/download/gperftools-2.5/gperftools-2.5.tar.gz
	tar -zxvf  gperftools-2.5.tar.gz
	cd gperftools-2.5
	./configure
	make && make install
	echo "/usr/local/lib" > /etc/ld.so.conf.d/usr_local_lib.conf
	/sbin/ldconfig
	echo -e export LD_PRELOAD=/usr/local/lib/libtcmalloc_minimal.so >> $mysql_dir/bin/mysqld_safe
	service mysqld restart
}

function print_conf() {
	echo -e "===========Install Success==========="
	echo -e "--------------NGINX---------------"
	echo -e "Install dir \t ${nginx_dir}"
	echo -e "www dir \t ${www_dir}"
	echo -e "Config dir \t ${nginx_dir}/conf"
	echo -e "vhost config \t ${nginx_dir}/conf/vhost"
	echo -e "Log dir \t /var/log/nginx/"
	echo -e "--------------PHP-----------------"
	echo -e "Install dir \t ${php_dir}"
	echo -e "Config dir \t ${php_dir}/etc"
	echo -e "socket & pid \t ${php_dir}/var/run"
	echo -e "log dir \t ${php_dir}/var/log"
	echo -e "--------------MYSQL---------------"
	echo -e "Install dir \t ${mysql_dir}"
	echo -e "Data dir \t ${mysql_data_dir}"
	echo -e "Config \t /etc/my.cnf"
	echo -e "Mysql pid \t /var/mysql/mysql.pid"
	echo -e "Mysql log dir \t /var/mysql/log"
	echo -e "mariadb dir \t /var/log/mariadb"
	echo -e "Mysql root 密码为空，请自己修改!"
}

init_yum
init
install_nginx
install_php
install_mysql
print_conf
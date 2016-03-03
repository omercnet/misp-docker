#!/bin/bash

set -e

# Set MYSQL_ROOT_PASSWORD
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
  echo "MYSQL_ROOT_PASSWORD is not set, use default value 'root'"
  MYSQL_ROOT_PASSWORD=root
else
  echo "MYSQL_ROOT_PASSWORD is set to '$MYSQL_ROOT_PASSWORD'" 
fi

# Set MYSQL_MISP_PASSWORD
if [ -z "$MYSQL_MISP_PASSWORD" ]; then
  echo "MYSQL_MISP_PASSWORD is not set, use default value 'misp'"
  MYSQL_MISP_PASSWORD=misp
fi

# Create a database and user  

echo "Connecting to database ..."

# Ugly but we need MySQL temporary up for the setup phase...
service mysql start
sleep 5

ret=`echo 'SHOW DATABASES;' | mysql -u root --password="$MYSQL_ROOT_PASSWORD" -h 127.0.0.1 -P 3306 # 2>&1`

if [ $? -eq 0 ]; then
  echo "Connected to database successfully"
  found=0
  for db in $ret; do
    if [ "$db" == "misp" ]; then
      found=1
    fi    
  done
  if [ $found -eq 1 ]; then
    echo "Database misp found"
  else
    echo "Database misp not found, creating now one ..."
	cat > /tmp/create_misp_database.sql <<-EOSQL
		create database misp;
		grant usage on *.* to misp identified by "$MYSQL_MISP_PASSWORD";
		grant all privileges on misp.* to misp;
	EOSQL
    ret=`mysql -u root --password="$MYSQL_ROOT_PASSWORD" -h 127.0.0.1 -P 3306 2>&1 < /tmp/create_misp_database.sql`
    if [ $? -eq 0 ]; then
      echo "Created database misp successfully"

      echo "Importing /var/www/MISP/INSTALL/MYSQL.sql"
      ret=`mysql -u misp --password="$MYSQL_MISP_PASSWORD" misp -h 127.0.0.1 -P 3306 2>&1 < /var/www/MISP/INSTALL/MYSQL.sql`
      if [ $? -eq 0 ]; then
        echo "Imported /var/www/MISP/INSTALL/MYSQL.sql successfully"
      else
        echo "ERROR: Importing /var/www/MISP/INSTALL/MYSQL.sql failed:"
        echo $ret
      fi
      service mysql stop
    else
      echo "ERROR: Creating database misp failed:"
      echo $ret
    fi    
  fi
else
  echo "ERROR: Connecting to database failed:"
  echo $ret
fi

# MISP configuration

cd /var/www/MISP/app/Config
cp -a database.default.php database.php
sed -i "s/localhost/127.0.0.1/" database.php
sed -i "s/db\s*login/misp/" database.php
sed -i "s/8889/3306/" database.php
sed -i "s/db\s*password/$MYSQL_MISP_PASSWORD/" database.php

cp -a core.default.php core.php

chown -R www-data:www-data /var/www/MISP/app/Config
chmod -R 750 /var/www/MISP/app/Config

# Display tips
if [ -r /.firstboot.tmp ]; then
	cat <<__WELCOME__
---------------------------------------------------------------------------------------------
The MISP docker has been successfully booted for the first time.
Don't forget:
- Change 'baseurl' in /var/www/MISP/app/Config/config.php
- Reconfigure postfix to match your environment
- Upload the GPG key
---------------------------------------------------------------------------------------------
__WELCOME__
	rm -f /.firstboot.tmp
fi

# Start supervisord 
cd /
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf

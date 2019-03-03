#!/bin/bash

# Usage: execute.sh [WildFly mode] [configuration file]
#
# The default mode is 'standalone' and default configuration is based on the
# mode. It can be 'standalone.xml' or 'domain.xml'.

JBOSS_HOME=/opt/jboss/wildfly
JBOSS_CLI=$JBOSS_HOME/bin/jboss-cli.sh
JBOSS_MODE=${1:-"standalone"}
JBOSS_CONFIG=${2:-"$JBOSS_MODE.xml"}

function wait_for_server() {
  until `$JBOSS_CLI -c ":read-attribute(name=server-state)" 2> /dev/null | grep -q running`; do
    sleep 1
  done
}

echo "=> Starting WildFly server"
$JBOSS_HOME/bin/$JBOSS_MODE.sh -b 0.0.0.0 -c $JBOSS_CONFIG &

echo "=> Waiting for the server to boot"
wait_for_server

echo "=> Executing the commands"
echo "=> MYSQL_HOST (explicit): " $MYSQL_HOST
echo "=> MYSQL_PORT (explicit): " $MYSQL_PORT
echo "=> MYSQL (docker host): " $DB_PORT_3306_TCP_ADDR
echo "=> MYSQL (docker port): " $DB_PORT_3306_TCP_PORT
echo "=> MYSQL (k8s host): " $MYSQL_SERVICE_SERVICE_HOST
echo "=> MYSQL (k8s port): " $MYSQL_SERVICE_SERVICE_PORT
echo "=> MYSQL_URI (docker with networking): " $MYSQL_URI

$JBOSS_CLI -c << EOF
batch

#set CONNECTION_URL=jdbc:mysql://$MYSQL_SERVICE_SERVICE_HOST:$MYSQL_SERVICE_SERVICE_PORT/sample
set CONNECTION_URL=jdbc:mysql://$MYSQL_URI/sample
echo "Connection URL: " $CONNECTION_URL

# Add MySQL module
module add --name=com.mysql --resource-delimiter=: --resources=/opt/jboss/wildfly/customization/mysql-connector-java-5.1.31-bin.jar:/opt/jboss/wildfly/customization/tomcat-jdbc-9.0.16.jar:/opt/jboss/wildfly/customization/tomcat-juli-9.0.16.jar --dependencies=javax.api,javax.transaction.api

# Add p6spy module
module add --name=com.p6spy \
      --resources=/opt/jboss/wildfly/customization/p6spy-3.8.1.jar \
      --dependencies=javax.api,javax.transaction.api,com.mysql


# Add MySQL driver
/subsystem=datasources/jdbc-driver=mysql:add(driver-name=mysql,driver-module-name=com.mysql,driver-xa-datasource-class-name=com.mysql.jdbc.jdbc2.optional.MysqlXADataSource)
# Add P6Spy driver
/subsystem=datasources/jdbc-driver=p6spy:add(driver-name=p6spy,driver-module-name=com.p6spy,driver-class-name=com.p6spy.engine.spy.P6SpyDriver,driver-xa-datasource-class-name=com.mysql.jdbc.jdbc2.optional.MysqlXADataSource)

# Add the datasource
#data-source add --name=mysqlDS --driver-name=mysql --jndi-name=java:jboss/datasources/ExampleMySQLDS --connection-url=jdbc:mysql://$MYSQL_HOST:$MYSQL_PORT/sample?useUnicode=true&amp;characterEncoding=UTF-8 --user-name=mysql --password=mysql --use-ccm=false --max-pool-size=25 --blocking-timeout-wait-millis=5000 --enabled=true
#data-source add --name=mysqlDS --driver-name=mysql --jndi-name=java:jboss/datasources/ExampleMySQLDS --connection-url=jdbc:mysql://$MYSQL_SERVICE_HOST:$MYSQL_SERVICE_PORT/sample?useUnicode=true&amp;characterEncoding=UTF-8 --user-name=mysql --password=mysql --use-ccm=false --max-pool-size=25 --blocking-timeout-wait-millis=5000 --enabled=true
#data-source add --name=mysqlDS --driver-name=mysql --jndi-name=java:jboss/datasources/ExampleMySQLDS --connection-url=jdbc:mysql://$DB_PORT_3306_TCP_ADDR:$DB_PORT_3306_TCP_PORT/sample?useUnicode=true&amp;characterEncoding=UTF-8 --user-name=mysql --password=mysql --use-ccm=false --max-pool-size=25 --blocking-timeout-wait-millis=5000 --enabled=true
#data-source add --name=mysqlDS --driver-name=mysql --jndi-name=java:jboss/datasources/ExampleMySQLDS --connection-url=jdbc:mysql://$MYSQL_SERVICE_SERVICE_HOST:$MYSQL_SERVICE_SERVICE_PORT/sample --user-name=mysql --password=mysql --use-ccm=false --max-pool-size=25 --blocking-timeout-wait-millis=5000 --enabled=true
data-source add --name=mysqlDS --driver-name=mysql --datasource-class=org.apache.tomcat.jdbc.pool.DataSource --jndi-name=java:jboss/datasources/ExampleMySQLDS --connection-url=jdbc:mysql://$MYSQL_URI/sample?useUnicode=true&amp;characterEncoding=UTF-8 --user-name=mysql --password=mysql --use-ccm=false --max-pool-size=25 --blocking-timeout-wait-millis=5000 --enabled=true
data-source add --name=p6spyDS --driver-name=p6spy --jndi-name=java:jboss/datasources/p6SpyDS --connection-url=jdbc:p6spy:mysql://$MYSQL_URI/sample?useUnicode=true&amp;characterEncoding=UTF-8 --user-name=mysql --password=mysql --use-ccm=false --max-pool-size=25 --blocking-timeout-wait-millis=5000 --enabled=true

/subsystem=datasources/data-source=mysqlDS/connection-properties=driverClassName:add(value="com.mysql.jdbc.Driver")
/subsystem=datasources/data-source=mysqlDS/connection-properties=url:add(value="jdbc:mysql://db:3306/sample"
/subsystem=datasources/data-source=mysqlDS/connection-properties=username:add(value="mysql")
/subsystem=datasources/data-source=mysqlDS/connection-properties=password:add(value="mysql")

/system-property=jboss.bind.address:add(value=0.0.0.0)
/system-property=jboss.bind.address.management:add(value=0.0.0.0)

# Execute the batch
run-batch
EOF

echo "=> Shutting down WildFly"
if [ "$JBOSS_MODE" = "standalone" ]; then
  $JBOSS_CLI -c ":shutdown"
else
  $JBOSS_CLI -c "/host=*:shutdown"
fi

echo "=> Restarting WildFly"
cp /opt/jboss/wildfly/customization/spy.properties $JBOSS_HOME/bin/spy.properties
$JBOSS_HOME/bin/$JBOSS_MODE.sh -b 0.0.0.0 -c $JBOSS_CONFIG

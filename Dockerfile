FROM jboss/wildfly:latest

USER jboss

ADD customization /opt/jboss/wildfly/customization/

RUN /opt/jboss/wildfly/bin/add-user.sh admin jboss --silent
# the following line was needed for my sample application
# COPY jaxb-impl.jar /opt/jboss/wildfly/standalone/lib/ext
CMD ["/opt/jboss/wildfly/customization/execute.sh"]
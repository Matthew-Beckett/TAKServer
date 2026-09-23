#!/bin/sh
# Ready once the config microservice has started.
exec grep -q 'Started TAK Server config Microservice' /opt/tak/logs/takserver-config.log 2>/dev/null

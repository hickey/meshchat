#!/bin/sh /etc/rc.common

START=99
APP=meshchatsync
SERVICE_WRITE_PID=1
SERVICE_DAEMONIZE=1

start() {
	service_start /usr/local/bin/meshchatsync
}
stop() {
    service_stop /usr/local/bin/meshchatsync
    killall meshchatsync
}

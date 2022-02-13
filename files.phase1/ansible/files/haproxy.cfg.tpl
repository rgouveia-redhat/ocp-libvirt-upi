#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    # to have these messages end up in /var/log/haproxy.log you will
    # need to:
    #
    # 1) configure syslog to accept network log events.  This is done
    #    by adding the '-r' option to the SYSLOGD_OPTIONS in
    #    /etc/sysconfig/syslog
    #
    # 2) configure local2 events to go to the /var/log/haproxy.log
    #   file. A line like the following can be added to
    #   /etc/sysconfig/syslog
    #
    #    local2.*                       /var/log/haproxy.log
    #
    log         127.0.0.1 local2

    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats

    # utilize system-wide crypto-policies
    ssl-default-bind-ciphers PROFILE=SYSTEM
    ssl-default-server-ciphers PROFILE=SYSTEM

#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

#---------------------------------------------------------------------

frontend stats
  bind		*:1936
  mode		http
  log		global
  maxconn	10
  stats		enable
  stats		hide-version
  stats		refresh 30s
  stats		show-node
  stats		show-desc Stats for ocp4 cluster: admin - ocp4
  stats 	auth admin:ocp4
  stats		uri /stats

listen api-server-6443
  bind *:6443
  mode tcp
  server bootstrap bootstrap.CLUSTER_NAME.CLUSTER_DOMAIN:6443 check inter 1s backup
  server master1 master1.CLUSTER_NAME.CLUSTER_DOMAIN:6443 check inter 1s
  server master2 master2.CLUSTER_NAME.CLUSTER_DOMAIN:6443 check inter 1s
  server master3 master3.CLUSTER_NAME.CLUSTER_DOMAIN:6443 check inter 1s

listen machine-config-server-22623
  bind *:22623
  mode tcp
  server bootstrap bootstrap.CLUSTER_NAME.CLUSTER_DOMAIN:22623 check inter 1s backup
  server master1 master1.CLUSTER_NAME.CLUSTER_DOMAIN:22623 check inter 1s
  server master2 master2.CLUSTER_NAME.CLUSTER_DOMAIN:22623 check inter 1s
  server master3 master3.CLUSTER_NAME.CLUSTER_DOMAIN:22623 check inter 1s

listen ingress-router-443
  bind *:443
  mode tcp
  balance source
  server worker1 worker1.CLUSTER_NAME.CLUSTER_DOMAIN:443 check inter 1s
  server worker2 worker2.CLUSTER_NAME.CLUSTER_DOMAIN:443 check inter 1s
  server worker3 worker3.CLUSTER_NAME.CLUSTER_DOMAIN:443 check inter 1s

listen ingress-router-80
  bind *:80
  mode tcp
  balance source
  server worker1 worker1.CLUSTER_NAME.CLUSTER_DOMAIN:80 check inter 1s
  server worker2 worker2.CLUSTER_NAME.CLUSTER_DOMAIN:80 check inter 1s
  server worker3 worker3.CLUSTER_NAME.CLUSTER_DOMAIN:80 check inter 1s

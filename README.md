# nodemonitorsolana
A complete log file based Solana validator up-time monitoring solution for Zabbix. It consists of the shell script nodemonitor.sh for generating log files on the host and the template zbx_5_template_nodemonitorsolana.xml for the Zabbix 5.0 server.

### Concept

nodemonitor.sh generates human-readable logs that look like:

`
[2020-08-01 02:44:13-04:00] status=validating height=27383265 tFromNow=23 lastVote=27383322 rootBlock=27383268 leaderSlots=56 skippedSlots=3 pctSkipped=5.35 credits=15840625 activeStake=116197.93`
 
`
[2020-08-01 02:44:44-04:00] status=validating height=27383359 tFromNow=29 lastVote=27383400 rootBlock=27383369 leaderSlots=56 skippedSlots=3 pctSkipped=5.35 credits=15840697 activeStake=116197.93`
 
`
[2020-08-01 02:45:15-04:00] status=validating height=27383440 tFromNow=31 lastVote=27383480 rootBlock=27383443 leaderSlots=56 skippedSlots=3 pctSkipped=5.35 credits=15840771 activeStake=116197.93`

For the Zabbix server there is a log module for analyzing log data. The log line entries that are used by the server are:

* **status** can be {scriptstarted | error | delinquent | validating | up} 'error' can have various causes, typically the `solana-validator` process is down. 'up' means the node is confirmed running when the validator metrics are turned off.
* **tfromnow** time in seconds since recent slot height (used for chain halt detection)
* **pctSkipped** percentage of skipped leader slots
* **leaderSlots** number of leader slots
* **activeStake** the active stake

### Installation

The script for the host has a configuration section on top where parameters can be set. Most values are discovered automatically.

A Zabbix server is required that connects to the host running the Solana validator. On the host side the Zabbix agent needs to be installed and configured for active mode. There is various information on the Zabbix site and from other sources that explains how to connect a host to the server and utilize the standard Linux OS templates for general monitoring. Once these steps are completed the Solana Validator template file can be imported. Under `All templates/Template App Solana Validator` there is a `Macros` section with several parameters that can be configured, in particular the path to the log file must be set. Do not change those values there, instead go to `Hosts` and select the particular host, then go to `Macros`, then to `Inherited and host macros`. There the macros from the generic template are mirrored for the specific host and can be set without affecting other hosts using the same template.


### Issues

The Zabbix server is low on resources and a small size VPS is sufficient. However, lags can occur with the log file module. Performance problems with the server are mostly caused by the underlying database slowing down the processing. Database tuning might improve on the issues as well as changing the default Zabbix server parameters for caching etc.

The timestamp from the `solana block-time` call appears to be inaccurate, however it does not affect the purpose of up-time monitoring.

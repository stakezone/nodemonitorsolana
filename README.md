# nodemonitorsolana

Template not yet updated for all new metrics...

A complete log file based Solana validator up-time monitoring solution for Zabbix. It consists of the shell script nodemonitor.sh for generating log files on the host and the template zbx_5_template_nodemonitorsolana.xml for the Zabbix 5.0 server.

### Concept

nodemonitor.sh generates human-readable logs that look like:

`
[2020-12-23 17:29:00-05:00] status=validating height=54509289 tFromNow=25 avgTime=.50 lastVote=54509353 rootSlot=54509295 leaderSlots=912 skippedSlots=189 pctSkipped=20.72 pctTotSkipped=19.94 pctSkippedDerivation=3.91 credits=14229146 activatedStake=57203.20 version=1.4.19 commission=100 pctTotDelinquent=2.80 pctNewerVersions=0 nodes=492 epoch=138 pctEpochElapsed=96.55`
 
`
[2020-12-23 17:30:07-05:00] status=validating height=54509468 tFromNow=28 avgTime=.47 lastVote=54509516 rootSlot=54509473 leaderSlots=912 skippedSlots=189 pctSkipped=20.72 pctTotSkipped=19.94 pctSkippedDerivation=3.91 credits=14229263 activatedStake=57203.20 version=1.4.19 commission=100 pctTotDelinquent=3.01 pctNewerVersions=0 nodes=492 epoch=138 pctEpochElapsed=96.58`
 
`
[2020-12-23 17:31:13-05:00] status=validating height=54509627 tFromNow=28 avgTime=.50 lastVote=54509668 rootSlot=54509631 leaderSlots=912 skippedSlots=189 pctSkipped=20.72 pctTotSkipped=19.94 pctSkippedDerivation=3.91 credits=14229368 activatedStake=57203.20 version=1.4.19 commission=100 pctTotDelinquent=3.01 pctNewerVersions=0 nodes=490 epoch=138 pctEpochElapsed=96.62`

For the Zabbix server there is a log module for analyzing log data. The log line entries that are used by the server are:

* **status** can be {scriptstarted | error | delinquent | validating | up} 'error' can have various causes, typically the `solana-validator` process is down. 'up' means the node is confirmed running when the validator metrics are turned off.
* **tFromNow** time in seconds since recent slot height (used for chain halt detection)
* **avgTime**  average slot time for interval as configured 
* **pctSkipped** percentage of skipped leader slots
* **leaderSlots** number of leader slots
* **pctTotSkipped** percentage of total skipped leader slots for the validator set 
* **pctSkippedDerivation** derivation in percentage of pctSkipped from pctTotSkipped, can be negative (how the node performs in relation to the average)
* **leaderSlots** number of leader slots
* **pctTotDelinquent** percentage of delinquent nodes for the validator set (if high some general problem is likely)
* **pctNewerVersions** percentage of nodes with newer version than this node based on stake (detects need for updating software)

### Installation

The script for the host has a configuration section on top where parameters can be set. Most values are discovered automatically.

A Zabbix server is required that connects to the host running the Solana validator. On the host side the Zabbix agent needs to be installed and configured for active mode. There is various information on the Zabbix site and from other sources that explains how to connect a host to the server and utilize the standard Linux OS templates for general monitoring. Once these steps are completed the Solana Validator template file can be imported. Under `All templates/Template App Solana Validator` there is a `Macros` section with several parameters that can be configured, in particular the path to the log file must be set. Do not change those values there, instead go to `Hosts` and select the particular host, then go to `Macros`, then to `Inherited and host macros`. There the macros from the generic template are mirrored for the specific host and can be set without affecting other hosts using the same template.

More useful modules for GPU and SMART monitoring are available from the Zabbix site.


### Issues

The Zabbix server is low on resources and a small size VPS is sufficient. However, lags can occur with the log file module. Performance problems with the server are mostly caused by the underlying database slowing down the processing. Database tuning might improve on the issues as well as changing the default Zabbix server parameters for caching etc.

Getting the timestamp from the `solana block-time` sometime fails, however it does not affect the purpose of up-time monitoring. Occasionally no `avgTime` value can be calculated.

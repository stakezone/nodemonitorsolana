# nodemonitorsolana
A complete log file based Solana validator up-time monitoring solution for Zabbix. It consists of the shell script nodemonitor.sh for generating log files on the host and the template zbx_5_template_nodemonitorsolana.xml for the Zabbix 5.0 server.

### Concept

nodemonitor.sh generates human-readable logs that look like:

`
[2020-12-22 19:31:00-05:00] status=validating height=56835798 tFromNow=27 avgTime=.49 lastVote=56835847 rootSlot=56835796 leaderSlots=1164 skippedSlots=565 pctSkipped=48.53 pctTotSkipped=33.14 pctSkippedDerivation=46.43 credits=49156695 activatedStake=701168.05 version=1.4.17 commission=0 pctTotDelinquent=4.15 pctVersionActive=84.83 nodes=494 epoch=131 pctEpochElapsed=56.44`
 
`
[2020-12-22 19:32:10-05:00] status=validating height=56835910 tFromNow=45 avgTime=.46 lastVote=56835997 rootSlot=56835905 leaderSlots=1164 skippedSlots=565 pctSkipped=48.53 pctTotSkipped=33.14 pctSkippedDerivation=46.43 credits=49156771 activatedStake=701168.05 version=1.4.17 commission=0 pctTotDelinquent=4.15 pctVersionActive=84.83 nodes=497 epoch=131 pctEpochElapsed=56.48`
 
`
[2020-12-22 19:32:45-05:00] status=validating height=56836022 tFromNow=29 avgTime=.47 lastVote=56836073 rootSlot=56836026 leaderSlots=1168 skippedSlots=569 pctSkipped=48.71 pctTotSkipped=33.14 pctSkippedDerivation=46.98 credits=49156824 activatedStake=701168.05 version=1.4.17 commission=0 pctTotDelinquent=4.12 pctVersionActive=84.83 nodes=493 epoch=131 pctEpochElapsed=56.50`

For the Zabbix server there is a log module for analyzing log data. The log line entries that are used by the server are:

* **status** can be {scriptstarted | error | delinquent | validating | up} 'error' can have various causes, typically the `solana-validator` process is down. 'up' means the node is confirmed running when the validator metrics are turned off.
* **tFromNow** time in seconds since recent slot height (used for chain halt detection)
* **pctSkipped** percentage of skipped leader slots
* **leaderSlots** number of leader slots
* **activeStake** the active stake

### Installation

The script for the host has a configuration section on top where parameters can be set. Most values are discovered automatically.

A Zabbix server is required that connects to the host running the Solana validator. On the host side the Zabbix agent needs to be installed and configured for active mode. There is various information on the Zabbix site and from other sources that explains how to connect a host to the server and utilize the standard Linux OS templates for general monitoring. Once these steps are completed the Solana Validator template file can be imported. Under `All templates/Template App Solana Validator` there is a `Macros` section with several parameters that can be configured, in particular the path to the log file must be set. Do not change those values there, instead go to `Hosts` and select the particular host, then go to `Macros`, then to `Inherited and host macros`. There the macros from the generic template are mirrored for the specific host and can be set without affecting other hosts using the same template.


### Issues

The Zabbix server is low on resources and a small size VPS is sufficient. However, lags can occur with the log file module. Performance problems with the server are mostly caused by the underlying database slowing down the processing. Database tuning might improve on the issues as well as changing the default Zabbix server parameters for caching etc.

The timestamp from the `solana block-time` call appears to be inaccurate, however it does not affect the purpose of up-time monitoring.

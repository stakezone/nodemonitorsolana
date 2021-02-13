# nodemonitorsolana

Please upgrade the Template when using the latest script...

A complete log file based Solana validator uptime monitoring solution for Zabbix. It consists of the shell script nodemonitor.sh for generating log files on the host and the template zbx_5_template_nodemonitorsolana.xml for the Zabbix 5.0 server. Also useful for other monitoring platforms and as a tool.

### Concept

nodemonitor.sh generates human-readable logs that look like:

`
[2020-12-26 19:13:45-05:00] status=validating height=57554659 elapsed=35 behind=36 lastVote=57554703 rootSlot=57554660 leaderSlots=488 skippedSlots=131 pctSkipped=26.84 pctTotSkipped=29.33 pctSkippedDelta=-8.48 pctTotDelinquent=1.68 version=1.4.19 pctNewerVersions=0 balance=278.12 activatedStake=701169.33 credits=49487265 commission=0 avgSlotTime=.48 nodes=499 epoch=133 pctEpochElapsed=22.85`
 
`
[2020-12-26 19:14:50-05:00] status=validating height=57554798 elapsed=26 behind=31 lastVote=57554853 rootSlot=57554803 leaderSlots=488 skippedSlots=131 pctSkipped=26.84 pctTotSkipped=29.34 pctSkippedDelta=-8.52 pctTotDelinquent=1.68 version=1.4.19 pctNewerVersions=0 balance=278.12 activatedStake=701169.33 credits=49487327 commission=0 avgSlotTime=.50 nodes=506 epoch=133 pctEpochElapsed=22.88`
 
`
[2020-12-26 19:15:55-05:00] status=validating height=57554914 elapsed=36 behind=28 lastVote=57554983 rootSlot=57554917 leaderSlots=488 skippedSlots=131 pctSkipped=26.84 pctTotSkipped=29.33 pctSkippedDelta=-8.48 pctTotDelinquent=1.68 version=1.4.19 pctNewerVersions=0 balance=278.12 activatedStake=701169.33 credits=49487408 commission=0 avgSlotTime=.50 nodes=503 epoch=133 pctEpochElapsed=22.91`

The Zabbix agent on the host can process the log data. The log line entries that are imported by the server are:

* **status** can be {scriptstarted | error | delinquent | validating | up} 'error' can have various causes, typically the `solana-validator` process is down. 'up' means the node is confirmed running when the validator metrics are turned off.
* **height** slot height (finalized, confirmed by supermajority)
* **elapsed** time in seconds since slot height (useful for latency or chain halt detection)
* **behind** distance between height and cluster singleGossip height
* **pctSkipped** percentage of skipped leader slots
* **leaderSlots** number of leader slots
* **pctTotSkipped** percentage of total skipped leader slots for the validator set 
* **pctSkippedDelta** percentual derivation of pctSkipped from pctTotSkipped, can be negative if below average (how the node performs in relation to the average)
* **balance** SOL/lamports balance for the identity pubkey
* **activatedStake** the activated stake of this node
* **pctTotDelinquent** percentage of delinquent nodes for the validator set (if high some general problem is likely to be the cause)
* **pctNewerVersions** percentage of nodes with newer version than this node based on stake (detects the requirement for updates)
* **nodes** the number of nodes
* **avgSlotTime** average slot time for the configured interval

### Installation

The script for the host has a configuration section on top where parameters can be set. Most values are discovered automatically. However, setting the identity and vote account addresses manually can enable the script to start even when the rpc server is down.

A Zabbix server is required that connects to the host running the Solana validator. On the host side the Zabbix agent needs to be installed and configured for active mode. There is various information on the Zabbix site and from other sources that explains how to connect a host to the server and utilize the standard Linux OS templates for general monitoring. Once these steps are completed the Solana Validator template file can be imported. Under `All templates/Template App Solana Validator` there is a `Macros` section with several parameters that can be configured, in particular the path to the log file must be set. Do not change those values there, instead go to `Hosts` and select the particular host, then go to `Macros`, then to `Inherited and host macros`. There the macros from the generic template are mirrored for the specific host and can be set without affecting other hosts using the same template.

Additional useful templates for GPU and S.M.A.R.T monitoring are available from the Zabbix site.

### New

'behind' added as a measure of slot distance from the cluster height.

Balances are now checked for the identity pubkey with a related trigger for a low amount.

RPC queries are wrapped with `timeout` in order to prevent any possible deadlock.

### Issues

Getting the timestamp from `solana block-time`sometimes fails causing a `Block Not Found` error. However, it is not a critical value and does only affect `avgSlotTime` calculation, which is not a value used for uptime monitoring.

If suppression of error messages is preferred, start like `./nodemonitor.sh 2> /dev/null`.

If the `ledger/` directory gets deleted several values are only available in the next epoch. However, no essential values for uptime monitoring are affected.

As of time of writing, a cluster can sometimes produce inconsistent timestamps that lead to wrong time calculation causing the `elapsed` time showing large lags.

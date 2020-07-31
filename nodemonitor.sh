#!/bin/bash

#####    Packages required: bc

#####    CONFIG    ##################################################################################################
configDir="$HOME/.config/solana/" # the directory for the config files, eg.: /home/user/.config/solana/
##### optional:        #
validatorChecks="on"   # set to 'on' for obtaining validator metrics
IdentityPubkey=""      # identity pubkey for validator, can be empty when it corresponds to the default keypair pair in config.yml
voteAccount=""         # necessary in case there is more than one vote account per identity pubkey
cli=""                 # auto detection of the solana cli can fail, in case insert like /path/solana 
logname=""             # a custom monitor log file name can be chosen, if left empty default is nodecheck-<username>.log
logpath="$(pwd)"       # the directory where the log file is stored, for customization insert path like: /my/path
logsize=200            # the max number of lines after that the log will be trimmed to reduce its size
sleep1=30s             # polls every sleep1 sec
#####  END CONFIG  ##################################################################################################


if [ -z $configDir ]; then echo "please configure the config directory"; exit 1; fi
keyfile=$(cat ${configDir}cli/config.yml | grep "keypair_path\:" | awk '{print $2}')
cli="$(cat ${configDir}install/config.yml | grep 'active_release_dir\:' | awk '{print $2}')/bin/solana"
if [ -z $IdentityPubkey ]; then IdentityPubkey=$(${installDir}/solana-keygen pubkey $keyfile); fi
if [ -z $IdentityPubkey ]; then echo "please configure the IdentityPubkey in the script"; exit 1; fi
if [ -z  $cli ]; then echo "please configure cli manually or check the configDir"; exit 1; fi

if [ -z $logname ]; then logname="nodemonitor-${USER}.log"; fi
logfile="${logpath}/${logname}"
touch $logfile

echo "log file: ${logfile}"
echo "solana bin: ${cli}"
echo "identity pubkey: ${IdentityPubkey}"
echo ""

validatorCheck=$($cli validators)
if [ $(grep -c $IdentityPubkey <<< $validatorCheck) == 0  ]; then echo "validator not found in set"; exit 1; fi
if [ $(grep -c $IdentityPubkey <<< $validatorCheck) -gt 1  ]; then echo "please configure one of the vote accounts"; exit 1; fi

nloglines=$(wc -l <$logfile)
if [ $nloglines -gt $logsize ]; then sed -i "1,$(expr $nloglines - $logsize)d" $logfile; fi # the log file is trimmed for logsize

date=$(date --rfc-3339=seconds)
echo "[$date] status=scriptstarted chainid=$chainid" >>$logfile

while true; do
    if [ "$validatorChecks" == "on" ]; then
       validatorBlockProduction=$($cli block-production | grep $IdentityPubkey | grep "$voteAccount")
       validatorInfo="a"$($cli validators | grep $IdentityPubkey | grep "$voteAccount") #fix empty space with prefix 'a'
       if [ $(echo $validatorInfo | awk '{print $1}') == "a!" ]; then status=delinquent; else status=active; fi
    fi
    validatorBlockTime=$($cli slot --commitment recent | $cli block-time)
    validatorBlockTimeTest=$(echo $validatorBlockTime | grep -c "Date")
    if [ -n "$validatorInfo" ] && [ "$validatorBlockTimeTest" -eq "1" ]; then
        blockHeight=$(echo $validatorBlockTime | grep "Block:" | awk '{print $2}')
        blockHeightTime=$(echo $validatorBlockTime | grep "UnixTimestamp:" | awk '{print $4}' | sed 's/)/ /g')
        now=$(date --rfc-3339=seconds)
        blockHeightFromNow=$(expr $(date +%s -d "$now") - $(date +%s -d $blockHeightTime))
        logentry="[$now] height=${blockHeight} tFromNow=${blockHeightFromNow}"
        if [ "$validatorChecks" == "on" ]; then
           logentry="$logentry validatorStatus=$status lastVote=$(echo $validatorInfo | awk '{print $5}') rootBlock=$(echo $validatorInfo | awk '{print $6}')"
           if [ $status == "active" ]; then
              leaderSlots=$(echo $validatorBlockProduction | awk '{print $2}')
              skippedSlots=$(echo $validatorBlockProduction | awk '{print $4}')
              pctSkipped=$(echo "scale=2 ; 100 * $skippedSlots / $leaderSlots" | bc)
              logentry="$logentry leaderSlots=$leaderSlots skippedSlots=$skippedSlots pctSkipped=$pctSkipped"
              logentry="$logentry credits=$(echo $validatorInfo | awk '{print $7}') activeStake=$(echo $validatorInfo | awk '{print $8}')"
           fi
        fi
        echo "$logentry" >>$logfile
    else
        now=$(date --rfc-3339=seconds)
        logentry="[$now] status=error"
        echo "$logentry" >>$logfile
    fi

    nloglines=$(wc -l <$logfile)
    if [ $nloglines -gt $logsize ]; then sed -i '1d' $logfile; fi

    echo "$logentry"
    echo "sleep $sleep1"
    sleep $sleep1
done

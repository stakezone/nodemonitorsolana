#!/bin/bash

#####    Packages required: bc

#####    CONFIG    ##################################################################################################
configDir="$HOME/.config/solana/" # the directory for the config files, eg.: /home/user/.config/solana/
voteAccount=""         # vote account for the validator
##### optional:        #
validatorChecks="on"   # set to 'on' for obtaining validator metrics
IdentityPubkey=""      # identity pubkey for validator, insert if auto-discovery fails
cli=""                 # auto detection of the solana cli can fail, in case insert like /path/solana
rpcPort=""             # value of --rpc-port for solana-validator, insert if auto-discovery fails 
logname=""             # a custom monitor log file name can be chosen, if left empty default is nodecheck-<username>.log
logpath="$(pwd)"       # the directory where the log file is stored, for customization insert path like: /my/path
logsize=200            # the max number of lines after that the log will be trimmed to reduce its size
sleep1=30s             # polls every sleep1 sec
#####  END CONFIG  ##################################################################################################


if [ -z $configDir ]; then echo "please configure the config directory"; exit 1; fi
installDir="$(cat ${configDir}install/config.yml | grep 'active_release_dir\:' | awk '{print $2}')/bin"
cli="${installDir}/solana"

if [ -z  $cli ]; then echo "please configure cli manually or check the configDir"; exit 1; fi

if [ -z $rpcPort ]; then rpcPort="http://127.0.0.1:"$(ps aux | grep solana-validator | grep -Po "\-\-rpc\-port\s+\K[0-9]+"); fi
if [ -z $rpcPort ]; then echo "please configure rpcPort"; exit 1; fi

if [ -z $voteAccount ]; then echo "please configure the vote account in the script"; exit 1; fi
if [ -z $IdentityPubkey ]; then IdentityPubkey=$(echo "a"$($cli validators --url $rpcPort | grep "$voteAccount") | awk '{print $2}'); fi #fix empty space with prefix 'a'
if [ -z $IdentityPubkey ]; then echo "please configure the IdentityPubkey in the script"; exit 1; fi

if [ -z $logname ]; then logname="nodemonitor-${USER}.log"; fi
logfile="${logpath}/${logname}"
touch $logfile

echo "log file: ${logfile}"
echo "solana cli: ${cli}"
echo "rpc url: ${rpcPort}"
echo "identity pubkey: ${IdentityPubkey}"
echo ""

validatorCheck=$($cli validators)
if [ $(grep -c $voteAccount <<< $validatorCheck) == 0  ]; then echo "validator not found in set"; exit 1; fi

nloglines=$(wc -l <$logfile)
if [ $nloglines -gt $logsize ]; then sed -i "1,$(expr $nloglines - $logsize)d" $logfile; fi # the log file is trimmed for logsize

date=$(date --rfc-3339=seconds)
echo "[$date] status=scriptstarted" >>$logfile

while true; do
    validatorBlockTime=$($cli slot --commitment recent --url $rpcPort | $cli block-time --url $rpcPort)
    validatorBlockTimeTest=$(echo $validatorBlockTime | grep -c "Date")
    if [ "$validatorChecks" == "on" ]; then
       validatorBlockProduction=$($cli block-production --url $rpcPort | grep "$IdentityPubkey")
echo $validatorBlockProduction
       validatorInfo=$($cli validators --url $rpcPort | grep "$voteAccount")
    fi
    if [[ (-n "$validatorInfo" && "$validatorChecks" == "on")  ]] || [[ ("$validatorBlockTimeTest" -eq "1" && "$validatorChecks" != "on") ]]; then
        validatorInfo="a"$validatorInfo  #fix empty space with prefix 'a'
        status="up"
        blockHeight=$(echo $validatorBlockTime | grep "Block:" | awk '{print $2}')
        blockHeightTime=$(echo $validatorBlockTime | grep "UnixTimestamp:" | awk '{print $6}' | sed 's/)/ /g')
        now=$(date --rfc-3339=seconds)
        #blockHeightFromNow=$(expr $(date +%s -d "$now") - $(date +%s -d $blockHeightTime))
        blockHeightFromNow=$(expr $(date +%s) - $blockHeightTime)
        logentry="height=${blockHeight} tFromNow=${blockHeightFromNow}"
        if [ "$validatorChecks" == "on" ]; then
           if [ $(echo $validatorInfo | awk '{print $1}') == "a!" ]; then status=delinquent; elif [ "$validatorInfo" == "a" ]; then status=error; else status=validating; fi
           logentry="$logentry lastVote=$(echo $validatorInfo | awk '{print $5}') rootBlock=$(echo $validatorInfo | awk '{print $6}')"
           if [ $status == "validating" ]; then
              leaderSlots=$(echo $validatorBlockProduction | awk '{print $2}')
              skippedSlots=$(echo $validatorBlockProduction | awk '{print $4}')
              activeStake=$(echo "scale=2 ; $(echo $validatorInfo | awk '{print $8}') / 1.0" | bc)
              if [ -n "$leaderSlots" ]; then pctSkipped=$(echo "scale=2 ; 100 * $skippedSlots / $leaderSlots" | bc); fi
              logentry="$logentry leaderSlots=$leaderSlots skippedSlots=$skippedSlots pctSkipped=$pctSkipped"
              logentry="$logentry credits=$(echo $validatorInfo | awk '{print $7}') activeStake=$activeStake"
           fi
        fi
        logentry="[$now] status=$status $logentry"
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

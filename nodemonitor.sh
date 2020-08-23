#!/bin/bash

#####    Packages required: jq,bc

#####    CONFIG    ##################################################################################################
configDir="$HOME/.config/solana/" # the directory for the config files, eg.: /home/user/.config/solana/
##### optional:        #
voteAccount=""         # vote account address for the validator
identityPubkey=""      # identity pubkey for validator, insert if auto-discovery fails
validatorChecks="on"   # set to 'on' for obtaining validator metrics
cli=""                 # auto detection of the solana cli can fail, in case insert like /path/solana
rpcPort=""             # value of --rpc-port for solana-validator, insert if auto-discovery fails
logname=""             # a custom monitor log file name can be chosen, if left empty default is nodecheck-<username>.log
logpath="$(pwd)"       # the directory where the log file is stored, for customization insert path like: /my/path
logsize=200            # the max number of lines after that the log will be trimmed to reduce its size
sleep1=30s             # polls every sleep1 sec
#####  END CONFIG  ##################################################################################################


if [ -z $configDir ]; then echo "please configure the config directory"; exit 1; fi
installDir="$(cat ${configDir}install/config.yml | grep 'active_release_dir\:' | awk '{print $2}')/bin"
if [ -z  $installDir ]; then echo "please configure the cli manually or check the configDir setting"; exit 1; fi

if [ -z  $cli ]; then cli="${installDir}/solana"; fi

if [ -z $rpcPort ]; then rpcPort=$(ps aux | grep solana-validator | grep -Po "\-\-rpc\-port\s+\K[0-9]+"); fi
if [ -z $rpcPort ]; then echo "auto-detection failed, please configure the rpcPort"; exit 1; fi
rpcURL="http://127.0.0.1:$rpcPort"

if [ -z $voteAccount ]; then voteAccount=$(ps aux | grep solana-validator | grep -Po "\-\-vote\-account\s+\K\w+"); fi
if [ -z $voteAccount ]; then echo "please configure the vote account in the script"; exit 1; fi
#if [ -z $identityPubkey ]; then identityPubkey=$(echo "a"$($cli validators --url $rpcURL | grep "$voteAccount") | awk '{print $2}'); fi #fix empty space with prefix 'a'
if [ -z $identityPubkey ]; then identityPubkey=$($cli validators --url $rpcURL --output json-compact | jq -r '.currentValidators[] | select(.voteAccountPubkey == '\"$voteAccount\"') | .identityPubkey'); fi
if [ -z $identityPubkey ]; then echo "auto-detection failed, please configure the identityPubkey in the script"; exit 1; fi

if [ -z $logname ]; then logname="nodemonitor-${USER}.log"; fi
logfile="${logpath}/${logname}"
touch $logfile

echo "log file: ${logfile}"
echo "solana cli: ${cli}"
echo "rpc url: ${rpcURL}"
echo "identity pubkey: ${identityPubkey}"
echo "vote account: ${voteAccount}"
echo ""

validatorCheck=$($cli validators)
if [ $(grep -c $voteAccount <<< $validatorCheck) == 0  ]; then echo "validator not found in set"; exit 1; fi

nloglines=$(wc -l <$logfile)
if [ $nloglines -gt $logsize ]; then sed -i "1,$(expr $nloglines - $logsize)d" $logfile; fi # the log file is trimmed for logsize

date=$(date --rfc-3339=seconds)
echo "[$date] status=scriptstarted" >>$logfile

while true; do
    validatorBlockTime=$($cli slot --commitment recent --url  $rpcURL | $cli block-time --url  $rpcURL --output json-compact)
    validatorBlockTimeTest=$(echo $validatorBlockTime | grep -c "timestamp")
    if [ "$validatorChecks" == "on" ]; then
      #validatorBlockProduction=$($cli block-production --url  $rpcURL | grep "$identityPubkey")
       validatorBlockProduction=$($cli block-production --url $rpcURL --output json-compact | jq -r '.leaders[] | select(.identityPubkey == '\"$identityPubkey\"')')
       currentValidatorInfo=$($cli validators --url $rpcURL --output json-compact | jq -r '.currentValidators[] | select(.voteAccountPubkey == '\"$voteAccount\"')')
       delinquentValidatorInfo=$($cli validators --url $rpcURL --output json-compact | jq -r '.delinquentValidators[] | select(.voteAccountPubkey == '\"$voteAccount\"')')
    fi
    if [[ ((-n "$currentValidatorInfo" || "$delinquentValidatorInfo" ) && "$validatorChecks" == "on")  ]] || [[ ("$validatorBlockTimeTest" -eq "1" && "$validatorChecks" != "on") ]]; then
        status="up"
        blockHeight=$(jq -r '.slot' <<<$validatorBlockTime)
        blockHeightTime=$(jq -r '.timestamp' <<<$validatorBlockTime)
        now=$(date --rfc-3339=seconds)
        blockHeightFromNow=$(expr $(date +%s) - $blockHeightTime)
        logentry="height=${blockHeight} tFromNow=${blockHeightFromNow}"
        if [ "$validatorChecks" == "on" ]; then
           if [ -n "$delinquentValidatorInfo" ]; then
              status=delinquent
              activatedStake=$(jq -r '.activatedStake' <<<$delinquentValidatorInfo)
              credits=$(jq -r '.credits' <<<$delinquentValidatorInfo)
              version=$(jq -r '.version' <<<$delinquentValidatorInfo | sed 's/ /-/g')
              commission=$(jq -r '.commission' <<<$delinquentValidatorInfo)
              logentry="$logentry lastVote=$(jq -r '.lastVote' <<<$delinquentValidatorInfo) rootSlot=$(jq -r '.rootSlot' <<<$delinquentValidatorInfo) credits=$credits activatedStake=$activatedStake version=$version commission=$commission"
           elif [ -n "$currentValidatorInfo" ]; then
              status=validating
              activatedStake=$(jq -r '.activatedStake' <<<$currentValidatorInfo)
              credits=$(jq -r '.credits' <<<$currentValidatorInfo)
              version=$(jq -r '.version' <<<$currentValidatorInfo | sed 's/ /-/g')
              commission=$(jq -r '.commission' <<<$currentValidatorInfo)
              logentry="$logentry lastVote=$(jq -r '.lastVote' <<<$currentValidatorInfo) rootSlot=$(jq -r '.rootSlot' <<<$currentValidatorInfo)"
              leaderSlots=$(jq -r '.leaderSlots' <<<$validatorBlockProduction)
              skippedSlots=$(jq -r '.skippedSlots' <<<$validatorBlockProduction)
              activatedStake=$(echo "scale=2 ; $activatedStake / 1.0" | bc)
              if [ -n "$leaderSlots" ]; then pctSkipped=$(echo "scale=2 ; 100 * $skippedSlots / $leaderSlots" | bc); fi
              logentry="$logentry leaderSlots=$leaderSlots skippedSlots=$skippedSlots pctSkipped=$pctSkipped"
              logentry="$logentry credits=$credits activatedStake=$activatedStake version=$version commission=$commission"
           else status=error; fi
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

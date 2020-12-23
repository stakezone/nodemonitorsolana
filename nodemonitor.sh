#!/bin/bash

#####    Packages required: jq, bc

#####    CONFIG    ##################################################################################################
configDir="$HOME/.config/solana/" # the directory for the config files, eg.: /home/user/.config/solana/
##### optional:        #
identityPubkey=""      # identity pubkey for the validator, insert if autodiscovery fails
voteAccount=""         # vote account address for the validator, specify if there are more than one or if autodiscovery fails
sleep1=1m              # polls every sleep1 time interval
slotinterval="100"     # interval of slots for calculating average slot time
validatorChecks="on"   # set to 'on' for obtaining validator metrics
additionalInfo="on"    # set to on for additional general metrics
cli=""                 # auto detection of the solana cli can fail, in case insert like /path/solana
rpcURL=""              # default is localhost with port number autodiscovered, alternatively it can be specified like http://custom.rpc.com:port
format="SOL"           # amounts shown in SOL instead of lamports
logname=""             # a custom monitor log file name can be chosen, if left empty default is nodecheck-<username>.log
logpath="$(pwd)"       # the directory where the log file is stored, for customization insert path like: /my/path
logsize=200            # the max number of lines after that the log will be trimmed to reduce its size
dateprecision="seconds"      # precision for date format, can be seconds or ns (for nano seconds)
#####  END CONFIG  ##################################################################################################


if [ -z $configDir ]; then echo "please configure the config directory"; exit 1; fi
installDir="$(cat ${configDir}install/config.yml | grep 'active_release_dir\:' | awk '{print $2}')/bin"
if [ -z  $installDir ]; then echo "please configure the cli manually or check the configDir setting"; exit 1; fi

if [ -z  $cli ]; then cli="${installDir}/solana"; fi

if [ -z $rpcURL ]; then
   rpcPort=$(ps aux | grep solana-validator | grep -Po "\-\-rpc\-port\s+\K[0-9]+")
   if [ -z $rpcPort ]; then echo "auto-detection failed, please configure the rpcURL"; exit 1; fi
   rpcURL="http://127.0.0.1:$rpcPort"
fi

if [ -z $identityPubkey ]; then identityPubkey=$($cli address --url $rpcURL); fi
if [ -z $identityPubkey ]; then echo "auto-detection failed, please configure the identityPubkey in the script"; exit 1; fi
if [ -z $voteAccount ]; then voteAccount=$($cli validators --url $rpcURL --output json-compact | jq -r '.currentValidators[] | select(.identityPubkey == '\"$identityPubkey\"') | .voteAccountPubkey'); fi
if [ -z $voteAccount ]; then echo "please configure the vote account in the script"; exit 1; fi

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

date=$(date --rfc-3339=$dateprecision)
echo "[$date] status=scriptstarted" >>$logfile

while true; do
    #validatorBlockTime=$($cli slot --commitment recent --url  $rpcURL | $cli block-time --url  $rpcURL --output json-compact)
    validatorBlockTime=$($cli block-time --url $rpcURL --output json-compact)
    validatorBlockTimeTest=$(echo $validatorBlockTime | grep -c "timestamp")
    if [ "$validatorChecks" == "on" ]; then
       blockProduction=$($cli block-production --url $rpcURL --output json-compact)
       validatorBlockProduction=$(jq -r '.leaders[] | select(.identityPubkey == '\"$identityPubkey\"')' <<<$blockProduction)
       validators=$($cli validators --url $rpcURL --output json-compact)
       currentValidatorInfo=$(jq -r '.currentValidators[] | select(.voteAccountPubkey == '\"$voteAccount\"')' <<<$validators)
       delinquentValidatorInfo=$(jq -r '.delinquentValidators[] | select(.voteAccountPubkey == '\"$voteAccount\"')' <<<$validators)
    fi
    if [[ ((-n "$currentValidatorInfo" || "$delinquentValidatorInfo" ) && "$validatorChecks" == "on")  ]] || [[ ("$validatorBlockTimeTest" -eq "1" && "$validatorChecks" != "on") ]]; then
        status="up"
        blockHeight=$(jq -r '.slot' <<<$validatorBlockTime)
        blockHeightTime=$(jq -r '.timestamp' <<<$validatorBlockTime)
        avgBlockTime=$(echo "scale=2 ; $(expr $blockHeightTime - $($cli block-time --url $rpcURL --output json-compact $(expr $blockHeight - $slotinterval) | jq -r '.timestamp')) / $slotinterval" | bc)
        now=$(date --rfc-3339=$dateprecision)
        blockHeightFromNow=$(expr $(date +%s) - $blockHeightTime)
        logentry="height=${blockHeight} tFromNow=${blockHeightFromNow} avgTime=${avgBlockTime}"
        if [ "$validatorChecks" == "on" ]; then
           if [ -n "$delinquentValidatorInfo" ]; then
              status=delinquent
              activatedStake=$(jq -r '.activatedStake' <<<$delinquentValidatorInfo)
              activatedStakeDisplay=$activatedStake
              credits=$(jq -r '.credits' <<<$delinquentValidatorInfo)
              version=$(jq -r '.version' <<<$delinquentValidatorInfo | sed 's/ /-/g')
              commission=$(jq -r '.commission' <<<$delinquentValidatorInfo)
              logentry="$logentry lastVote=$(jq -r '.lastVote' <<<$delinquentValidatorInfo) rootSlot=$(jq -r '.rootSlot' <<<$delinquentValidatorInfo) credits=$credits activatedStake=$activatedStake version=$version commission=$commission"
           elif [ -n "$currentValidatorInfo" ]; then
              status=validating
              activatedStake=$(jq -r '.activatedStake' <<<$currentValidatorInfo)
              activatedStakeDisplay=$activatedStake
              credits=$(jq -r '.credits' <<<$currentValidatorInfo)
              version=$(jq -r '.version' <<<$currentValidatorInfo | sed 's/ /-/g')
              commission=$(jq -r '.commission' <<<$currentValidatorInfo)
              logentry="$logentry lastVote=$(jq -r '.lastVote' <<<$currentValidatorInfo) rootSlot=$(jq -r '.rootSlot' <<<$currentValidatorInfo)"
              leaderSlots=$(jq -r '.leaderSlots' <<<$validatorBlockProduction)
              skippedSlots=$(jq -r '.skippedSlots' <<<$validatorBlockProduction)
              #totalBlocksProduced=$(jq -r '.total_blocks_produced' <<<$blockProduction)
              totalBlocksProduced=$(jq -r '.total_slots' <<<$blockProduction)
              totalSlotsSkipped=$(jq -r '.total_slots_skipped' <<<$blockProduction)
              if [ "$format" == "SOL" ]; then activatedStakeDisplay=$(echo "scale=2 ; $activatedStake / 1000000000.0" | bc); fi
              if [ -n "$leaderSlots" ]; then pctSkipped=$(echo "scale=2 ; 100 * $skippedSlots / $leaderSlots" | bc); fi
              if [ -n "$totalBlocksProduced" ]; then
                 pctTotSkipped=$(echo "scale=2 ; 100 * $totalSlotsSkipped / $totalBlocksProduced" | bc)
                 pctSkippedDerivation=$(echo "scale=2 ; 100 * ($pctSkipped - $pctTotSkipped) / $pctTotSkipped" | bc)
              fi
              logentry="$logentry leaderSlots=$leaderSlots skippedSlots=$skippedSlots pctSkipped=$pctSkipped pctTotSkipped=$pctTotSkipped pctSkippedDerivation=$pctSkippedDerivation"
              logentry="$logentry credits=$credits activatedStake=$activatedStakeDisplay version=$version commission=$commission"
           else status=error; fi
        fi
        if [ "$additionalInfo" == "on" ]; then
           totalActiveStake=$(jq -r '.totalActiveStake' <<<$validators)
           totalDelinquentStake=$(jq -r '.totalDelinquentStake' <<<$validators)
           pctTotDelinquent=$(echo "scale=2 ; 100 * $totalDelinquentStake / $totalActiveStake" | bc)
           #validators=$($cli epoch-info --url $rpcURL --output json-compact)
           #versionActiveStake=$(jq -r '.stakeByVersion.'\"$version\"'.currentActiveStake' <<<$validators)
           stakeByVersion=$(jq -r '.stakeByVersion' <<<$validators)
           stakeByVersion=$(jq -r 'to_entries | map_values(.value + { version: .key })' <<<$stakeByVersion)
           nextVersionIndex=$(expr $(jq -r 'map(.version == '\"$version\"') | index(true)' <<<$stakeByVersion) + 1)
           stakeByVersion=$(jq '.['$nextVersionIndex':]' <<<$stakeByVersion)
           stakeNewerVersions=$(jq -s 'map(.[].currentActiveStake) | add' <<<$stakeByVersion)
           totalCurrentStake=$(jq -r '.totalCurrentStake' <<<$validators)
           #pctVersionActive=$(echo "scale=2 ; 100 * $versionActiveStake / $totalCurrentStake" | bc)
           pctNewerVersions=$(echo "scale=2 ; 100 * $stakeNewerVersions / $totalCurrentStake" | bc)
           nodes=$($cli gossip | grep -Po "Nodes:\s+\K[0-9]+")
           epochInfo=$($cli epoch-info --url $rpcURL --output json-compact)
           epoch=$(jq -r '.epoch' <<<$epochInfo)
           pctEpochElapsed=$(echo "scale=2 ; 100 * $(jq -r '.slotIndex' <<<$epochInfo) / $(jq -r '.slotsInEpoch' <<<$epochInfo)" | bc)
           logentry="$logentry pctTotDelinquent=$pctTotDelinquent pctNewerVersions=$pctNewerVersions nodes=$nodes epoch=$epoch pctEpochElapsed=$pctEpochElapsed"
        fi
        logentry="[$now] status=$status $logentry"
        echo "$logentry" >>$logfile
    else
        now=$(date --rfc-3339=$dateprecision)
        logentry="[$now] status=error"
        echo "$logentry" >>$logfile
    fi
    nloglines=$(wc -l <$logfile)
    if [ $nloglines -gt $logsize ]; then sed -i '1d' $logfile; fi
    echo "$logentry"
    echo "sleep $sleep1"
    sleep $sleep1
done

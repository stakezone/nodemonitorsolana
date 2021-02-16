#!/bin/bash

#set -x # for debugging

###    packages required: jq, bc

###    if suppressing error messages is preferred, run as './nodemonitor.sh 2> /dev/null'

###    CONFIG    ##################################################################################################
configDir=""           # the directory for the config files, eg.: '$HOME/.config/solana'
### optional:          #
identityPubkey=""      # identity pubkey for the validator, insert if autodiscovery fails
voteAccount=""         # vote account address for the validator, specify if there are more than one
sleep1="30"            # polls every sleep1 sec, please use a number value in seconds in order to enable proper interval calculation
slotinterval="$((4 * $sleep1))"     # interval of slots for calculating a meaningful average slot time, can be overridden with static value
validatorChecks="on"   # set to 'on' for obtaining validator metrics, will be autodiscovered to 'off' when flag --no-voting is set
additionalInfo="on"    # set to 'on' for additional general metrics
binDir=""              # auto detection of the solana binary directory can fail or an alternative custom inst>
rpcURL=""              # default is localhost with port number autodiscovered, alternatively it can be specified like 'http://custom.rpc.com:8899'
format="SOL"           # amounts shown in 'SOL' instead of Lamports, when choosing Lamports dependent trigger amounts need to be adjusted
logname=""             # a custom monitor log file name can be chosen, if left empty default is 'nodecheck-<username>.log'
logpath="$(pwd)"       # the directory where the log file is stored, for customization insert path like: '/my/path'
logsize=200            # the max number of lines after that the log gets truncated to reduce its size
dateprecision="seconds"      # precision for date format, can be seconds or ns (for nano seconds)
colorI='\033[0;32m'    # black 30, red 31, green 32, yellow 33, blue 34, magenta 35, cyan 36, white 37
colorD='\033[0;90m'    # for light color 9 instead of 3
colorE='\033[0;31m'    #
colorW='\033[0;33m'    #
noColor='\033[0m'      # no color
###  END CONFIG  ##################################################################################################

if [ -n  "$binDir" ]; then
   cli="timeout --kill-after=10 8 ${binDir}/solana"
else
   if [ -z "$configDir" ]; then echo "please configure the config directory"; exit 1; fi
   installDir="$(cat ${configDir}/install/config.yml | grep 'active_release_dir\:' | awk '{print $2}')/bin"
   if [ -n "$installDir" ]; then cli="${installDir}/solana"; else echo "please configure the cli manually or check the configDir setting"; exit 1; fi
fi

if [ -z "$rpcURL" ]; then
   rpcPort=$(ps aux | grep solana-validator | grep -Po "\-\-rpc\-port\s+\K[0-9]+")
   if [ -z "$rpcPort" ]; then echo "auto-detection failed, please configure the rpcURL"; exit 1; fi
   rpcURL="http://127.0.0.1:$rpcPort"
fi

noVoting=$(ps aux | grep solana-validator | grep -c "\-\-no\-voting")
if [ "$noVoting" -eq 0 ]; then
   if [ -z "$identityPubkey" ]; then identityPubkey=$($cli address --url $rpcURL); fi
   if [ -z "$identityPubkey" ]; then echo "auto-detection failed, please configure the identityPubkey in the script if not done"; exit 1; fi
   if [ -z "$voteAccount" ]; then voteAccount=$($cli validators --url $rpcURL --output json-compact | jq -r '.currentValidators[] | select(.identityPubkey == '\"$identityPubkey\"') | .voteAccountPubkey'); fi
   if [ -z "$voteAccount" ]; then voteAccount=$($cli validators --url $rpcURL --output json-compact | jq -r '.delinquentValidators[] | select(.identityPubkey == '\"$identityPubkey\"') | .voteAccountPubkey'); fi
   if [ -z "$voteAccount" ]; then echo "please configure the vote account in the script or wait for availability upon starting the node"; exit 1; fi
else validatorChecks="off"; fi

if [ -z "$logname" ]; then logname="nodemonitor-${USER}.log"; fi
logfile="${logpath}/${logname}"
touch $logfile

echo "log file: ${logfile}"
echo "solana cli: ${cli}"
echo "rpc url: ${rpcURL}"
echo "identity pubkey: ${identityPubkey}"
echo "vote account: ${voteAccount}"
echo ""

validatorCheck=$($cli validators --url $rpcURL)
if [ $(grep -c $voteAccount <<< $validatorCheck) == 0  ] && [ "$validatorChecks" == "on" ] && [ -z "$identityPubkey" &&  -z "$voteAccount" ]; then echo "validator not found in set"; exit 1; fi

nloglines=$(wc -l <$logfile)
if [ $nloglines -gt $logsize ]; then sed -i "1,$(($nloglines - $logsize))d" $logfile; fi # the log file is trimmed for logsize

date=$(date --rfc-3339=$dateprecision)
echo "[$date] status=scriptstarted" >>$logfile

while true; do
    validatorBlockTime=$($cli block-time --url  $rpcURL --output json-compact $($cli slot --commitment max --url  $rpcURL))
    #validatorBlockTime=$($cli block-time --url $rpcURL --output json-compact)
    validatorBlockTimeTest=$(echo $validatorBlockTime | grep -c "timestamp")
    if [ "$validatorChecks" == "on" ]; then
       blockProduction=$(tail -n1 <<<$($cli block-production --url $rpcURL --output json-compact))
       validatorBlockProduction=$(jq -r '.leaders[] | select(.identityPubkey == '\"$identityPubkey\"')' <<<$blockProduction)
       validators=$($cli validators --url $rpcURL --output json-compact)
       currentValidatorInfo=$(jq -r '.currentValidators[] | select(.voteAccountPubkey == '\"$voteAccount\"')' <<<$validators)
       delinquentValidatorInfo=$(jq -r '.delinquentValidators[] | select(.voteAccountPubkey == '\"$voteAccount\"')' <<<$validators)
    fi
    if [[ ((-n "$currentValidatorInfo" || "$delinquentValidatorInfo" ) && "$validatorChecks" == "on")  ]] || [[ ("$validatorBlockTimeTest" -eq "1" && "$validatorChecks" != "on") ]]; then
        status="up"
        blockHeight=$(jq -r '.slot' <<<$validatorBlockTime)
        blockHeightTime=$(jq -r '.timestamp' <<<$validatorBlockTime)
        #avgBlockTime=$(echo "scale=2 ; $(expr $blockHeightTime - $($cli block-time --url $rpcURL --output json-compact $(expr $blockHeight - $slotinterval) | jq -r '.timestamp')) / $slotinterval" | bc)
        now=$(date --rfc-3339=$dateprecision)
        if [ -n "$blockHeightTime" ]; then elapsed=$(( $(date +%s) - $blockHeightTime)); fi
        logentry="height=${blockHeight} elapsed=$elapsed"
        if [ "$validatorChecks" == "on" ]; then
           if [ -n "$delinquentValidatorInfo" ]; then
              status=delinquent
              slotHeight=$($cli slot --commitment singleGossip) # this should query the cluster
              if [[ -n "$slotHeight" && -n "$blockHeight" ]]; then behind=$(($slotHeight - $blockHeight));else behind=""; fi
              activatedStake=$(jq -r '.activatedStake' <<<$delinquentValidatorInfo)
              activatedStakeDisplay=$activatedStake
              if [ "$format" == "SOL" ]; then activatedStakeDisplay=$(echo "scale=2 ; $activatedStake / 1000000000.0" | bc); fi
              credits=$(jq -r '.credits' <<<$delinquentValidatorInfo)
              version=$(jq -r '.version' <<<$delinquentValidatorInfo | sed 's/ /-/g')
              rootSlot=$(jq -r '.rootSlot' <<<$delinquentValidatorInfo)
              lastVote=$(jq -r '.lastVote' <<<$delinquentValidatorInfo)
              logentry="$logentry behind=$behind rootSlot=$rootSlot lastVote=$lastVote credits=$credits activatedStake=$activatedStakeDisplay version=$version"
           elif [ -n "$currentValidatorInfo" ]; then
              status=validating
              slotHeight=$($cli slot --commitment singleGossip --url $rpcURL)
              if [[ -n "$slotHeight" && -n "$blockHeight" ]]; then behind=$(($slotHeight - $blockHeight));else behind=""; fi
              balance=$($cli account $identityPubkey --url $rpcURL --output json-compact)
              balance=$(jq -r '.account.lamports' <<<$balance)
              activatedStake=$(jq -r '.activatedStake' <<<$currentValidatorInfo)
              activatedStakeDisplay=$activatedStake
              credits=$(jq -r '.credits' <<<$currentValidatorInfo)
              version=$(jq -r '.version' <<<$currentValidatorInfo | sed 's/ /-/g')
              commission=$(jq -r '.commission' <<<$currentValidatorInfo)
              rootSlot=$(jq -r '.rootSlot' <<<$currentValidatorInfo)
              lastVote=$(jq -r '.lastVote' <<<$currentValidatorInfo)
              logentry="$logentry behind=$behind rootSlot=$rootSlot lastVote=$lastVote"
              leaderSlots=$(jq -r '.leaderSlots' <<<$validatorBlockProduction)
              skippedSlots=$(jq -r '.skippedSlots' <<<$validatorBlockProduction)
              #totalBlocksProduced=$(jq -r '.total_blocks_produced' <<<$blockProduction)
              totalBlocksProduced=$(jq -r '.total_slots' <<<$blockProduction)
              totalSlotsSkipped=$(jq -r '.total_slots_skipped' <<<$blockProduction)
              if [ "$format" == "SOL" ]; then
                 activatedStakeDisplay=$(echo "scale=2 ; $activatedStake / 1000000000.0" | bc)
                 balance=$(echo "scale=2 ; $balance / 1000000000.0" | bc)
              fi
              if [ -n "$leaderSlots" ]; then pctSkipped=$(echo "scale=2 ; 100 * $skippedSlots / $leaderSlots" | bc); fi
              if [ -n "$totalBlocksProduced" ]; then
                 pctTotSkipped=$(echo "scale=2 ; 100 * $totalSlotsSkipped / $totalBlocksProduced" | bc)
                 pctSkippedDelta=$(echo "scale=2 ; 100 * ($pctSkipped - $pctTotSkipped) / $pctTotSkipped" | bc)
              fi
              totalActiveStake=$(jq -r '.totalActiveStake' <<<$validators)
              totalDelinquentStake=$(jq -r '.totalDelinquentStake' <<<$validators)
              pctTotDelinquent=$(echo "scale=2 ; 100 * $totalDelinquentStake / $totalActiveStake" | bc)
              #versionActiveStake=$(jq -r '.stakeByVersion.'\"$version\"'.currentActiveStake' <<<$validators)
              stakeByVersion=$(jq -r '.stakeByVersion' <<<$validators)
              stakeByVersion=$(jq -r 'to_entries | map_values(.value + { version: .key })' <<<$stakeByVersion)
              nextVersionIndex=$(( $(jq -r 'map(.version == '\"$version\"') | index(true)' <<<$stakeByVersion) + 1))
              stakeByVersion=$(jq '.['$nextVersionIndex':]' <<<$stakeByVersion)
              stakeNewerVersions=$(jq -s 'map(.[].currentActiveStake) | add' <<<$stakeByVersion)
              totalCurrentStake=$(jq -r '.totalCurrentStake' <<<$validators)
              #pctVersionActive=$(echo "scale=2 ; 100 * $versionActiveStake / $totalCurrentStake" | bc)
              pctNewerVersions=$(echo "scale=2 ; 100 * $stakeNewerVersions / $totalCurrentStake" | bc)
              logentry="$logentry leaderSlots=$leaderSlots skippedSlots=$skippedSlots pctSkipped=$pctSkipped pctTotSkipped=$pctTotSkipped pctSkippedDelta=$pctSkippedDelta pctTotDelinquent=$pctTotDelinquent"
              logentry="$logentry version=$version pctNewerVersions=$pctNewerVersions balance=$balance activatedStake=$activatedStakeDisplay credits=$credits commission=$commission"
           else status=error; fi
        else
           if [ "$elapsed" -gt 80 ]; then entry1="--url $rpcURL"; else entry1=""; fi
           slotHeight=$($cli slot $entry1 --commitment singleGossip)
           if [[ -n "$slotHeight" && -n "$blockHeight" ]]; then behind=$(($slotHeight - $blockHeight));else behind=""; fi
           logentry="$logentry behind=$behind"
        fi
        avgSlotTime=""
        if [ "$additionalInfo" == "on" ]; then
           if [ -n "$blockHeightTime" ]; then
              if [ -n "$blockHeight" ];then slotIntervalTime=$($cli block-time --url $rpcURL --output json-compact $(( $blockHeight - $slotinterval)) | jq -r '.timestamp'); fi
              if [ -n "$slotIntervalTime" ];then avgSlotTime=$(echo "scale=2 ; ($blockHeightTime - $slotIntervalTime) / $slotinterval" | bc); fi
           fi
           nodes=$($cli gossip --url $rpcURL | grep -Po "Nodes:\s+\K[0-9]+")
           epochInfo=$($cli epoch-info --url $rpcURL --output json-compact)
           epoch=$(jq -r '.epoch' <<<$epochInfo)
           pctEpochElapsed=$(echo "scale=2 ; 100 * $(jq -r '.slotIndex' <<<$epochInfo) / $(jq -r '.slotsInEpoch' <<<$epochInfo)" | bc)
           logentry="$logentry avgSlotTime=$avgSlotTime nodes=$nodes epoch=$epoch pctEpochElapsed=$pctEpochElapsed"
        fi
        logentry="[$now] status=$status $logentry"
        echo "$logentry" >>$logfile
    else
        now=$(date --rfc-3339=$dateprecision)
        status="error"
        logentry="[$now] status=$status"
        echo "$logentry" >>$logfile
    fi
    nloglines=$(wc -l <$logfile)
    if [ $nloglines -gt $logsize ]; then sed -i '1d' $logfile; fi
    case $status in
       validating|up)
          color=$colorI
          ;;
       error)
          color=$colorE
          ;;
       delinquent)
          color=$colorW
          ;;
       *)
          color=$noColor
          ;;
    esac
    logentry=$(sed 's/[^ ]*[\=]/'\\${color}'&'\\${noColor}'/g' <<<$logentry)
    echo -e $logentry
    echo -e "${colorD}sleep $sleep1${noColor}"
    sleep $sleep1
done

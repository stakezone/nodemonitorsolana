#!/bin/bash

#set -x # for debugging

###    packages required: jq, bc

###    if suppressing error messages is preferred, run as './nodemonitor.sh 2> /dev/null'

###    CONFIG    ##################################################################################################
CONFIGDIR="$HOME/.config/solana"            # the directory for the config files, eg.: '$HOME/.config/solana'
### optional:           #
IDENTITYPUBKEY=""       # identity pubkey for the validator, insert if autodiscovery fails
VOTEACCOUNT=""          # vote account address for the validator, specify if there are more than one
SLEEP1="30"             # polls every SLEEP1 sec, please use a number value in seconds in order to enable proper interval calculation
VALIDATORCHECKS="on"    # set to 'on' for obtaining validator metrics, will be autodiscovered to 'off' when flag '--no-voting' is set
ADDITIONALMETRICS="on"  # set to 'on' for additional general metrics
GOVERNANCE="off"        # EXPERIMENTAL set to 'on' for governance metrics, might not work with all configurations, spl-token-cli must be installed
BINDIR=""               # auto detection of the solana binary directory can fail, or an alternative custom installation can be specified
RPCURL=""               # default is localhost with port number autodiscovered, alternatively it can be specified like 'http://custom.rpc.com:8899'
FORMAT="SOL"            # amounts shown in 'SOL' instead of 'Lamports', when choosing Lamports dependent trigger amounts need to be adjusted
LOGNAME=""              # a custom monitor log file name can be chosen, if left empty default is 'nodecheck-<username>.log'
LOGPATH="$(pwd)"        # the directory where the log file is stored, for customization insert path like: '/my/path'
LOGSIZE="200"           # the max number of lines after that the log gets truncated to reduce its size
LOGROTATION="1"         # options for log rotation: (1) rotate to $LOGNAME.1 every $LOGSIZE lines;  (2) append to $LOGNAME.1 every $LOGSIZE lines; (3) truncate $logfile to $LOGSIZE every iteration
TIMEFORMAT="-u --rfc-3339=seconds" # date format for log line entries
###  INTERNAL           #
colorI='\033[0;32m'     # black 30, red 31, green 32, yellow 33, blue 34, magenta 35, cyan 36, white 37
colorD='\033[0;90m'     # for light color 9 instead of 3
colorE='\033[0;31m'     #
colorW='\033[0;33m'     #
noColor='\033[0m'       # no color
###  END CONFIG  ##################################################################################################

if [ -n "$BINDIR" ]; then
    cli="timeout -k 8 6 ${BINDIR}/solana"
else
    if [ -z "$CONFIGDIR" ]; then
        echo "please configure the config directory"
        exit 1
    fi
    installDir="$(cat ${CONFIGDIR}/install/config.yml | grep 'active_release_dir\:' | awk '{print $2}')/bin"
    if [ -n "$installDir" ]; then cli="${installDir}/solana"; else
        echo "please configure the cli manually or check the CONFIGDIR setting"
        exit 1
    fi
fi

if [ -z "$RPCURL" ]; then
    rpcPort=$(ps aux | grep solana-validator | grep -Po "\-\-rpc\-port\s+\K[0-9]+")
    if [ -z "$rpcPort" ]; then
        echo "auto-detection failed, please configure the RPCURL"
        exit 1
    fi
    RPCURL="http://127.0.0.1:$rpcPort"
fi

noVoting=$(ps aux | grep solana-validator | grep -c "\-\-no\-voting")
if [ "$noVoting" -eq 0 ]; then
    if [ -z "$IDENTITYPUBKEY" ]; then IDENTITYPUBKEY=$($cli address --url $RPCURL); fi
    if [ -z "$IDENTITYPUBKEY" ]; then
        echo "auto-detection failed, please configure the IDENTITYPUBKEY in the script if not done"
        exit 1
    fi
    if [ -z "$VOTEACCOUNT" ]; then VOTEACCOUNT=$($cli validators --url $RPCURL --output json-compact | jq -r '.currentValidators[] | select(.identityPubkey == '\"$IDENTITYPUBKEY\"') | .voteAccountPubkey'); fi
    if [ -z "$VOTEACCOUNT" ]; then VOTEACCOUNT=$($cli validators --url $RPCURL --output json-compact | jq -r '.delinquentValidators[] | select(.identityPubkey == '\"$IDENTITYPUBKEY\"') | .voteAccountPubkey'); fi
    if [ -z "$VOTEACCOUNT" ]; then
        echo "please configure the vote account in the script or wait for availability upon starting the node"
        exit 1
    fi
else VALIDATORCHECKS="off"; fi

if [ -z "$LOGNAME" ]; then LOGNAME="nodemonitor-${USER}.log"; fi
logfile="${LOGPATH}/${LOGNAME}"
touch $logfile

echo "log file: ${logfile}"
echo "solana cli: ${cli}"
echo "rpc url: ${RPCURL}"
echo "identity pubkey: ${IDENTITYPUBKEY}"
echo "vote account: ${VOTEACCOUNT}"
echo ""

validatorCheck=$($cli validators --url $RPCURL)
if [ $(grep -c $VOTEACCOUNT <<<$validatorCheck) == 0 ] && [ "$VALIDATORCHECKS" == "on" ] && [[ -z "$IDENTITYPUBKEY" && -z "$VOTEACCOUNT" ]]; then
    echo "validator not found in set"
    exit 1
fi

nloglines=$(wc -l <$logfile)
if [ $nloglines -gt $LOGSIZE ]; then sed -i "1,$(($nloglines - $LOGSIZE))d" $logfile; fi # the log file is trimmed for LOGSIZE

date=$(date $TIMEFORMAT)
echo "[$date] status=scriptstarted" >>$logfile

while true; do
    validatorBlockTime=$($cli block-time --url $RPCURL --output json-compact $($cli slot --commitment max --url $RPCURL))
    #validatorBlockTime=$($cli block-time --url $RPCURL --output json-compact)
    validatorBlockTimeTest=$(echo $validatorBlockTime | grep -c "timestamp")
    if [ "$VALIDATORCHECKS" == "on" ]; then
        blockProduction=$(tail -n1 <<<$($cli block-production --url $RPCURL --output json-compact))
        validatorBlockProduction=$(jq -r '.leaders[] | select(.identityPubkey == '\"$IDENTITYPUBKEY\"')' <<<$blockProduction)
        validators=$($cli validators --url $RPCURL --output json-compact)
        #currentValidatorInfo=$(jq -r '.currentValidators[] | select(.voteAccountPubkey == '\"$VOTEACCOUNT\"')' <<<$validators) # pre v1.6.7
        #delinquentValidatorInfo=$(jq -r '.delinquentValidators[] | select(.voteAccountPubkey == '\"$VOTEACCOUNT\"')' <<<$validators) # pre v1.6.7
        validatorInfo=$(jq -r '.validators[]  | select(.voteAccountPubkey == '\"$VOTEACCOUNT\"')' <<<$validators)
        currentValidatorInfo=$(jq -r 'select(.delinquent == 'false')' <<<$validatorInfo)
        delinquentValidatorInfo=$(jq -r 'select(.delinquent == 'true')' <<<$validatorInfo)
    fi
    if [[ (-n "$currentValidatorInfo" || "$delinquentValidatorInfo") && "$VALIDATORCHECKS" == "on" ]] || [[ "$validatorBlockTimeTest" -eq "1" && "$VALIDATORCHECKS" != "on" ]]; then
        status="up"
        blockHeight=$(jq -r '.slot' <<<$validatorBlockTime)
        blockHeightTime=$(jq -r '.timestamp' <<<$validatorBlockTime)
        now=$(date $TIMEFORMAT)
        if [ -n "$blockHeightTime" ]; then elapsed=$(($(date +%s) - $blockHeightTime)); fi
        logentry="height=${blockHeight} elapsed=$elapsed"
        if [ "$VALIDATORCHECKS" == "on" ]; then
            if [ -n "$delinquentValidatorInfo" ]; then
                status=delinquent
                slotHeight=$($cli slot --commitment singleGossip) # this should query the cluster
                if [[ -n "$slotHeight" && -n "$blockHeight" ]]; then behind=$(($slotHeight - $blockHeight)); else behind=""; fi
                activatedStake=$(jq -r '.activatedStake' <<<$delinquentValidatorInfo)
                activatedStakeDisplay=$activatedStake
                if [ "$FORMAT" == "SOL" ]; then activatedStakeDisplay=$(echo "scale=2 ; $activatedStake / 1000000000.0" | bc); fi
                version=$(jq -r '.version' <<<$delinquentValidatorInfo | sed 's/ /-/g')
                rootSlot=$(jq -r '.rootSlot' <<<$delinquentValidatorInfo)
                lastVote=$(jq -r '.lastVote' <<<$delinquentValidatorInfo)
                logentry="$logentry behind=$behind rootSlot=$rootSlot lastVote=$lastVote activatedStake=$activatedStakeDisplay version=$version"
            elif [ -n "$currentValidatorInfo" ]; then
                status=validating
                slotHeight=$($cli slot --commitment singleGossip --url $RPCURL)
                if [[ -n "$slotHeight" && -n "$blockHeight" ]]; then behind=$(($slotHeight - $blockHeight)); else behind=""; fi
                balance=$($cli account $IDENTITYPUBKEY --url $RPCURL --output json-compact)
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
                if [ "$FORMAT" == "SOL" ]; then
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
                stakeByVersion=$(jq -r 'map(if .version == "unknown" then .version="1.0.0" else . end)' <<<$stakeByVersion)
                stakeByVersion=$(jq -r 'sort_by(.version | split(".") | map(tonumber))' <<<$stakeByVersion)
                nextVersionIndex=$(($(jq -r 'map(.version == '\"$version\"') | index(true)' <<<$stakeByVersion) + 1))
                stakeByVersion=$(jq '.['$nextVersionIndex':]' <<<$stakeByVersion)
                stakeNewerVersions=$(jq -s 'map(.[].currentActiveStake) | add' <<<$stakeByVersion)
                totalCurrentStake=$(jq -r '.totalCurrentStake' <<<$validators)
                #pctVersionActive=$(echo "scale=2 ; 100 * $versionActiveStake / $totalCurrentStake" | bc)
                pctNewerVersions=$(echo "scale=2 ; 100 * $stakeNewerVersions / $totalCurrentStake" | bc)
                logentry="$logentry leaderSlots=$leaderSlots skippedSlots=$skippedSlots pctSkipped=$pctSkipped pctTotSkipped=$pctTotSkipped pctSkippedDelta=$pctSkippedDelta pctTotDelinquent=$pctTotDelinquent"
                logentry="$logentry version=$version pctNewerVersions=$pctNewerVersions balance=$balance activatedStake=$activatedStakeDisplay credits=$credits commission=$commission"
                if [ "$GOVERNANCE" == "on" ]; then
                    outstandingVotes=$(spl-token accounts | grep -c "[0-9]\.[0-9]")
                    logentry="$logentry outstandingVotes=$outstandingVotes"
                fi
            else
                status=error
            fi
        else
            if [ "$elapsed" -gt 80 ]; then entry1="--url $RPCURL"; else entry1=""; fi
            slotHeight=$($cli slot $entry1 --commitment singleGossip)
            if [[ -n "$slotHeight" && -n "$blockHeight" ]]; then behind=$(($slotHeight - $blockHeight)); else behind=""; fi
            logentry="$logentry behind=$behind"
        fi
        if [ "$ADDITIONALMETRICS" == "on" ]; then
            nodes=$($cli gossip --url $RPCURL | grep -Po "Nodes:\s+\K[0-9]+") #currently there is no json output from command
            epochInfo=$($cli epoch-info --url $RPCURL --output json-compact)
            epoch=$(jq -r '.epoch' <<<$epochInfo)
            pctEpochElapsed=$(echo "scale=2 ; 100 * $(jq -r '.slotIndex' <<<$epochInfo) / $(jq -r '.slotsInEpoch' <<<$epochInfo)" | bc)
            transactionCount=$($cli transaction-count --url $RPCURL) #currently there is no json output from command
            if [[ -n "$blockHeightTime" && -n "$blockHeightTime_" ]]; then
                if [[ -n "$blockHeight" && -n "$blockHeight_" ]]; then avgSlotTime=$(echo "scale=2 ; ($blockHeightTime - $blockHeightTime_) / ($blockHeight - $blockHeight_)" | bc); fi
                if [[ -n "$transactionCount" && -n "$transactionCount_" ]]; then avgTPS=$(echo "scale=0 ; ($transactionCount - $transactionCount_) / ($blockHeightTime - $blockHeightTime_)" | bc); fi
            fi
            transactionCount_=$transactionCount
            blockHeightTime_=$blockHeightTime
            blockHeight_=$blockHeight
            logentry="$logentry avgSlotTime=$avgSlotTime avgTPS=$avgTPS nodes=$nodes epoch=$epoch pctEpochElapsed=$pctEpochElapsed"
        fi
        variables="status=$status $logentry"
        logentry="[$now] $variables"
        echo "$logentry" >>$logfile
    else
        now=$(date $TIMEFORMAT)
        status="error"
        variables="status=$status"
        logentry="[$now] $variables"
        echo "$logentry" >>$logfile
    fi

    nloglines=$(wc -l <$logfile)
    if [ $nloglines -gt $LOGSIZE ]; then
        case $LOGROTATION in
        1)
            mv $logfile "${logfile}.1"
            touch $logfile
            ;;
        2)
            echo "$(cat $logfile)" >>${logfile}.1
            >$logfile
            ;;
        3)
            sed -i '1d' $logfile
            if [ -f ${logfile}.1 ]; then rm ${logfile}.1; fi # no log rotation with option (3)
            ;;
        *) ;;
        esac
    fi

    case $status in
    validating | up)
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
    echo -e "${colorD}sleep ${SLEEP1}${noColor}"

    variables_=""
    for var in $variables; do
        var_=$(grep -Po '^[0-9a-zA-Z_-]*' <<<$var)
        var_="$var_=\"\""
        variables_="$var_; $variables_"
    done
    #echo $variables_
    eval $variables_

    sleep $SLEEP1
done

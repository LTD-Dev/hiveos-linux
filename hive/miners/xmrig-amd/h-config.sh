#!/usr/bin/env bash

function miner_ver() {
	echo $MINER_LATEST_VER
}


function miner_config_echo() {
	local MINER_VER=`miner_ver`
	miner_echo_config_file "/hive/miners/$MINER_NAME/$MINER_VER/config.json"
}

function miner_config_gen() {

  [[ -z $XMRIG_PASS ]] && XMRIG_PASS="x"

	local MINER_CONFIG="$MINER_DIR/$MINER_VER/config.json"
	mkfile_from_symlink $MINER_CONFIG

	conf=`cat $MINER_DIR/$MINER_VER/config_global.json | envsubst`

		if [[ ! -z ${XMRIG_ALGO} ]]; then
	algo=${XMRIG_ALGO}
	#translate CUSTOM_ALGO to a view clear for miner
	# 	case ${XMRIG_ALGO} in
	# 		"cryptonight-lite-v7" )
	# 			algo="cryptonight-lite"
	# 		;;
	# 		* )
	# 		algo=${XMRIG_ALGO}
	# 		;;
	# 	esac
		algo=`jq --null-input --arg algo "$algo" '{$algo}'`
		conf=$(jq -s '.[0] * .[1]' <<< "$conf $algo")
	fi

	#merge user config options into main config
	if [[ ! -z $XMRIG_USER_CONFIG ]]; then
		while read -r line; do
			[[ -z $line ]] && continue
				conf=$(jq -s '.[0] * .[1]' <<< "$conf {$line}")
		done <<< "$XMRIG_USER_CONFIG"
	fi

	[[ -z $conf || $conf == '[]' || $conf == 'null' ]] && echo -e "${RED}Error in \"Extra config arguments\" value, check your Miner Config please.${NOCOLOR}" && exit 1

	#add api port to main config
	port=$MINER_API_PORT
	port=`jq --null-input --arg port "$port" '{$port}'`
	api=$(jq -s '.[0].api * .[1]' <<< "$conf $port")
	api=`jq --null-input --argjson api "$api" '{"api": $api}'`
	conf=$(jq -s '.[0] * .[1]' <<< "$conf $api")

	#merge pools into main config
	pools='[]'
	tls=$(jq -r .tls <<< "$conf")
	[[ -z $tls || $tls == "null" ]] && tls="false"
	tls_fp=$(jq -r '."tls-fingerprint"' <<< "$conf")
	[[ -z $tls_fp || $tls_fp == "null" ]] && tls_fp="null"
	variant=$(jq -r '."variant"' <<< "$conf")
	[[ -z $variant= || $variant= == "null" ]] && variant=-1
	rig_id=$(jq -r '."rig_id"' <<< "$conf")
	[[ -z $rig_id= || $rig_id= == "null" ]] && rig_id=""
	for url in $XMRIG_URL; do
		grep -q "nicehash.com" <<< $XMRIG_URL
		[[ $? -eq 0 ]] && nicehash="true" || nicehash="false"
		pool=$(cat <<EOF
					{"url": "$url", "user": "$XMRIG_TEMPLATE", "pass": "$XMRIG_PASS", "rig_id": "$rig_id", "use_nicehash": $nicehash, "tls": $tls, "tls-fingerprint": $tls_fp, "variant": $variant, "keepalive": true }
EOF
)
		pools=`jq --null-input --argjson pools "$pools" --argjson pool "$pool" '$pools + [$pool]'`
	done

	if [[ -z $pools || $pools == '[]' || $pools == 'null' ]]; then
		echo -e "${RED}No pools configured, using default${NOCOLOR}"
	else
		pools=`jq --null-input --argjson pools "$pools" '{"pools": $pools}'`
		conf=$(jq -s '.[0] * .[1]' <<< "$conf $pools")
	fi

	[[ -z $conf || $conf == '[]' || $conf == 'null' ]] && echo -e "${RED}Error in \"Pool URL\" value, check your Miner Config please.${NOCOLOR}" && exit 1

	#merge GPU settings into main config
	if [[ -z $XMRIG_THREADS || $XMRIG_THREADS == '[]' || $XMRIG_THREADS == 'null' ]]; then
		echo -e "${YELLOW}CUSTOM_GPU_CONFIG is empty, useing autoconfig${NOCOLOR}"
	else
		threads=$XMRIG_THREADS
		threads=`jq --null-input --argjson threads "$threads" '{"threads": $threads}'`
		conf=$(jq -s '.[0] * .[1]' <<< "$conf $threads")
	fi

	[[ -z $conf || $conf == '[]' || $conf == 'null' ]] && echo -e "${RED}Error in \"GPU settings\" value, check your Miner Config please.${NOCOLOR}" && exit 1

	#pass can also contain %var%
	#Don't remove until Hive 1 is gone
	[[ ! -z $EWAL ]] && conf=$(sed "s/%EWAL%/$EWAL/g" <<< $conf) #|| echo "${RED}EWAL not set${NOCOLOR}"
	[[ ! -z $DWAL ]] && conf=$(sed "s/%DWAL%/$DWAL/g" <<< $conf) #|| echo "${RED}DWAL not set${NOCOLOR}"
	[[ ! -z $ZWAL ]] && conf=$(sed "s/%ZWAL%/$ZWAL/g" <<< $conf) #|| echo "${RED}ZWAL not set${NOCOLOR}"
	[[ ! -z $EMAIL ]] && conf=$(sed "s/%EMAIL%/$EMAIL/g" <<< $conf)
	[[ ! -z $WORKER_NAME ]] && conf=$(sed "s/%WORKER_NAME%/$WORKER_NAME/g" <<< $conf) #|| echo "${RED}WORKER_NAME not set${NOCOLOR}"

	echo $conf | jq . > $MINER_CONFIG
}
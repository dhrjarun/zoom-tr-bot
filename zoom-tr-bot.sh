#!/bin/bash

tbot_image="zoom_tbot"

mkdir -p logs

call_dataroom_webhook() {
  echo "Calling dataroom webhook"
}


validate_bot_id() {
    local bot_id=$1
    if [[ $bot_id =~ ^[a-zA-Z0-9]([a-zA-Z0-9_-]*[a-zA-Z0-9])?$ ]]; then
        return 0
    else
        return 1
    fi
}

container_exists() {
    docker ps -aq -f name=$1
}

run_container() {
    docker run -d --name $bot_id  \
    -v $(pwd)/$config_file_name:/app/config.toml \
    -e PAD_ID=$pad_id \
    -e PAD_SECRET=$pad_secret \
    -e DATAROOM_WEBHOOK_URL=$dataroom_webhook_url \
    -e DATAROOM_WEBHOOK_SECRET=$dataroom_webhook_secret \
    $tbot_image
}

validate_with_other_bots() {
    # Check for duplicate client_id or meeting details in other config files
    for other_config_file in config.*.toml; do
        if [ -f "$other_config_file" ]; then
            other_bot_id=$(basename "$other_config_file" | cut -d'.' -f2)
            other_client_id=$(grep "^client-id" "$other_config_file" | cut -d'"' -f2)
            other_join_url=$(grep "^join-url" "$other_config_file" | cut -d'"' -f2)
            other_meeting_id=$(grep "^meeting-id" "$other_config_file" | cut -d'"' -f2)

            if ! [ container_exists $other_bot_id ]; then
              rm "$other_config_file"
              continue
            fi

            if [ "$other_bot_id" = "$bot_id" ]; then
                echo "Error: There is already a bot with id $other_bot_id"
                exit 1
            fi

            if [ "$other_client_id" = "$client_id" ] && [ ! -z "$client_id" ]; then
                echo "Error: There is already a bot $other_bot_id with client_id $client_id"
                exit 1
            fi

            if [ "$other_join_url" = "$join_url" ] && [ ! -z "$join_url" ]; then
                echo "Error: There is already a bot $other_bot_id joined in meeting $join_url"
                exit 1
            fi

            if [ "$other_meeting_id" = "$meeting_id" ] && [ ! -z "$meeting_id" ]; then
                echo "Error: There is already a bot $other_bot_id joined in meeting $meeting_id"
                exit 1
            fi
        fi
    done
}

handle_start() {
    config_file=${ZOOM_TBOT_CONFIG:-config.toml}

    while [ $# -gt 0 ]; do
        case "$1" in
            --join-url)
                join_url="$2"
                shift 2
                ;;
            --meeting-id)
                meeting_id="$2"
                shift 2
                ;;
            --meeting-password)
                meeting_password="$2"
                shift 2
                ;;
            --client-id)
                client_id="$2"
                shift 2
                ;;
            --client-secret)
                client_secret="$2"
                shift 2
                ;;
            --dataroom-webhook-url)
                dataroom_webhook_url="$2"
                shift 2
                ;;
            --dataroom-webhook-secret)
                dataroom_webhook_secret="$2"
                shift 2
                ;;
            --pad-id)
                pad_id="$2"
                shift 2
                ;;
            --pad-secret)
                pad_secret="$2"
                shift 2
                ;;
            --display-name)
                display_name="$2"
                shift 2
                ;;
            --config)
                if [ -f "$2" ]; then
                config_file="$2"
                  shift 2
                else
                  echo "Error: config file $2 does not exist"
                  exit 1
                fi
                ;;
            *)
                if [[ $1 =~ ^-- ]]; then
                  echo "Unknown option: $1"
                  exit 1
                fi

                if [ validate_bot_id $1 ]; then
                  bot_id="$1"
                  shift 1
                else
                  echo "Error: bot-id can only contain letters, numbers, underscore (_) or hyphen (-)"
                  exit 1
                fi
                ;;
        esac
    done

    if [ -f "$config_file" ]; then
      config_display_name=$(grep "^display-name" $config_file | cut -d'"' -f2)
      config_client_id=$(grep "^client-id" $config_file | cut -d'"' -f2)
      config_client_secret=$(grep "^client-secret" $config_file | cut -d'"' -f2)
      config_pad_id=$(grep "^pad-id" $config_file | cut -d'"' -f2)
      config_pad_secret=$(grep "^pad-secret" $config_file | cut -d'"' -f2)
      config_dataroom_webhook_url=$(grep "^dataroom-webhook-url" $config_file | cut -d'"' -f2)
      config_dataroom_webhook_secret=$(grep "^dataroom-webhook-secret" $config_file | cut -d'"' -f2)
      config_join_url=$(grep "^join-url" $config_file | cut -d'"' -f2)
      config_meeting_id=$(grep "^meeting-id" $config_file | cut -d'"' -f2)
      config_meeting_password=$(grep "^meeting-password" $config_file | cut -d'"' -f2)

      display_name=${config_display_name:-${ZOOM_TBOT_DISPLAY_NAME:-}}
      client_id=${config_client_id:-${ZOOM_TBOT_CLIENT_ID:-}}
      client_secret=${config_client_secret:-${ZOOM_TBOT_CLIENT_SECRET:-}}
      pad_id=${config_pad_id:-${ZOOM_TBOT_PAD_ID:-}}
      pad_secret=${config_pad_secret:-${ZOOM_TBOT_PAD_SECRET:-}}
      dataroom_webhook_url=${config_dataroom_webhook_url:-${ZOOM_TBOT_DATAROOM_WEBHOOK_URL:-}}
      dataroom_webhook_secret=${config_dataroom_webhook_secret:-${ZOOM_TBOT_DATAROOM_WEBHOOK_SECRET:-}}
      join_url=${config_join_url:-}
      meeting_id=${config_meeting_id:-}
      meeting_password=${config_meeting_password:-}
    fi

    if [ -z "$client_id" ] || [ -z "$client_secret" ] || [ -z "$pad_secret" ]; then
        echo "Error: client-id, client-secret, and pad-secret are required"
        exit 1
    fi

    if [ ! validate_bot_id $bot_id ]; then
      echo "Error: bot-id can only contain letters, numbers, underscore (_) or hyphen (-)"
      exit 1
    fi

    # prompt bot_id
    while [ -z "$bot_id" ]; do
      default_bot_id=$(date +%s)
      read -p "Enter Bot Id(${default_bot_id}): " bot_id
      if [ -z "$bot_id" ]; then
        bot_id=$default_bot_id
      fi

      if ! validate_bot_id "$bot_id"; then
        echo "Invalid Bot id, it can only contain letters, numbers, underscore (_) or hyphen (-)"
        bot_id=""
        continue
      fi
    done

    # prompt join_url or meeting_id & meeting_password
    if [ -z "$join_url" ] && ([ -z "$meeting_id" ] || [ -z "$meeting_password" ]); then
        while [ -z "$join_url_or_meeting_id" ]; do
            read -p "Enter Join URL or Meeting ID: " join_url_or_meeting_id
            if [ -z "$join_url_or_meeting_id" ]; then
                echo "Join URL or Meeting ID is required, try again"
                continue
            fi
        done

        if [[ $join_url_or_meeting_id =~ ^https?:// ]]; then
            join_url=$join_url_or_meeting_id
        else
            meeting_id=$join_url_or_meeting_id
            while [ -z "$meeting_password" ]; do
                read -p "Enter Meeting Password: " meeting_password
                if [ -z "$meeting_password" ]; then
                    echo "Meeting password is required, try again"
                    continue
                fi
            done
        fi
    fi

    # prompt pad_id
    while [ -z "$pad_id" ]; do
      read -p "Enter Pad ID: " pad_id
      if [ -z "$pad_id" ]; then
        echo "pad-id is required, try again"
        continue
      fi

      pad_id=$pad_id
    done

    validate_with_other_bots

    # create a new config.toml file
    config_file_name="config.${bot_id}.toml"
    touch $config_file_name

    # write the config.toml file
    echo "
client-id=\"$client_id\"
client-secret=\"$client_secret\"
display-name=\"$display_name\"
" > $config_file_name

    if [ -n "$join_url" ]; then
        echo "join-url=\"$join_url\"" >> $config_file_name
    else
        echo "meeting-id=\"$meeting_id\"" >> $config_file_name
        echo "meeting-password=\"$meeting_password\"" >> $config_file_name
    fi

    echo "
[RawAudio]
file=\"meeting-audio.pcm\"
" >> $config_file_name

    if ! run_container; then
        rm "$config_file_name"
        echo "Failed to start container"
        exit 1
    fi


    docker logs -f $bot_id &> logs/$bot_id.log &
    call_dataroom_webhook 'started' $bot_id
}

handle_stop() {
    bot_id=$1

    if [ -z "$bot_id" ]; then
        echo "Error: bot-id is required"
        echo "Usage: $0 stop BOT_ID"
        exit 1
    fi

    # Validate bot_id format
    if ! [ $(validate_bot_id $bot_id) ]; then
        echo "Error: bot-id can only contain letters, numbers, underscore (_) or hyphen (-)"
        exit 1
    fi

     # Remove the config file
    config_file="config.${bot_id}.toml"
    if [ -f "$config_file" ]; then
        rm "$config_file"
    fi

    # Check if container exists
    if ! [ $(container_exists $bot_id) ]; then
        echo "Error: No container found with bot-id $bot_id"
        exit 1
    fi

    # Stop and remove the container
    docker stop $bot_id
    docker rm $bot_id

    call_dataroom_webhook 'stopped' $bot_id
}

handle_list() {
    docker ps --filter "ancestor=${tbot_image}" --format "table {{.Names}}\t{{.Status}}"
}

case "$1" in
    start)
        shift
        handle_start "$@"
        ;;
    stop)
        shift
        handle_stop "$@"
        ;;
    list)
        handle_list
        ;;
    *)
        echo "Usage: $0 {start|stop|list} [options]"
        exit 1
        ;;
esac

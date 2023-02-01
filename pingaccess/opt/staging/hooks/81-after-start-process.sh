#!/usr/bin/env sh
# shellcheck source=../../../../pingcommon/opt/staging/hooks/pingcommon.lib.sh
. "${HOOKS_DIR}/pingcommon.lib.sh"

pingaccess_private_hostname=${PA_CONSOLE_HOST}
test -n "${PA_ADMIN_PRIVATE_HOSTNAME}" && pingaccess_private_hostname=${PA_ADMIN_PRIVATE_HOSTNAME}

pingaccess_private_port=${PA_ADMIN_PORT}
test -n "${PA_ADMIN_PRIVATE_PORT_HTTPS}" && pingaccess_private_port=${PA_ADMIN_PRIVATE_PORT_HTTPS}

pingaccess_api_out=$(mktemp)

# Attempt to update the administrator password from the default password
# This does nothing if the password has already been changed
run_hook "83-change-password.sh"

echo "Checking for data.json to import.."
if test -f "${STAGING_DIR}/instance/data/data.json"; then
    if test -f "${STAGING_DIR}/instance/conf/pa.jwk"; then
        if test -f "${STAGING_DIR}/instance/data/PingAccess.mv.db"; then
            echo "INFO: file named /instance/data/data.json found and will overwrite /instance/data/PingAccess.mv.db"
        else
            echo "INFO: file named /instance/data/data.json found"
        fi
        run_hook "85-import-configuration.sh"
    else
        echo "WARNING: instance/data/data.json found, but no /instance/conf/pa.jwk found"
        echo "WARNING: skipping import."
    fi
else
    # If no profile is provided through a data.json file, configure a default PingAccess cluster
    echo "INFO: No file named /instance/data/data.json found, skipping import."

    # Only configure default PingAccess cluster on the CLUSTERED_CONSOLE node.
    if test "${OPERATIONAL_MODE}" = "CLUSTERED_CONSOLE"; then
        # Only configure default PingAccess cluster when starting the container for the first time.
        if test "${RUN_PLAN}" = "START"; then
            echo "INFO: Configuring Default PingAccess Cluster"
            _basePaURL="https://localhost:${pingaccess_private_port}/pa-admin-api/v3"
            _keypairURL="${_basePaURL}/keyPairs/generate"

            # Create Keypair
            echo "INFO: Creating keypair for ${pingaccess_private_hostname}."
            https_result_code=$(
                curl \
                    --insecure \
                    --silent \
                    --request POST \
                    --user "${ROOT_USER}:${PING_IDENTITY_PASSWORD}" \
                    --header "X-Xsrf-Header: PingAccess" \
                    --output "${pingaccess_api_out}" \
                    --write-out '%{http_code}' \
                    --data '{"alias": "DEFAULT_CERT",
                            "commonName": "'"${pingaccess_private_hostname}"'",
                            "country": "US",
                            "keyAlgorithm": "RSA",
                            "keySize": "2048",
                            "organization": "Ping Identity",
                            "subjectAlternativeNames": [{"name": "dNSName", "value": "'"${pingaccess_private_hostname}"'"}],
                            "validDays": "365"}' \
                    "${_keypairURL}"
            )

            if test "${https_result_code}" = "200"; then
                key_pair_id=$(jq -r '.id' "${pingaccess_api_out}")
            else
                cat "${pingaccess_api_out}"
                container_failure "${https_result_code}" "Failure to create Keypair"
            fi

            # Assign HTTPS Listeners
            echo "INFO: Assigning ADMIN HTTPS listener to keypairID ${key_pair_id}."
            _httpsListenersURL="${_basePaURL}/httpsListeners"
            https_result_code=$(
                curl \
                    --insecure \
                    --silent \
                    --request PUT \
                    --user "${ROOT_USER}:${PING_IDENTITY_PASSWORD}" \
                    --header "X-Xsrf-Header: PingAccess" \
                    --write-out '%{http_code}' \
                    --output "${pingaccess_api_out}" \
                    --data '{"keyPairId": "'"${key_pair_id}"'", "name": "ADMIN", "restartRequired": "false"}' \
                    "${_httpsListenersURL}/1"
            )

            if test "${https_result_code}" != "200"; then
                cat "${pingaccess_api_out}"
                container_failure "${https_result_code}" "Failure to assign ADMIN HTTPS Listener"
            fi

            echo "INFO: Assigning ENGINE HTTPS listener to keypairID ${key_pair_id}."
            https_result_code=$(
                curl \
                    --insecure \
                    --silent \
                    --request PUT \
                    --user "${ROOT_USER}:${PING_IDENTITY_PASSWORD}" \
                    --header "X-Xsrf-Header: PingAccess" \
                    --write-out '%{http_code}' \
                    --output "${pingaccess_api_out}" \
                    --data '{"keyPairId": "'"${key_pair_id}"'", "name": "ENGINE", "restartRequired": "false"}' \
                    "${_httpsListenersURL}/2"
            )

            if test "${https_result_code}" != "200"; then
                cat "${pingaccess_api_out}"
                container_failure "${https_result_code}" "Failure to assign ENGINE HTTPS Listener"
            fi

            echo "INFO: Assigning AGENT HTTPS listener to keypairID ${key_pair_id}."
            https_result_code=$(
                curl \
                    --insecure \
                    --silent \
                    --request PUT \
                    --user "${ROOT_USER}:${PING_IDENTITY_PASSWORD}" \
                    --header "X-Xsrf-Header: PingAccess" \
                    --write-out '%{http_code}' \
                    --output "${pingaccess_api_out}" \
                    --data '{"keyPairId": "'"${key_pair_id}"'", "name": "AGENT", "restartRequired": "false"}' \
                    "${_httpsListenersURL}/3"
            )

            if test "${https_result_code}" != "200"; then
                cat "${pingaccess_api_out}"
                container_failure "${https_result_code}" "Failure to assign AGENT HTTPS Listener"
            fi

            echo "INFO: Assigning CONFIG QUERY HTTPS listener to keypairID ${key_pair_id}."
            https_result_code=$(
                curl \
                    --insecure \
                    --silent \
                    --request PUT \
                    --user "${ROOT_USER}:${PING_IDENTITY_PASSWORD}" \
                    --header "X-Xsrf-Header: PingAccess" \
                    --write-out '%{http_code}' \
                    --output "${pingaccess_api_out}" \
                    --data '{"keyPairId": "'"${key_pair_id}"'", "name": "CONFIG QUERY", "restartRequired": "false"}' \
                    "${_httpsListenersURL}/4"
            )

            if test "${https_result_code}" != "200"; then
                cat "${pingaccess_api_out}"
                container_failure "${https_result_code} Failure to assign CONFIG QUERY HTTPS Listener"
            fi

            echo "INFO: Assigning SIDEBAND HTTPS listener to keypairID ${key_pair_id}."
            https_result_code=$(
                curl \
                    --insecure \
                    --silent \
                    --request PUT \
                    --user "${ROOT_USER}:${PING_IDENTITY_PASSWORD}" \
                    --header "X-Xsrf-Header: PingAccess" \
                    --write-out '%{http_code}' \
                    --output "${pingaccess_api_out}" \
                    --data '{"keyPairId": "'"${key_pair_id}"'", "name": "SIDEBAND", "restartRequired": "false"}' \
                    "${_httpsListenersURL}/5"
            )

            if test "${https_result_code}" != "200"; then
                cat "${pingaccess_api_out}"
                container_failure "${https_result_code}" "Failure to assign SIDEBAND HTTPS Listener"
            fi

            # Update Administrative Node Host
            adminNodesHost="${pingaccess_private_hostname}:${PA_ADMIN_PRIVATE_PORT_CLUSTERCONFIG}"
            echo "INFO: Setting administrative node ${adminNodesHost}"
            _adminNodeHostURL="${_basePaURL}/adminConfig"

            https_result_code=$(
                curl \
                    --insecure \
                    --silent \
                    --request PUT \
                    --user "${ROOT_USER}:${PING_IDENTITY_PASSWORD}" \
                    --header "X-Xsrf-Header: PingAccess" \
                    --write-out '%{http_code}' \
                    --output "${pingaccess_api_out}" \
                    --data '{"hostPort":"'"${adminNodesHost}"'"}' \
                    "${_adminNodeHostURL}"
            )

            if test "${https_result_code}" != "200"; then
                cat "${pingaccess_api_out}"
                container_failure "${https_result_code}" "Failure to update the Administrative Node Host"
            fi
        else
            # On any other run plan, do not configure the default PingAccess cluster
            echo "INFO: Run plan = ${RUN_PLAN}. Skipping configuration of default PingAccess cluster"
        fi
    fi
fi

rm -f "${pingaccess_api_out}"

exit 0

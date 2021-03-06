#!/bin/bash

set -eu

export ROOT_DIR=`pwd`
source $ROOT_DIR/nsx-t-ci-pipeline/functions/copy_binaries.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_versions.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/generate_cert.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/yaml2json.sh
source $ROOT_DIR/nsx-t-ci-pipeline/functions/check_null_variables.sh

check_bosh_version
check_available_product_version "pivotal-container-service"

if [ -z "$PKS_SSL_CERT"  -o  "null" == "$PKS_SSL_CERT" ]; then
  domains=(
    "*.${PKS_SYSTEM_DOMAIN}"
    "*.api.${PKS_SYSTEM_DOMAIN}"
    "*.uaa.${PKS_SYSTEM_DOMAIN}"
  )

  certificates=$(generate_cert "${domains[*]}")
  export PKS_SSL_CERT=`echo $certificates | jq --raw-output '.certificate'`
  export PKS_SSL_PRIVATE_KEY=`echo $certificates | jq --raw-output '.key'`
fi


om-linux \
    -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
    -u $OPSMAN_USERNAME \
    -p $OPSMAN_PASSWORD \
    -k stage-product \
    -p $PRODUCT_NAME \
    -v $PRODUCT_VERSION

check_staged_product_guid "pivotal-container-service-"

pks_network=$(
  jq -n \
    --arg pks_deployment_network_name "$PKS_DEPLOYMENT_NETWORK_NAME" \
    --arg pks_cluster_service_network_name "$PKS_CLUSTER_SERVICE_NETWORK_NAME" \
    --arg other_azs "$PKS_NW_AZS" \
    --arg singleton_az "$PKS_SINGLETON_JOB_AZ" \
    '
    {
      "network": {
        "name": $pks_deployment_network_name
      },
      "service_network": {
        "name": $pks_cluster_service_network_name
      },
      "other_availability_zones": ($other_azs | split(",") | map({name: .})),
      "singleton_availability_zone": {
        "name": $singleton_az
      }
    }
   '
)

om-linux \
  -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  -u $OPSMAN_USERNAME \
  -p $OPSMAN_PASSWORD \
  --skip-ssl-validation \
  configure-product \
  --product-name pivotal-container-service \
  --product-network "$pks_network"

echo "Finished configuring network properties"

  pks_syslog_properties=$(
    jq -n \
    --arg pks_syslog_migration_enabled "$PKS_SYSLOG_MIGRATION_ENABLED" \
    --arg pks_syslog_address "$PKS_SYSLOG_ADDRESS" \
    --arg pks_syslog_port "$PKS_SYSLOG_PORT" \
    --arg pks_syslog_transport_protocol "$PKS_SYSLOG_TRANSPORT_PROTOCOL" \
    --arg pks_syslog_tls_enabled "$PKS_SYSLOG_TLS_ENABLED" \
    --arg pks_syslog_peer "$PKS_SYSLOG_PEER" \
    --arg pks_syslog_ca_cert "$PKS_SYSLOG_CA_CERT" \
      '

      # Syslog
      if $pks_syslog_migration_enabled == "enabled" then
        {
          ".properties.syslog_migration_selector.enabled.address": {
            "value": $pks_syslog_address
          },
          ".properties.syslog_migration_selector.enabled.port": {
            "value": $pks_syslog_port
          },
          ".properties.syslog_migration_selector.enabled.transport_protocol": {
            "value": $pks_syslog_transport_protocol
          },
          ".properties.syslog_migration_selector.enabled.tls_enabled": {
            "value": $pks_syslog_tls_enabled
          },
          ".properties.syslog_migration_selector.enabled.permitted_peer": {
            "value": $pks_syslog_peer
          },
          ".properties.syslog_migration_selector.enabled.ca_cert": {
            "value": $pks_syslog_ca_cert
          }
        }
      else
        {
          ".properties.syslog_migration_selector": {
            "value": "disabled"
          }
        }
      end
      '
  )


om-linux \
  -t https://$OPSMAN_DOMAIN_OR_IP_ADDRESS \
  -u $OPSMAN_USERNAME \
  -p $OPSMAN_PASSWORD \
  --skip-ssl-validation \
  configure-product \
  --product-name pivotal-container-service \
  --product-properties "$pks_syslog_properties"
echo "Finished configuring syslog properties"

# Check if product is older 1.0 or not
if [[ "$PRODUCT_VERSION" =~ ^1.0 ]]; then
  product_version=1.0
  echo ""
  echo "Starting configuration of PKS v1.0 properties"
  source $ROOT_DIR/nsx-t-ci-pipeline/tasks/config-pks/config-pks-1.0.sh
else
  product_version=1.1
  echo ""
  echo "Starting configuration of PKS v1.1+ properties"
  source $ROOT_DIR/nsx-t-ci-pipeline/tasks/config-pks/config-pks-superuser.sh
  source $ROOT_DIR/nsx-t-ci-pipeline/tasks/config-pks/config-pks-1.1.sh
fi

echo ""
echo "Finished configuring PKS Tile"

#!/bin/bash

DEFAULT_QUOTA=2000

# Use provided SUBSCRIPTIONS env var, or fall back to all subscriptions
if [[ -n "$SUBSCRIPTIONS" ]]; then
  SUBSCRIPTION_LIST=$SUBSCRIPTIONS
else
  SUBSCRIPTION_LIST=$(az account list --query "[].id" -o tsv)
fi

for SUBSCRIPTION_ID in $SUBSCRIPTION_LIST; do
  echo "Checking subscription: $SUBSCRIPTION_ID"

  RESPONSE=$(az rest --method get \
    --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" \
    --query "length(value)" -o tsv 2>&1)

  if [[ $? -ne 0 || "$RESPONSE" == *"AADSTS"* ]]; then
    echo "  ❌ Skipping due to authentication or access error."
    echo "  Message: $RESPONSE"
    echo ""
    continue
  fi

  COUNT=$RESPONSE
  echo "  Role assignments used: $COUNT"
  echo "  Default quota limit:   $DEFAULT_QUOTA"

  if (( COUNT >= DEFAULT_QUOTA )); then
    echo "  ⚠️  Quota limit reached or exceeded!"
  elif (( COUNT >= DEFAULT_QUOTA * 90 / 100 )); then
    echo "  ⚠️  Usage is above 90% of the quota!"
  else
    echo "  ✅ Within safe quota range."
  fi

  echo ""
done

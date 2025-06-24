#!/bin/bash

# Function to get quota limit dynamically for a subscription
get_quota_limit() {
  local subscription_id=$1
  
  # Call Azure API to get role assignment quota information
  local quota_response=$(az rest --method get \
    --url "https://management.azure.com/subscriptions/${subscription_id}/providers/Microsoft.Authorization/roleassignmentsusagemetrics?api-version=2019-08-01-preview" \
    --query "roleAssignmentsLimit" -o tsv 2>&1)
  
  if [[ $? -ne 0 || "$quota_response" == *"AADSTS"* || -z "$quota_response" ]]; then
    # Fallback to default if API call fails
    echo "2000"
  else
    echo "$quota_response"
  fi
}

# Use provided SUBSCRIPTIONS env var, or fall back to all subscriptions
if [[ -n "$SUBSCRIPTIONS" ]]; then
  # Support both space-separated and CSV formats
  # Convert CSV to space-separated if needed
  SUBSCRIPTION_LIST=$(echo "$SUBSCRIPTIONS" | tr ',' ' ')
else
  SUBSCRIPTION_LIST=$(az account list --query "[].id" -o tsv)
fi

for SUBSCRIPTION_ID in $SUBSCRIPTION_LIST; do
  echo "Checking subscription: $SUBSCRIPTION_ID"

  # Get dynamic quota limit for this subscription
  QUOTA_LIMIT=$(get_quota_limit "$SUBSCRIPTION_ID")
  
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
  echo "  Current quota limit:   $QUOTA_LIMIT"

  if (( COUNT >= QUOTA_LIMIT )); then
    echo "  ⚠️  Quota limit reached or exceeded!"
  elif (( COUNT >= QUOTA_LIMIT * 90 / 100 )); then
    echo "  ⚠️  Usage is above 90% of the quota!"
  else
    echo "  ✅ Within safe quota range."
  fi

  echo ""
done

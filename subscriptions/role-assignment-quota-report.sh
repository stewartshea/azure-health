#!/bin/bash

# Set DEBUG=1 to see detailed role assignment information
DEBUG=${DEBUG:-0}

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
  # Get subscription name for better readability
  SUBSCRIPTION_NAME=$(az account show --subscription "$SUBSCRIPTION_ID" --query "name" -o tsv 2>/dev/null)
  
  if [[ -z "$SUBSCRIPTION_NAME" ]]; then
    echo "Checking subscription: $SUBSCRIPTION_ID"
  else
    echo "Checking subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
  fi

  # Get dynamic quota limit for this subscription
  QUOTA_LIMIT=$(get_quota_limit "$SUBSCRIPTION_ID")
  
  # Get all direct role assignments (exclude inherited ones)
  # Using $filter to ensure we only get assignments directly made at this subscription scope
  ALL_ASSIGNMENTS=$(az rest --method get \
    --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=atScope()" \
    --query "value" -o json 2>&1)

  if [[ $? -ne 0 || "$ALL_ASSIGNMENTS" == *"AADSTS"* ]]; then
    echo "  ❌ Skipping due to authentication or access error."
    echo "  Message: $ALL_ASSIGNMENTS"
    echo ""
    continue
  fi

  # Additional filtering to ensure only direct assignments
  # Filter out any assignments with scope different from current subscription
  DIRECT_ASSIGNMENTS=$(echo "$ALL_ASSIGNMENTS" | jq --arg sub_scope "/subscriptions/$SUBSCRIPTION_ID" '[.[] | select(.properties.scope == $sub_scope)]' 2>/dev/null)
  
  if [[ -z "$DIRECT_ASSIGNMENTS" || "$DIRECT_ASSIGNMENTS" == "null" ]]; then
    # Fallback if jq fails - use the original response
    DIRECT_ASSIGNMENTS="$ALL_ASSIGNMENTS"
  fi

  # Count the direct role assignments only
  COUNT=$(echo "$DIRECT_ASSIGNMENTS" | jq '. | length' 2>/dev/null)
  
  # Fallback if jq is not available
  if [[ -z "$COUNT" || "$COUNT" == "null" ]]; then
    COUNT=$(echo "$DIRECT_ASSIGNMENTS" | grep -o '"principalId"' | wc -l)
  fi

  # Debug output to help understand what's being counted
  if [[ "$DEBUG" == "1" ]]; then
    echo "  🔍 DEBUG: API endpoint used: /subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/roleAssignments"
    echo "  🔍 DEBUG: API version: 2022-04-01"
    echo "  🔍 DEBUG: Filter applied: atScope() + scope filtering"
    echo "  🔍 DEBUG: Scope: DIRECT subscription-level assignments ONLY"
    if command -v jq >/dev/null 2>&1; then
      echo "  🔍 DEBUG: Sample assignments (first 3):"
      echo "$DIRECT_ASSIGNMENTS" | jq -r '.[:3] | .[] | "    - " + .properties.principalDisplayName + " (" + .properties.roleDefinitionName + ") [Scope: " + .properties.scope + "]"' 2>/dev/null || echo "    (Unable to parse assignment details)"
      
      # Show total vs direct count if different
      TOTAL_COUNT=$(echo "$ALL_ASSIGNMENTS" | jq '. | length' 2>/dev/null)
      if [[ "$TOTAL_COUNT" != "$COUNT" ]]; then
        echo "  🔍 DEBUG: Total assignments found: $TOTAL_COUNT, Direct assignments: $COUNT"
      fi
    fi
  fi

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

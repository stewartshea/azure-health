#!/bin/bash

# Set DEBUG=1 to see detailed role assignment information
DEBUG=${DEBUG:-0}

# Ensure Azure Resource Graph extension is installed
echo "🔧 Checking Azure CLI resource-graph extension..."
if ! az extension list --query "[?name=='resource-graph']" -o tsv | grep -q "resource-graph"; then
  echo "📦 Installing Azure CLI resource-graph extension..."
  az extension add --name resource-graph --yes >/dev/null 2>&1
fi

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
  
  # Get role assignment count using Azure Resource Graph (same as user's working query)
  RESOURCE_GRAPH_QUERY="authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | where subscriptionId == '${SUBSCRIPTION_ID}' | summarize count()"
  
  # Execute query and capture both stdout and stderr, then filter out warnings
  GRAPH_OUTPUT=$(az graph query -q "$RESOURCE_GRAPH_QUERY" --query "data[0].count_" -o tsv 2>&1)
  
  # Extract just the numeric count, filtering out warnings and prompts
  COUNT=$(echo "$GRAPH_OUTPUT" | grep -E '^[0-9]+$' | head -1)

  # Check for errors in the output
  if [[ -z "$COUNT" || ! "$COUNT" =~ ^[0-9]+$ ]] || echo "$GRAPH_OUTPUT" | grep -qi "error\|failed\|denied\|unauthorized\|forbidden"; then
    echo "  ❌ Error retrieving role assignment count."
    echo "  Message: $GRAPH_OUTPUT"
    echo ""
    continue
  fi

  # Debug output to help understand what's being counted
  if [[ "$DEBUG" == "1" ]]; then
    echo "  🔍 DEBUG: Using Azure Resource Graph query"
    echo "  🔍 DEBUG: Query: $RESOURCE_GRAPH_QUERY"
    echo "  🔍 DEBUG: Raw output: $GRAPH_OUTPUT"
    echo "  🔍 DEBUG: Extracted count: $COUNT"
    echo "  🔍 DEBUG: This matches the KQL query that gives accurate results"
  fi

  echo "  Role assignments used: $COUNT"
  echo "  Current quota limit:   $QUOTA_LIMIT"

  # Final safety check for any error conditions before status evaluation
  if echo "$GRAPH_OUTPUT" | grep -qi "error\|failed\|denied\|unauthorized\|forbidden\|exception"; then
    echo "  ❌ Warning: Errors detected in data retrieval - count may be unreliable."
    echo ""
    continue
  fi

  # Determine status based on count and quota
  if [[ "$COUNT" == "0" ]]; then
    echo "  ⚠️  No role assignments found - this may indicate an access issue or unusual configuration."
  elif (( COUNT >= QUOTA_LIMIT )); then
    echo "  ⚠️  Quota limit reached or exceeded!"
  elif (( COUNT >= QUOTA_LIMIT * 90 / 100 )); then
    echo "  ⚠️  Usage is above 90% of the quota!"
  else
    echo "  ✅ Within safe quota range."
  fi

  echo ""
done

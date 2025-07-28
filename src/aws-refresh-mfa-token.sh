#!/bin/bash
# refresh-aws-token.sh
# Auto-refresh AWS session tokens for account

# Set default ACCOUNT_ID (can be empty to force prompt)
ACCOUNT_ID=""

# Check if ACCOUNT_ID is set and not empty
if [ -n "$ACCOUNT_ID" ]; then
    echo "Current AWS account ID that enforces MFA: $ACCOUNT_ID"
    echo ""
    echo "Options: y=keep, n=exit, r=replace"
    read -p "Refresh MFA credentials for current account ID? (y/n/r): " keep_account
    case $keep_account in
        [Yy]* )
            echo "Using existing account ID: $ACCOUNT_ID"
            ;;
        [Rr]* )
            while true; do
                read -p "Enter new AWS account ID that enforces MFA: " NEW_ACCOUNT_ID
                if [ -z "$NEW_ACCOUNT_ID" ]; then
                    echo "❌ Error: Account ID is required"
                    continue
                fi
                if [[ ! "$NEW_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
                    echo "❌ Error: Account ID must be exactly 12 digits (e.g., 123456789012)"
                    continue
                fi
                break
            done
            ACCOUNT_ID="$NEW_ACCOUNT_ID"
            echo "MFA Account ID updated to: $ACCOUNT_ID"
            
            # Save the new account ID back to the script file
            SCRIPT_FILE="$0"
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS version
                sed -i '' "s/^ACCOUNT_ID=.*/ACCOUNT_ID=\"$ACCOUNT_ID\"/" "$SCRIPT_FILE"
            else
                # Linux version
                sed -i "s/^ACCOUNT_ID=.*/ACCOUNT_ID=\"$ACCOUNT_ID\"/" "$SCRIPT_FILE"
            fi
            echo "✓ Account ID saved to script file for future use"
            ;;
        [Nn]* )
            echo "Exiting..."
            exit 0
            ;;
        * )
            echo "Invalid option. Exiting..."
            exit 1
            ;;
    esac
else
    # If ACCOUNT_ID is empty, prompt for it
    while true; do
        read -p "Enter AWS account ID that enforces MFA: " ACCOUNT_ID
        if [ -z "$ACCOUNT_ID" ]; then
            echo "❌ Error: Account ID is required"
            continue
        fi
        if [[ ! "$ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
            echo "❌ Error: Account ID must be exactly 12 digits (e.g., 123456789012)"
            continue
        fi
        break
    done
    
    # Save the new account ID back to the script file
    SCRIPT_FILE="$0"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version
        sed -i '' "s/^ACCOUNT_ID=.*/ACCOUNT_ID=\"$ACCOUNT_ID\"/" "$SCRIPT_FILE"
    else
        # Linux version
        sed -i "s/^ACCOUNT_ID=.*/ACCOUNT_ID=\"$ACCOUNT_ID\"/" "$SCRIPT_FILE"
    fi
    echo "✓ Account ID saved to script file for future use"
fi

PROFILE="mfa-auth"

# First, ensure permanent credentials exist for getting the session token
CREDENTIALS_FILE="$HOME/.aws/credentials"
mkdir -p "$(dirname "$CREDENTIALS_FILE")"

# Check if default profile exists and has permanent credentials
if [ ! -f "$CREDENTIALS_FILE" ] || ! grep -q "\[default\]" "$CREDENTIALS_FILE"; then
    echo "❌ Error: [default] profile not found in credentials file"
    echo "   Please run the setup script first: ./src/aws-setup-cli-profiles.sh"
    exit 1
fi

# Check if default profile has session credentials (which can't be used for token generation)
if grep -A 2 "\[default\]" "$CREDENTIALS_FILE" | grep -q "aws_session_token"; then
    echo "❌ Error: [default] profile contains session credentials"
    echo "   Session credentials cannot be used to generate new session tokens"
    echo "   Please run the setup script to configure permanent credentials: ./src/aws-setup-cli-profiles.sh"
    exit 1
fi

# Verify default profile has permanent credentials
if ! grep -A 2 "\[default\]" "$CREDENTIALS_FILE" | grep -q "aws_access_key_id"; then
    echo "❌ Error: [default] profile missing access key"
    echo "   Please run the setup script to configure credentials: ./src/aws-setup-cli-profiles.sh"
    exit 1
fi

echo "Getting new session token for account ${ACCOUNT_ID}..."

# Get MFA code from user
read -p "Enter MFA code: " MFA_CODE

# Get new session token using default profile (permanent credentials)
# Temporarily use AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY to bypass role config
TEMP_ACCESS_KEY=$(grep -A 2 "\[default\]" "$CREDENTIALS_FILE" | grep "aws_access_key_id" | cut -d'=' -f2 | xargs)
TEMP_SECRET_KEY=$(grep -A 2 "\[default\]" "$CREDENTIALS_FILE" | grep "aws_secret_access_key" | cut -d'=' -f2 | xargs)

TOKEN_RESPONSE=$(AWS_ACCESS_KEY_ID="$TEMP_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$TEMP_SECRET_KEY" aws sts get-session-token \
  --duration-seconds 43200 \
  --serial-number arn:aws:iam::${ACCOUNT_ID}:mfa/innovativesol-msft-authenticator-for-aws-console \
  --token-code "$MFA_CODE" \
  --output json)

# Check if successful
if [ $? -ne 0 ]; then
    echo "Failed to get session token"
    exit 1
fi

# Extract credentials
ACCESS_KEY=$(echo "$TOKEN_RESPONSE" | jq -r '.Credentials.AccessKeyId')
SECRET_KEY=$(echo "$TOKEN_RESPONSE" | jq -r '.Credentials.SecretAccessKey')
SESSION_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.Credentials.SessionToken')



# Now write the session credentials to the mfa-auth profile
# Remove ALL existing mfa-auth profiles if they exist (handle duplicates)
while grep -q "\[mfa-auth\]" "$CREDENTIALS_FILE"; do
    # Find the line numbers for the first mfa-auth profile
    start_line=$(grep -n "\[mfa-auth\]" "$CREDENTIALS_FILE" | head -1 | cut -d: -f1)
    if [ -n "$start_line" ]; then
        # Find the end of this profile (next profile or end of file)
        end_line=$(tail -n +$((start_line + 1)) "$CREDENTIALS_FILE" | grep -n "^\[" | head -1 | cut -d: -f1)
        if [ -n "$end_line" ]; then
            end_line=$((start_line + end_line))
        else
            end_line=$(wc -l < "$CREDENTIALS_FILE")
        fi
        # Remove the profile (compatible with both Linux and macOS)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS version
            sed -i '' "${start_line},${end_line}d" "$CREDENTIALS_FILE"
        else
            # Linux version
            sed -i "${start_line},${end_line}d" "$CREDENTIALS_FILE"
        fi
    fi
done

# Add mfa-auth profile with session credentials
echo "[mfa-auth]" >> "$CREDENTIALS_FILE"
echo "aws_access_key_id = $ACCESS_KEY" >> "$CREDENTIALS_FILE"
echo "aws_secret_access_key = $SECRET_KEY" >> "$CREDENTIALS_FILE"
echo "aws_session_token = $SESSION_TOKEN" >> "$CREDENTIALS_FILE"

echo "✓ Session token saved to mfa-auth profile"
echo "✓ Token expires in 12 hours"
echo ""
echo "[Default profile example]: aws s3 ls"
echo "[Role profile example]: aws s3 ls --profile customer-name"

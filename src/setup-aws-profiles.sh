#!/bin/bash
# setup-aws-profiles-dynamic.sh
# Set up AWS profiles dynamically using native AWS CLI



# 1. Add the primary account that requires MFA access, and that will be assuming customer roles here. 
PERMANENT_ACCESS_KEY=""
PERMANENT_SECRET_KEY=""

# 2. Define any CUSTOMER profiles here (add new customers as needed)
    # Format: "profile_name:arn:aws:iam::123456789012:role/RoleName"
    # IMPORTANT: Must include profile_name: prefix before the ARN
    # Note: DO NOT add [Default] or [profile mfa-auth] roles here,
    #       those are created from the script input or existing settings.
    # Note: No commas needed between array entries in Bash
PROFILES=(
    # "customer1:arn:aws:iam::123456789012:role/CustomerRole"
    # "customer2:arn:aws:iam::987654321098:role/CustomerRole"
    # "customer3:arn:aws:iam::111222333444:role/AnotherRole"
)
CONFIG_FILE="$HOME/.aws/config"
CREDENTIALS_FILE="$HOME/.aws/credentials"
BACKUP_DIR="$HOME/.aws/backups"

# 3. Save script and copy to /%HOME%/bin (e.g. /users/jdoe/bin) and restart terminal session

# 4.  Run the script

# 5. Then run the refresh-aws-mfa-token.sh script to update the .aws/credentials with the temporary access id, key, and session. 
     # You should now be authenticated to AWS. See that script output for usage/testing with the --profile option. 
     # Temporary MFA credentials are 12 hrs by default. Change in script as desired. Rerun refresh-aws-mfa-token.sh to get fresh credentials when needed

echo "Setting up AWS profiles..."

# Function to validate email format
validate_email() {
    local email="$1"
    local email_regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    if [[ $email =~ $email_regex ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate AWS ARN format
validate_arn() {
    local arn="$1"
    local arn_regex="^arn:aws:iam::[0-9]{12}:(mfa|user)/[a-zA-Z0-9._-]+$"
    if [[ $arn =~ $arn_regex ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate role ARN format
validate_role_arn() {
    local role_arn="$1"
    local role_arn_regex="^arn:aws:iam::[0-9]{12}:role/[a-zA-Z0-9._-]+$"
    if [[ $role_arn =~ $role_arn_regex ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate profile entry format
validate_profile_entry() {
    local profile_entry="$1"
    # Check if entry contains exactly one colon and has both parts
    if [[ $profile_entry =~ ^[a-zA-Z0-9._-]+:arn:aws:iam::[0-9]{12}:role/[a-zA-Z0-9._-]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to extract profile name and role ARN from entry
extract_profile_parts() {
    local profile_entry="$1"
    local profile_name=$(echo "$profile_entry" | cut -d':' -f1)
    local role_arn=$(echo "$profile_entry" | sed 's/^[^:]*://')
    echo "$profile_name|$role_arn"
}

# Function to format session name from email
format_session_name() {
    local email="$1"
    local username=$(echo "$email" | cut -d'@' -f1)
    local domain=$(echo "$email" | cut -d'@' -f2 | cut -d'.' -f1)
    local suffix=$(echo "$email" | cut -d'@' -f2 | cut -d'.' -f2-)
    echo "${username}_at_${domain}_dot_${suffix}"
}

# Function to reverse session name to email (if possible)
reverse_session_to_email() {
    local session_name="$1"
    # Try to reverse the format: username_at_domain_dot_suffix
    if [[ $session_name =~ ^([^_]+)_at_([^_]+)_dot_(.+)$ ]]; then
        local username="${BASH_REMATCH[1]}"
        local domain="${BASH_REMATCH[2]}"
        local suffix="${BASH_REMATCH[3]}"
        echo "${username}@${domain}.${suffix}"
    else
        echo ""
    fi
}

# Function to extract existing values from config
extract_existing_values() {
    local config_file=$CONFIG_FILE
    local existing_email=""
    local existing_mfa_serial=""
    
    if [ -f "$config_file" ]; then
        # Try to find existing session name and reverse it to email
        local existing_session=$(grep "role_session_name" "$config_file" | head -1 | cut -d'=' -f2 | xargs)
        if [ -n "$existing_session" ]; then
            existing_email=$(reverse_session_to_email "$existing_session")
        fi
        
        # Extract existing MFA serial
        existing_mfa_serial=$(grep "mfa_serial" "$config_file" | head -1 | cut -d'=' -f2 | xargs)
    fi
    
    echo "$existing_email|$existing_mfa_serial"
}

# Extract existing values
EXISTING_VALUES=$(extract_existing_values)
EXISTING_EMAIL=$(echo "$EXISTING_VALUES" | cut -d'|' -f1)
EXISTING_MFA_SERIAL=$(echo "$EXISTING_VALUES" | cut -d'|' -f2)

# Extract existing default role ARN
EXISTING_DEFAULT_ROLE_ARN=""
if [ -f "$CONFIG_FILE" ]; then
    EXISTING_DEFAULT_ROLE_ARN=$(grep -A 5 "\[default\]" "$CONFIG_FILE" | grep "role_arn" | cut -d'=' -f2 | xargs)
fi

# Prompt for email address with existing value option
echo ""
if [ -n "$EXISTING_EMAIL" ] && validate_email "$EXISTING_EMAIL"; then
    echo "Found existing email: $EXISTING_EMAIL"
    read -p "Keep existing email? (y/n): " keep_email
    if [[ $keep_email =~ ^[Nn]$ ]]; then
        EMAIL_ADDRESS=""
    else
        EMAIL_ADDRESS="$EXISTING_EMAIL"
    fi
else
    EMAIL_ADDRESS=""
fi

if [ -z "$EMAIL_ADDRESS" ]; then
    echo "Please enter your email address:"
    while true; do
        read -p "Email address: " EMAIL_ADDRESS
        if validate_email "$EMAIL_ADDRESS"; then
            break
        else
            echo "❌ Invalid email format. Please enter a valid email address (e.g., user@domain.com)"
        fi
    done
fi

# Format session name from email
SESSION_NAME=$(format_session_name "$EMAIL_ADDRESS")
echo ""

# Prompt for default role ARN with existing value option
if [ -n "$EXISTING_DEFAULT_ROLE_ARN" ] && validate_role_arn "$EXISTING_DEFAULT_ROLE_ARN"; then
    echo "Found existing default role ARN: $EXISTING_DEFAULT_ROLE_ARN"
    read -p "Keep existing default role ARN? (y/n): " keep_role_arn
    if [[ $keep_role_arn =~ ^[Nn]$ ]]; then
        DEFAULT_ROLE_ARN=""
    else
        DEFAULT_ROLE_ARN="$EXISTING_DEFAULT_ROLE_ARN"
    fi
else
    DEFAULT_ROLE_ARN=""
fi

if [ -z "$DEFAULT_ROLE_ARN" ]; then
    echo "Please enter your default role ARN:"
    while true; do
        read -p "Default Role ARN: " DEFAULT_ROLE_ARN
        if validate_role_arn "$DEFAULT_ROLE_ARN"; then
            break
        else
            echo "❌ Invalid role ARN format. Please enter a valid AWS role ARN (e.g., arn:aws:iam::123456789012:role/RoleName)"
        fi
    done
fi
echo ""

# Prompt for MFA Serial ARN with existing value option
if [ -n "$EXISTING_MFA_SERIAL" ] && validate_arn "$EXISTING_MFA_SERIAL"; then
    echo "Found existing MFA Serial ARN: $EXISTING_MFA_SERIAL"
    read -p "Keep existing MFA Serial ARN? (y/n): " keep_mfa
    if [[ $keep_mfa =~ ^[Nn]$ ]]; then
        MFA_SERIAL=""
    else
        MFA_SERIAL="$EXISTING_MFA_SERIAL"
    fi
else
    MFA_SERIAL=""
fi

if [ -z "$MFA_SERIAL" ]; then
    echo "Please enter your MFA Serial ARN:"
    while true; do
        read -p "MFA Serial ARN: " MFA_SERIAL
        if validate_arn "$MFA_SERIAL"; then
            break
        else
            echo "❌ Invalid ARN format. Please enter a valid AWS ARN (e.g., arn:aws:iam::123456789012:mfa/user@domain.com)"
        fi
    done
fi
echo ""

# Handle credentials file
mkdir -p "$(dirname "$CREDENTIALS_FILE")"

# Initialize backup tracking
BACKUP_MESSAGES=()

# Create backup of credentials file if it exists
if [ -f "$CREDENTIALS_FILE" ]; then
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    CREDENTIALS_BACKUP="$BACKUP_DIR/credentials_${TIMESTAMP}"
    cp "$CREDENTIALS_FILE" "$CREDENTIALS_BACKUP"
    BACKUP_MESSAGES+=("Credentials: $CREDENTIALS_BACKUP")
fi

# Extract existing permanent credentials or prompt for them

if [ -f "$CREDENTIALS_FILE" ] && grep -q "\[default\]" "$CREDENTIALS_FILE"; then
    # Check if default profile has session credentials (which we don't want to preserve)
    if grep -A 3 "\[default\]" "$CREDENTIALS_FILE" | grep -q "aws_session_token"; then
        echo "⚠️  Warning: [default] profile contains session credentials"
        echo "   These will be replaced with permanent credentials for MFA token generation"
        echo ""
        PERMANENT_ACCESS_KEY=""
        PERMANENT_SECRET_KEY=""
    else
        # Extract existing permanent credentials from default profile
        PERMANENT_ACCESS_KEY=$(grep -A 2 "\[default\]" "$CREDENTIALS_FILE" | grep "aws_access_key_id" | cut -d'=' -f2 | xargs)
        PERMANENT_SECRET_KEY=$(grep -A 2 "\[default\]" "$CREDENTIALS_FILE" | grep "aws_secret_access_key" | cut -d'=' -f2 | xargs)
    fi
fi

# Prompt for credentials if they don't exist
if [ -z "$PERMANENT_ACCESS_KEY" ] || [ -z "$PERMANENT_SECRET_KEY" ]; then
    echo ""
    echo "Permanent AWS credentials not found or incomplete."
    echo "Please enter your AWS access credentials:"
    echo ""
    
    if [ -z "$PERMANENT_ACCESS_KEY" ]; then
        read -p "AWS Access Key ID: " PERMANENT_ACCESS_KEY
    fi
    
    if [ -z "$PERMANENT_SECRET_KEY" ]; then
        echo -n "AWS Secret Access Key: "
        # Read with visual feedback
        PERMANENT_SECRET_KEY=""
        while IFS= read -rs -n 1 char; do
            if [[ $char == $'\0' ]]; then
                break
            elif [[ $char == $'\177' ]]; then
                # Backspace
                if [ ${#PERMANENT_SECRET_KEY} -gt 0 ]; then
                    PERMANENT_SECRET_KEY="${PERMANENT_SECRET_KEY%?}"
                    echo -ne "\b \b"
                fi
            else
                PERMANENT_SECRET_KEY+="$char"
                echo -n "*"
            fi
        done
        echo ""
        # Show immediate feedback with character count
        if [ -n "$PERMANENT_SECRET_KEY" ]; then
            echo "✓ Secret key entered (${#PERMANENT_SECRET_KEY} characters)"
        else
            echo "❌ No secret key entered"
            exit 1
        fi
    fi
    
    echo ""
fi

# Create clean credentials file with default section and preserve other sections
echo "[default]" > "$CREDENTIALS_FILE"
echo "aws_access_key_id = $PERMANENT_ACCESS_KEY" >> "$CREDENTIALS_FILE"
echo "aws_secret_access_key = $PERMANENT_SECRET_KEY" >> "$CREDENTIALS_FILE"
echo "" >> "$CREDENTIALS_FILE"

# Preserve existing sections except default and mfa-auth
if [ -f "$CREDENTIALS_BACKUP" ]; then
    # Extract all sections except [default] and [mfa-auth]
    awk '/^\[/ { 
        if ($0 ~ /^\[default\]/ || $0 ~ /^\[mfa-auth\]/) {
            skip = 1
        } else {
            skip = 0
            print ""
            print $0
        }
        next
    }
    !skip && NF > 0 {
        print $0
    }' "$CREDENTIALS_BACKUP" >> "$CREDENTIALS_FILE"
fi

# Create config file in correct order
mkdir -p "$(dirname "$CONFIG_FILE")"

# Create backup of config file if it exists
if [ -f "$CONFIG_FILE" ]; then
    # Create backups directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
    
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    CONFIG_BACKUP="$BACKUP_DIR/config_${TIMESTAMP}"
    cp "$CONFIG_FILE" "$CONFIG_BACKUP"
    BACKUP_MESSAGES+=("Config: $CONFIG_BACKUP/config_${TIMESTAMP}")
fi

# Start with default profile (dual nature: permanent creds + role config)
echo "[default]" > "$CONFIG_FILE"
echo "role_arn = $DEFAULT_ROLE_ARN" >> "$CONFIG_FILE"
echo "source_profile = mfa-auth" >> "$CONFIG_FILE"
echo "role_session_name = $SESSION_NAME" >> "$CONFIG_FILE"
echo "region = us-east-1" >> "$CONFIG_FILE"
echo "" >> "$CONFIG_FILE"

# Add mfa-auth profile with MFA serial
echo "[profile mfa-auth]" >> "$CONFIG_FILE"
echo "mfa_serial = $MFA_SERIAL" >> "$CONFIG_FILE"
echo "" >> "$CONFIG_FILE"

# Validate all profile entries first before making any changes
echo ""
echo "Validating all profile entries..."

# Initialize arrays to collect errors and valid profiles
VALIDATION_ERRORS=()
VALID_PROFILES=()

for profile_entry in "${PROFILES[@]}"; do
    # Skip empty entries
    if [ -z "$profile_entry" ]; then
        continue
    fi
    
    # Validate profile entry format
    if ! validate_profile_entry "$profile_entry"; then
        VALIDATION_ERRORS+=("❌ Invalid profile entry format: $profile_entry")
        VALIDATION_ERRORS+=("   Expected format: profile_name:arn:aws:iam::123456789012:role/RoleName")
        continue
    fi
    
    # Extract profile name and role ARN
    profile_parts=$(extract_profile_parts "$profile_entry")
    profile_name=$(echo "$profile_parts" | cut -d'|' -f1)
    role_arn=$(echo "$profile_parts" | cut -d'|' -f2)
    
    # Validate role ARN format
    if ! validate_role_arn "$role_arn"; then
        VALIDATION_ERRORS+=("❌ Invalid role ARN format in profile '$profile_name': $role_arn")
        VALIDATION_ERRORS+=("   Expected format: arn:aws:iam::123456789012:role/RoleName")
        continue
    fi
    
    # If we get here, the profile is valid
    VALID_PROFILES+=("$profile_entry")
done

# Check if there are any validation errors
if [ ${#VALIDATION_ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "❌ VALIDATION ERRORS FOUND - NO CHANGES MADE"
    echo "============================================="
    echo "Please fix the following errors before running the script again:"
    echo ""
    for error in "${VALIDATION_ERRORS[@]}"; do
        echo "$error"
    done
    echo ""
    echo "============================================="
    echo "Script aborted. No files were modified."
    exit 1
fi

# If we get here, all profiles are valid - proceed with setup
echo "✓ All profile entries are valid"
echo ""
echo "Setting up customer profiles..."

for profile_entry in "${VALID_PROFILES[@]}"; do
    # Extract profile name and role ARN (we know these are valid now)
    profile_parts=$(extract_profile_parts "$profile_entry")
    profile_name=$(echo "$profile_parts" | cut -d'|' -f1)
    role_arn=$(echo "$profile_parts" | cut -d'|' -f2)
    
    echo "Setting up profile: $profile_name"
    echo "[profile $profile_name]" >> "$CONFIG_FILE"
    echo "role_arn = $role_arn" >> "$CONFIG_FILE"
    echo "source_profile = mfa-auth" >> "$CONFIG_FILE"
    echo "role_session_name = $SESSION_NAME" >> "$CONFIG_FILE"
    echo "region = us-east-1" >> "$CONFIG_FILE"
    echo "" >> "$CONFIG_FILE"
    echo "✓ Profile $profile_name configured"
done

# Count successful profiles
SUCCESSFUL_COUNT=${#VALID_PROFILES[@]}

echo ""
echo "All profiles configured with:"
echo "- Session name: $SESSION_NAME"
echo "- MFA serial: $MFA_SERIAL"
echo "Total role profiles created: $SUCCESSFUL_COUNT (out of ${#PROFILES[@]} entries)"

# Show successful profile names if any
if [ $SUCCESSFUL_COUNT -gt 0 ]; then
    echo "Successfully created profiles:"
    for profile_entry in "${VALID_PROFILES[@]}"; do
        profile_parts=$(extract_profile_parts "$profile_entry")
        profile_name=$(echo "$profile_parts" | cut -d'|' -f1)
        echo "  - $profile_name"
    done
fi

echo ""
echo "Config file created in this order:"
echo "1. [default]"
echo "2. [profile mfa-auth] (empty - inherits from default)"
echo "3. Customer role profiles"
echo ""
if [ -n "$CONFIG_BACKUP" ]; then
    echo "📁 Backup created: $CONFIG_BACKUP"
fi
if [ -n "$CREDENTIALS_BACKUP" ]; then
    echo "📁 Backup created: $CREDENTIALS_BACKUP"
fi

echo ""
echo "To add new customers:"
echo "1. Add them to the PROFILES array in this script"
echo "2. Run this script again"
echo ""
echo "To change session name or MFA serial:"
echo "1. Edit the SESSION_NAME or MFA_SERIAL variables in this script"
echo "2. Run this script again" 
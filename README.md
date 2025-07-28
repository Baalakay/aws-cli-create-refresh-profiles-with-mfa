# AWS MFA Token Management Scripts

This project contains two essential scripts for managing AWS Multi-Factor Authentication (MFA) tokens and profile configuration. These scripts work together to provide secure, temporary AWS credentials for accessing AWS services.

## Overview

The scripts provide a secure way to:
1. Set up AWS profiles with role-based access
2. Generate temporary MFA session tokens
3. Manage multiple customer accounts through role assumption
4. Maintain secure credential storage

## Scripts

### 1. `src/aws-setup-cli-profiles.sh`

**Purpose**: Configures AWS profiles for role-based access across multiple customer accounts.

**What it does**:
- Sets up the default AWS profile configuration
- Configures MFA serial numbers for authentication
- Creates role-based profiles for customer accounts
- Manages AWS credentials file structure
- Creates backups of existing configurations

**Key Features**:
- Interactive setup with validation
- Preserves existing configurations
- Creates automatic backups
- Supports multiple customer role profiles
- Validates email addresses and AWS ARN formats

### 2. `src/aws-refresh-mfa-token.sh`

**Purpose**: Generates temporary AWS session tokens using MFA authentication.

**What it does**:
- Prompts for MFA code from authenticator app
- Generates 12-hour temporary session tokens
- Updates AWS credentials with temporary access keys
- Manages the `mfa-auth` profile
- Provides usage examples for testing
- Manages AWS account ID with persistence

**Key Features**:
- 12-hour token duration (configurable)
- Automatic credential file management
- Cross-platform compatibility (Linux/macOS)
- Cross-shell compatibility (Bash/ZSH)
- Clean profile management (removes duplicates)
- Account ID validation (12-digit numeric) and persistence
- Interactive account ID management (keep/replace/exit)

## Execution Order

**IMPORTANT**: These scripts must be executed in the correct order:

1. **First**: Run `aws-setup-cli-profiles.sh` (one-time setup)
2. **Then**: Run `aws-refresh-mfa-token.sh` (whenever you need fresh credentials)

## Detailed Usage

### Step 1: Install Scripts

**macOS:**
```bash
# Copy scripts to user bin directory (already in PATH)
cp src/aws-setup-cli-profiles.sh ~/bin/
cp src/aws-refresh-mfa-token.sh ~/bin/

# Make scripts executable
chmod +x ~/bin/aws-setup-cli-profiles.sh
chmod +x ~/bin/aws-refresh-mfa-token.sh
```

**Linux:**
```bash
# Copy scripts to user bin directory (already in PATH)
cp src/aws-setup-cli-profiles.sh ~/.local/bin/
cp src/aws-refresh-mfa-token.sh ~/.local/bin/

# Make scripts executable
chmod +x ~/.local/bin/aws-setup-cli-profiles.sh
chmod +x ~/.local/bin/aws-refresh-mfa-token.sh
```

**Restart your terminal session** to ensure the scripts are available in your PATH.

### Step 2: Initial AWS Profile Setup

```bash
# Run the setup script
aws-setup-cli-profiles.sh
```

**Setup Script Prompts**:
- Email address (for session naming)
- Default role ARN (your primary AWS role)
- MFA Serial ARN (your MFA device ARN)
- AWS region (e.g., us-east-1, us-west-2, eu-west-1)
- AWS output format (json, text, table, yaml)
- AWS Access Key ID and Secret Access Key (stored in [default] profile)

**Example Setup Session**:
```
Setting up AWS profiles...

Please enter your email address:
Email address: user@company.com

Please enter your default role ARN:
Default Role ARN: arn:aws:iam::123456789012:role/MyRole

Please enter your MFA Serial ARN:
MFA Serial ARN: arn:aws:iam::123456789012:mfa/user@company.com

Enter AWS region (e.g., us-east-1, us-west-2, eu-west-1): us-east-1
✓ Region saved to script file for future use

Enter AWS output format (json, text, table, yaml): json
✓ Output format saved to script file for future use

Permanent AWS credentials not found or incomplete.
Please enter your AWS access credentials:

AWS Access Key ID: AKIA...
AWS Secret Access Key: ********
✓ Secret key entered (40 characters)

All profiles configured with:
- Session name: user_at_company_dot_com
- MFA serial: arn:aws:iam::123456789012:mfa/user@company.com
- AWS region: us-east-1
- AWS output format: json
Total role profiles created: 0
```

### Step 3: Generate Session Token

```bash
# Run the refresh script to get temporary credentials
aws-refresh-mfa-token.sh
```

**Refresh Script Prompts**:
- AWS account ID (if not already set or when replacing)
- MFA code from your authenticator app

**Example Refresh Session**:
```
Current AWS account ID that enforces MFA: 805336739295

Options: y=keep, n=exit, r=replace
Refresh MFA credentials for current account ID? (y/n/r): y
Using existing account ID: 805336739295
Getting new session token for account 805336739295...
Enter MFA code: 123456
✓ Session token saved to mfa-auth profile
✓ Token expires in 12 hours

[Default profile example]: aws s3 ls
[Customer profile example]: aws s3 ls --profile customer-name
```

**Note**: When using the AWS Toolkit in VS Code/Cursor, you must select the "AWS: profile:mfa-auth" profile for authentication.

**Note**: Manual profile selection is required because the AWS Toolkit doesn't support the dual nature of `[default]` profiles (permanent credentials + role configuration) like the AWS CLI does. The AWS CLI can intelligently use permanent credentials for MFA authentication and then assume roles, but the AWS Toolkit requires explicit profile selection when [default] is setup this way.

## AWS Toolkit Integration

To use the AWS Toolkit in VS Code/Cursor:

- **Profile Selection**: Select "AWS: profile:mfa-auth" from the AWS Toolkit profile dropdown
- **MFA Authentication**: When prompted, enter your MFA code directly in the IDE (if already authenticated prior then you will not be prompted for MFA and any red X error in the IDE footer should dissapear upon selection)
- **Manual Profile Selection**: You must manually select the mfa-auth profile in the AWS Toolkit
- **DevContainer Compatible**: Works with both local and devcontainer environments


## Testing Your Setup

After running both scripts, test your configuration:

```bash
# Test default profile
aws s3 ls

# Test with specific customer profile (if configured)
aws s3 ls --profile customer-name

# Check your current identity
aws sts get-caller-identity

# Check with specific profile
aws sts get-caller-identity --profile customer-name
```

## File Structure Created

The scripts create/modify these files:

```
~/.aws/
├── credentials          # AWS access keys and session tokens
└── config              # AWS profile configurations
    └── backups/        # Automatic backups of previous configurations
```

### Credentials File Structure
```
[default]
aws_access_key_id = AKIA...          # Permanent credentials for MFA token generation
aws_secret_access_key = ...          # (NOT session credentials)

[mfa-auth]
aws_access_key_id = ASIA...          # Temporary session credentials
aws_secret_access_key = ...
aws_session_token = IQoJb3JpZ2luX2Vj...
```

### Config File Structure
```
[default]
role_arn = arn:aws:iam::123456789012:role/MyRole
source_profile = mfa-auth
role_session_name = user_at_company_dot_com
region = us-east-1

[profile mfa-auth]
mfa_serial = arn:aws:iam::123456789012:mfa/user@company.com

[profile customer-name]
role_arn = arn:aws:iam::987654321098:role/CustomerRole
source_profile = mfa-auth
role_session_name = user_at_company_dot_com
region = us-east-1
```

## Adding Customer Profiles

To add new customer profiles:

1. Edit the setup script in your bin directory:
   ```bash
   # macOS
   nano ~/bin/aws-setup-cli-profiles.sh
   
   # Linux
   nano ~/.local/bin/aws-setup-cli-profiles.sh
   ```

2. Add customer entries to the `PROFILES` array:
   ```bash
   PROFILES=(
       "customer1:arn:aws:iam::123456789012:role/CustomerRole"
       "customer2:arn:aws:iam::987654321098:role/CustomerRole"
       "customer3:arn:aws:iam::111222333444:role/AnotherRole"
   )
   ```
   **Important**: 
   - The format must be `"profile_name:arn:aws:iam::123456789012:role/RoleName"` - both the profile name and the full ARN are required
   - **No commas needed** between entries in the Bash array
   - Each entry should be on its own line for readability

3. Run the setup script again: `aws-setup-cli-profiles.sh`

## Security Features

- **Temporary Credentials**: Session tokens expire after 12 hours
- **MFA Protection**: All access requires MFA authentication
- **Role-Based Access**: Uses AWS IAM roles for customer access
- **Automatic Backups**: Preserves previous configurations
- **Secure Input**: Secret keys are hidden during input

## Troubleshooting

### Common Issues

1. **"Cannot call GetSessionToken with session credentials"**
   - **Cause**: `[default]` profile contains session credentials instead of permanent credentials
   - **Solution**: Run the setup script to configure permanent credentials: `aws-setup-cli-profiles.sh`
   - **Prevention**: Always use permanent credentials in `[default]` profile for MFA token generation

2. **"Failed to get session token"**
   - Verify your MFA code is correct
   - Check that your permanent credentials are valid
   - Ensure your MFA device is properly configured

3. **"Account ID must be exactly 12 digits"**
   - **Cause**: AWS account ID must be exactly 12 numeric digits
   - **Solution**: Enter a valid 12-digit AWS account ID (e.g., 123456789012)
   - **Note**: Account ID is automatically saved for future use

4. **"Invalid email format"**
   - Use a valid email address format (e.g., user@domain.com)

5. **"Invalid ARN format"**
   - Role ARN format: `arn:aws:iam::123456789012:role/RoleName`
   - MFA ARN format: `arn:aws:iam::123456789012:mfa/user@domain.com`

6. **Permission Denied**
   - Ensure your role has the necessary permissions
   - Check that the role trust relationship allows your account

### Token Expiration

When your session token expires (after 12 hours):
1. Run `./src/aws-refresh-mfa-token.sh` again
2. Enter a new MFA code
3. Your credentials will be refreshed

## Best Practices

1. **Regular Token Refresh**: Refresh tokens before they expire
2. **Secure Storage**: Never commit credentials to version control
3. **Profile Naming**: Use descriptive names for customer profiles
4. **Backup Management**: Keep backups of important configurations
5. **MFA Device**: Ensure your MFA device is accessible and working

## Dependencies

- AWS CLI installed and configured
- `jq` command-line JSON processor
- Bash or ZSH shell environment
- Valid AWS account with MFA enabled
- Appropriate IAM roles and permissions

## Project Documentation

This project includes comprehensive documentation in the `memory-bank/` directory:

- **`projectbrief.md`**: Core purpose, goals, and success criteria
- **`systemPatterns.md`**: Architecture, technical decisions, and patterns
- **`techContext.md`**: Technology stack, dependencies, and setup
- **`activeContext.md`**: Current status and work focus
- **`progress.md`**: What works, what's left, and known issues

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Verify your AWS account permissions
3. Ensure MFA device is properly configured
4. Review AWS CLI documentation for additional commands
5. Check the memory bank documentation for technical details 
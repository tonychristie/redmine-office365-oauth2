# Redmine OAuth2 Email Integration for Office 365

This repository contains the necessary files and instructions to enable Redmine to receive emails from Office 365 using OAuth2 authentication via IMAP.

## Background

Microsoft no longer supports basic username/password authentication for IMAP access to Office 365 mailboxes. This solution implements OAuth2 authentication for Redmine's email receiver functionality.

## Solution Overview

This integration consists of:
1. Modified `imap.rb` file that adds OAuth2 support to Redmine's IMAP receiver
2. A shell script (`oauth_mail.sh`) that obtains OAuth2 tokens and triggers email retrieval
3. The `mail_xoauth2` Ruby gem for OAuth2 IMAP authentication

## Prerequisites

- Redmine installation (tested on 6.1, but should work on 4.x+)
- Office 365 mailbox for receiving Redmine emails
- Azure AD application registration with appropriate permissions
- `jq` command-line JSON processor

## Installation

### 1. Install Required Packages

```bash
# Install jq for JSON parsing
sudo apt-get update
sudo apt-get install jq

# Install the mail_xoauth2 gem
cd /opt/bitnami/redmine  # Adjust path to your Redmine installation
bundle add mail_xoauth2
```

### 2. Configure Azure AD Application

1. Register an application in Azure AD
2. Grant the following API permissions:
   - `IMAP.AccessAsUser.All`
   - `User.Read`
3. Enable "Allow public client flows" for the application
4. Note down:
   - Client ID
   - Client Secret
   - Tenant ID

### 3. Replace Redmine's IMAP Library

**Important: Backup the original file first!**

```bash
# Backup original file
sudo cp /opt/bitnami/redmine/lib/redmine/imap.rb /opt/bitnami/redmine/lib/redmine/imap.rb.original

# Replace with modified version
sudo cp imap.rb /opt/bitnami/redmine/lib/redmine/imap.rb
```

### 4. Configure the Email Retrieval Script

1. Create directory for the script:
```bash
mkdir -p ~/oauth_mail
```

2. Copy the `oauth_mail.sh` script to `~/oauth_mail/oauth_mail.sh`

3. Edit the script and update the following values:
   - `client_id`: Your Azure AD application client ID
   - `client_secret`: Your Azure AD application client secret
   - `username`: Your Office 365 email address (e.g., redmine@yourdomain.com)
   - `password`: The mailbox password
   - Tenant ID in the OAuth URL

4. Update the Redmine path if needed (default assumes `/opt/bitnami/redmine`)

5. Make the script executable:
```bash
chmod +x ~/oauth_mail/oauth_mail.sh
```

### 5. Test the Integration

Run the script manually to verify it works:

```bash
sudo -u daemon ~/oauth_mail/oauth_mail.sh
```

You should see curl progress output and any email processing messages.

### 6. Set Up Automated Email Retrieval

Add a cron job to check for emails regularly:

```bash
# Edit daemon user's crontab
sudo crontab -u daemon -e

# Add this line to check every 5 minutes:
*/5 * * * * /home/bitnami/oauth_mail/oauth_mail.sh
```

## How It Works

### OAuth2 Token Detection

The modified `imap.rb` detects OAuth2 tokens by checking password length:
- Passwords > 30 characters: Treated as OAuth2 token, uses `authenticate('XOAUTH2')`
- Passwords ≤ 30 characters: Treated as regular password, uses standard `login()`

This allows backward compatibility with non-OAuth IMAP servers.

### Authentication Flow

1. `oauth_mail.sh` requests an OAuth2 access token from Microsoft
2. Token is parsed using `jq` and stored in `$MSTOKEN` variable
3. Token is passed to Redmine's IMAP rake task as the password parameter
4. Modified `imap.rb` detects the long password and uses OAuth2 authentication
5. Emails are retrieved and processed by Redmine

## Customization

### Email Processing Options

The script supports various Redmine email processing options. Edit `oauth_mail.sh` to customize:

```bash
# Example: Allow overriding project, tracker, and priority from email
allow_override=project,tracker,priority

# Example: Set default project
project=myproject

# Example: Move processed emails instead of deleting
move_on_success=Processed
move_on_failure=Failed
```

See [Redmine's email documentation](https://www.redmine.org/projects/redmine/wiki/RedmineReceivingEmails) for all available options.

### Different Email Folders

To check a folder other than INBOX:

```bash
folder=Redmine
```

## Troubleshooting

### "LOGIN failed" Error

- Verify OAuth2 token is being generated correctly
- Check that `mail_xoauth2` gem is installed
- Ensure the modified `imap.rb` is in place
- Verify Azure AD application permissions are granted

### "Permission denied" Errors

Check file permissions:
```bash
# Database should be writable by daemon user
sudo chown daemon:daemon /opt/bitnami/redmine/db/redmine.sqlite3
sudo chmod 664 /opt/bitnami/redmine/db/redmine.sqlite3

# Files directory should be writable
sudo chown -R daemon:daemon /opt/bitnami/redmine/files
sudo chmod -R 755 /opt/bitnami/redmine/files
```

### No Emails Being Processed

- Check Redmine logs: `/opt/bitnami/redmine/log/production.log`
- Verify the mailbox has unread emails
- Test the script manually with `sudo -u daemon ~/oauth_mail/oauth_mail.sh`
- Check cron is running: `sudo systemctl status cron`

## Security Notes

- Store the `oauth_mail.sh` script with restricted permissions (it contains credentials)
- Consider using environment variables or a separate config file for sensitive values
- The OAuth2 token expires after a period (typically 1 hour), which is why we fetch a new one each time
- Microsoft recommends migrating to certificate-based authentication for production use

## Compatibility

- **Tested with**: Redmine 6.1, Office 365
- **Should work with**: Redmine 4.x+, any OAuth2-compatible IMAP server
- **Modified files**: Only `lib/redmine/imap.rb` (no database changes)

## License

These modifications are provided as-is for use with Redmine. Redmine itself is licensed under GPL v2.

## Contributing

Improvements and bug fixes welcome! This was created to solve a specific need but may benefit others facing the same Office 365 authentication challenges.

## Acknowledgments

Based on the requirement that Office 365 no longer supports basic authentication and the need to maintain email-to-issue functionality in Redmine without switching to more complex solutions.

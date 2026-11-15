# Redmine OAuth2 Email Integration for Office 365

This repository contains the necessary files and instructions to enable Redmine to receive emails from Office 365 using OAuth2 authentication via IMAP. I can't claim to have invented this, it's just pulled together from various forum posts and put here in the hope that it will help someone else one day.

## Background

Microsoft no longer supports basic username/password authentication for IMAP access to Office 365 mailboxes. This solution implements OAuth2 authentication for Redmine's email receiver functionality.

## Solution Overview

This integration consists of:
1. Modified `imap.rb` file that adds OAuth2 support to Redmine's IMAP receiver
2. A shell script that obtains OAuth2 tokens and triggers email retrieval
3. The `mail_xoauth2` Ruby gem for OAuth2 IMAP authentication

There are two ways to get the token. Choose one:

| | App-only (`oauth_mail_app.sh`) | Delegated password (`oauth_mail.sh`) |
|---|---|---|
| Mailbox | Shared mailbox | User mailbox |
| Licence | Not needed | Needed |
| Mailbox password | Not used | Stored in the script |
| Token flow | Client credentials, `IMAP.AccessAsApp` | Resource owner password (ROPC), `IMAP.AccessAsUser.All` |
| Mailboxes the app can read | Only those granted to it in Exchange Online | The signed-in user's mailbox |

The app-only method is recommended. Microsoft advises against the password flow, and it stops working when the account needs MFA.

## Prerequisites

- Redmine installation (tested on 6.1, but should work on 4.x+)
- Office 365 mailbox for receiving Redmine emails (a shared mailbox for the app-only method)
- Microsoft Entra ID (Azure AD) application registration with appropriate permissions
- `jq` command-line JSON processor
- For the app-only method: an Exchange Online administrator, and the `ExchangeOnlineManagement` PowerShell module

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

### 2. Replace Redmine's IMAP Library

**Important: Backup the original file first!**

```bash
# Backup original file
sudo cp /opt/bitnami/redmine/lib/redmine/imap.rb /opt/bitnami/redmine/lib/redmine/imap.rb.original

# Replace with modified version
sudo cp imap.rb /opt/bitnami/redmine/lib/redmine/imap.rb
```

Then follow step 3 for the app-only method, or step 4 for the delegated password method.

### 3. App-only Setup (Shared Mailbox)

#### 3.1 Register the Application

1. Register an application in Microsoft Entra ID
2. Under API permissions, add **Office 365 Exchange Online** > **Application permissions** > `IMAP.AccessAsApp`
3. Grant admin consent for the permission
4. Create a client secret, and note its expiry date: mail stops when it expires
5. Note down:
   - Application (client) ID
   - Directory (tenant) ID
   - Client secret value
   - The **Object ID** shown under **Enterprise applications** for the app. This is not the Object ID on the App registrations page.

#### 3.2 Create the Shared Mailbox

Create a shared mailbox in the Microsoft 365 admin centre, or in Exchange Online PowerShell:

```powershell
Connect-ExchangeOnline -Organization <tenant-id>
New-Mailbox -Shared -Name "Redmine" -DisplayName "Redmine" -Alias redmine -PrimarySmtpAddress redmine@yourdomain.com
```

A shared mailbox needs no licence. A new shared mailbox can refuse IMAP login for about 15 minutes after it is created.

To keep an existing user mailbox, convert it to a shared mailbox instead (Microsoft 365 admin centre, or `Set-Mailbox -Identity redmine@yourdomain.com -Type Shared`). The mailbox must still be licensed when it is converted; the licence can be removed afterwards. Converting disables sign-in for the account, so the delegated password script stops working at that moment. To keep mail flowing, grant the permission in 3.3 and switch to `oauth_mail_app.sh` first, then convert. Mail that arrives in between stays in the mailbox and is picked up by the next run.

#### 3.3 Give the Application Access to the Mailbox

In Exchange Online PowerShell, register the application's service principal in Exchange, then grant it access to the shared mailbox only:

```powershell
Connect-ExchangeOnline -Organization <tenant-id>

New-ServicePrincipal -AppId <application-client-id> -ObjectId <enterprise-application-object-id> -DisplayName "EXO SP Redmine"

Add-MailboxPermission -Identity redmine@yourdomain.com -User <enterprise-application-object-id> -AccessRights FullAccess -AutoMapping:$false
```

The application can read only the mailboxes it is given `FullAccess` on. A login to any other mailbox with the same token is refused with `NO User is authenticated but not connected.`

The permission can take an hour or more to take effect. Until then the IMAP login is refused with the same message.

#### 3.4 Configure the Email Retrieval Script

1. Create directory for the script:
```bash
mkdir -p ~/oauth_mail
```

2. Copy `oauth_mail_app.sh` to `~/oauth_mail/oauth_mail_app.sh`, and `redmine-mail.env.example` to `~/oauth_mail/redmine-mail.env`

3. Edit `redmine-mail.env` and set:
   - `TENANT_ID`: Your directory (tenant) ID
   - `CLIENT_ID`: Your application (client) ID
   - `CLIENT_SECRET`: Your client secret value
   - `MAILBOX`: The shared mailbox address (e.g., redmine@yourdomain.com)

4. Update `CONFIG` and `REDMINE_DIR` at the top of the script if needed (defaults assume `/home/bitnami/oauth_mail` and `/opt/bitnami/redmine`)

5. Restrict both files to the user that runs the script, as they hold or read the client secret:
```bash
sudo chown daemon:daemon ~/oauth_mail/oauth_mail_app.sh ~/oauth_mail/redmine-mail.env
sudo chmod 700 ~/oauth_mail/oauth_mail_app.sh
sudo chmod 600 ~/oauth_mail/redmine-mail.env
```

The script passes the token to Redmine through the environment rather than on the command line, so it does not appear in a process list.

#### Redmine in a Docker Container

If Redmine runs in a container (for example the official `redmine` image with `mail_xoauth2` added and the modified `imap.rb` copied in), run the script on the host and replace the `cd` and `bundle exec rake` lines with a `docker exec` into the container:

```bash
docker exec -e password -u redmine redmine bundle exec rake redmine:email:receive_imap \
  host=outlook.office365.com port=993 ssl=1 username="$MAILBOX" \
  allow_override=project,tracker,priority
```

`-e password` passes the token from the host's environment into the container.

### 4. Delegated Password Setup (Licensed Mailbox)

#### 4.1 Configure the Azure AD Application

1. Register an application in Azure AD
2. Grant the following API permissions:
   - `IMAP.AccessAsUser.All`
   - `User.Read`
3. Enable "Allow public client flows" for the application
4. Note down:
   - Client ID
   - Client Secret
   - Tenant ID

#### 4.2 Configure the Email Retrieval Script

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
# App-only
sudo -u daemon ~/oauth_mail/oauth_mail_app.sh

# Delegated password
sudo -u daemon ~/oauth_mail/oauth_mail.sh
```

You should see any email processing messages (the delegated password script also shows curl progress output).

### 6. Set Up Automated Email Retrieval

Add a cron job to check for emails regularly:

```bash
# Edit daemon user's crontab
sudo crontab -u daemon -e

# Add this line to check every 5 minutes (use oauth_mail.sh for the delegated password method):
*/5 * * * * /home/bitnami/oauth_mail/oauth_mail_app.sh
```

## How It Works

### OAuth2 Token Detection

The modified `imap.rb` detects OAuth2 tokens by checking password length:
- Passwords > 30 characters: Treated as OAuth2 token, uses `authenticate('XOAUTH2')`
- Passwords ≤ 30 characters: Treated as regular password, uses standard `login()`

This allows backward compatibility with non-OAuth IMAP servers.

### Authentication Flow

1. The script requests an OAuth2 access token from Microsoft: `oauth_mail_app.sh` as the application (client credentials, scope `https://outlook.office365.com/.default`), `oauth_mail.sh` as the mailbox user (password grant)
2. Token is parsed using `jq` and stored in `$MSTOKEN` variable
3. Token is passed to Redmine's IMAP rake task as the password parameter (`oauth_mail_app.sh` passes it through the environment)
4. Modified `imap.rb` detects the long password and uses OAuth2 authentication
5. Emails are retrieved and processed by Redmine

## Customization

### Email Processing Options

The scripts support various Redmine email processing options. Edit `oauth_mail_app.sh` or `oauth_mail.sh` to customize:

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

### "User is authenticated but not connected" Error (App-only)

The token is valid, but the application has no access to the mailbox:

- Check the `FullAccess` permission in Exchange Online PowerShell: `Get-MailboxPermission -Identity redmine@yourdomain.com`
- Check that `New-ServicePrincipal` used the Enterprise application Object ID, not the App registration Object ID
- Wait: a new permission can take an hour or more to take effect, and a new shared mailbox about 15 minutes

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
- Test the script manually with `sudo -u daemon ~/oauth_mail/oauth_mail_app.sh` (or `oauth_mail.sh`)
- Check cron is running: `sudo systemctl status cron`

## Security Notes

- Store `redmine-mail.env` (app-only) or the `oauth_mail.sh` script (delegated password) with restricted permissions, as they contain credentials
- With the app-only method, the application can read only the mailboxes granted to it in Exchange Online. Grant `FullAccess` on the Redmine mailbox only.
- The client secret has an expiry date. Renew it before then and update `redmine-mail.env`, or mail-to-ticket stops.
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

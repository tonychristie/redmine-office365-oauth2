#!/bin/bash
#
# Redmine OAuth2 Email Retrieval Script for Office 365 - app-only (shared mailbox)
#
# Gets an app-only OAuth2 access token from Microsoft Entra ID with the client
# credentials flow and uses it to retrieve emails from an Office 365 shared
# mailbox via IMAP. No mailbox password and no licence are needed.
#
# Configuration:
# - Copy redmine-mail.env.example to the path in CONFIG below and fill it in
# - Adjust REDMINE_DIR if your installation is not in /opt/bitnami/redmine
#
# Usage:
# Run manually: sudo -u daemon ./oauth_mail_app.sh
# Or add to the daemon user's cron: */5 * * * * /home/bitnami/oauth_mail/oauth_mail_app.sh
#
set -euo pipefail

CONFIG=/home/bitnami/oauth_mail/redmine-mail.env
REDMINE_DIR=/opt/bitnami/redmine

# Sets TENANT_ID, CLIENT_ID, CLIENT_SECRET and MAILBOX
source "$CONFIG"

# Obtain an app-only OAuth2 access token from Microsoft
MSTOKEN=$(curl -s -X POST -H 'Content-type: application/x-www-form-urlencoded' \
  --data-urlencode "client_id=$CLIENT_ID" --data-urlencode "client_secret=$CLIENT_SECRET" \
  -d "scope=https://outlook.office365.com/.default&grant_type=client_credentials" \
  "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" | jq -r '.access_token')

# The token is passed by name through the environment so it does not appear in a process list.
export password="$MSTOKEN"

# Run Redmine's email receiver with the OAuth2 token
cd "$REDMINE_DIR"
bundle exec rake redmine:email:receive_imap \
  RAILS_ENV="production" \
  host=outlook.office365.com \
  port=993 \
  ssl=1 \
  username="$MAILBOX" \
  allow_override=project,tracker,priority

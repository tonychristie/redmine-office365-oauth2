#!/bin/bash
#
# Redmine OAuth2 Email Retrieval Script for Office 365
#
# This script obtains an OAuth2 access token from Microsoft Azure AD
# and uses it to retrieve emails from Office 365 via IMAP.
#
# Configuration:
# - Update the client_id, client_secret, username, and password below
# - Update the tenant ID in the OAuth URL
# - Adjust the Redmine path if your installation is not in /opt/bitnami/redmine
#
# Usage:
# Run manually: sudo -u daemon ./oauth_mail.sh
# Or add to cron: */5 * * * * /home/bitnami/oauth_mail/oauth_mail.sh
#

# Obtain OAuth2 access token from Microsoft
eval MSTOKEN=$(curl -X POST -H 'Content-type: application/x-www-form-urlencoded' \
  -d "client_id=YOUR_CLIENT_ID_HERE&\
scope=https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/User.Read&\
grant_type=password&\
username=redmine@yourdomain.com&\
password=YOUR_PASSWORD_HERE&\
client_secret=YOUR_CLIENT_SECRET_HERE" \
  https://login.microsoftonline.com/YOUR_TENANT_ID_HERE/oauth2/v2.0/token | jq -r '.access_token')

# Run Redmine's email receiver with OAuth2 token
cd /opt/bitnami/redmine
bundle exec rake -v -f /opt/bitnami/redmine/Rakefile redmine:email:receive_imap \
  RAILS_ENV="production" \
  host=outlook.office365.com \
  port=993 \
  ssl=1 \
  username=redmine@yourdomain.com \
  password=$MSTOKEN \
  allow_override=project,tracker,priority

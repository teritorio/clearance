#! /usr/bin/env python

# Modified file from
# https://github.com/geofabrik/sendfile_osm_oauth_protector/blob/master/oauth_cookie_client.py
# BSD-2-Clause license - Copyright 2018 Geofabrik GmbH

import argparse
import json
import logging
import re
import requests
import sys
import urllib.parse
from getpass import getpass

CUSTOM_HEADER = {"user-agent": "oauth_cookie_client.py"}

def report_error(message):
    logging.critical("{}".format(message))
    exit(1)


def find_authenticity_token(response):
    """
    Search the authenticity_token in the response of the server
    """
    pattern = r"name=\"csrf-token\" content=\"([^\"]+)\""
    m = re.search(pattern, response)
    if m is None:
        report_error("Could not find the authenticity_token in the website to be scraped.")
    try:
        return m.group(1)
    except IndexError:
        report_error("ERROR: The login form does not contain an authenticity_token.")


parser = argparse.ArgumentParser(description="Get a cookie to access service protected by OpenStreetMap OAuth 1.0a and osm-internal-oauth")
parser.add_argument("--insecure", action="store_false", help="Do not check SSL certificates. This is useful for development setups only.")
parser.add_argument("-l", "--log-level", help="Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)", default="INFO", type=str)
parser.add_argument("-o", "--output", default=None, help="write the cookie to the specified file instead to STDOUT", type=argparse.FileType("w+"))
parser.add_argument("-u", "--user", default=None, help="user name", type=str)
parser.add_argument("-p", "--password", default=None, help="Password, leave empty to force input from STDIN.", type=str)
parser.add_argument("-s", "--settings", default=None, help="JSON file containing parameters", type=argparse.FileType("r"))
parser.add_argument("-c", "--consumer-url", default=None, help="URL of the OAuth cookie generation API of the provider who provides you OAuth protected access to their ressources", type=str)
parser.add_argument("-f", "--format", default="http", help="Output format: 'http' for the value of the HTTP 'Cookie' header or 'netscape' for a Netscape-like cookie jar file", type=str, choices=["http", "netscape"])
parser.add_argument("--osm-host", default="https://www.openstreetmap.org/", help="hostname of the OSM API/website to use (e.g. 'www.openstreetmap.org' or 'master.apis.dev.openstreetmap.org')", type=str)

args = parser.parse_args()
settings = {}
if args.settings is not None:
    settings = json.load(args.settings)

# log level
numeric_log_level = getattr(logging, args.log_level.upper())
if not isinstance(numeric_log_level, int):
    raise ValueError("Invalid log level {}".format(args.log_level.upper()))
logging.basicConfig(level=numeric_log_level)


username = settings.get("user", args.user)
if username is None:
    username = input("Please enter your user name and press ENTER: ")
if username is None:
    report_error("The username must not be empty.")
password = settings.get("password", args.password)
if password is None:
    password = getpass("Please enter your password and press ENTER: ")
if len(password) == 0:
    report_error("The password must not be empty.")

osm_host = settings.get("osm_host", args.osm_host)
consumer_url = settings.get("consumer_url", args.consumer_url)
if consumer_url is None:
    report_error("No consumer URL provided")

# get request token
url = consumer_url + "?action=get_authorization_url"
r = requests.post(url, data={}, headers=CUSTOM_HEADER, verify=args.insecure)
if r.status_code != 200:
    report_error("POST {}, received HTTP status code {} but expected 200".format(url, r.status_code))
json_response = json.loads(r.text)
authorization_url = None
state = None
redirect_uri = None
client_id = None
try:
    authorization_url = json_response["authorization_url"]
    state = json_response["state"]
    redirect_uri = json_response["redirect_uri"]
    client_id = json_response["client_id"]
except KeyError:
    report_error("oauth_token was not found in the first response by the consumer")

# get OSM session
login_url = osm_host + "/login?cookie_test=true"
s = requests.Session()
r = s.get(login_url, headers=CUSTOM_HEADER)
if r.status_code != 200:
    report_error("GET {}, received HTTP code {}".format(login_url, r.status_code))

# login
authenticity_token = find_authenticity_token(r.text)
login_url = osm_host + "/login"
r = s.post(login_url, data={"username": username, "password": password, "referer": "/", "commit": "Login", "authenticity_token": authenticity_token}, allow_redirects=False, headers=CUSTOM_HEADER)
if r.status_code != 302:
    report_error("POST {}, received HTTP code {} but expected 302".format(login_url, r.status_code))
logging.debug("{} -> {}".format(r.request.url, r.headers["location"]))

# authorize
r = s.get(authorization_url, headers=CUSTOM_HEADER, allow_redirects=False)
if r.status_code != 302:
    # If authorization has been granted to the OAuth client yet, we will receive status 302. If not, status 200 should be returned and the form needs to be submitted.
    if r.status_code != 200:
        report_error("GET {}, received HTTP code {} but expected 200".format(authorization_url, r.status_code))
    authenticity_token = find_authenticity_token(r.text)

    post_data = {"client_id": client_id, "redirect_uri": redirect_uri, "authenticity_token": authenticity_token, "state": state, "response_type": "code", "scope": "read_prefs", "nonce": "", "code_challenge": "", "code_challenge_method": "", "commit": "Authorize"}
    r = s.post(authorization_url, data=post_data, headers=CUSTOM_HEADER, allow_redirects=False)
    if r.status_code != 302:
        report_error("POST {}, received HTTP code {} but expected 302".format(authorization_url, r.status_code))
else:
    logging.debug("{} -> {}".format(r.request.url, r.headers["location"]))
location = None
try:
    location = r.headers["location"]
except KeyError:
    report_error("Response headers of authorization request did not contain a location header.")
if "?" not in location:
    report_error("Redirect URL after authorization misses query string.")

# logout
logout_url = "{}/logout".format(osm_host)
r = s.get(logout_url, headers=CUSTOM_HEADER)
if r.status_code != 200 and r.status_code != 302:
    report_error("POST {}, received HTTP code {} but expected 200 or 302".format(logout_url, r.status_code))

# get final cookie
url = "{}&{}".format(location, urllib.parse.urlencode({"format": args.format}))
r = requests.get(url, headers=CUSTOM_HEADER, verify=args.insecure)

if not r.headers['Content-Type'].startswith('text/plain'):
    report_error("Expected response with Content-Type 'text/plain' but received '{}'. Maybe request contains bad credential.".format(r.headers['Content-Type']))

cookie_text = r.text
if not cookie_text.endswith("\n"):
    cookie_text += "\n"

if not args.output:
    sys.stdout.write(cookie_text)
else:
    args.output.write(cookie_text)

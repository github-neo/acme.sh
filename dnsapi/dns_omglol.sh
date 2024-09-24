#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_myapi_info='omg.lol
 Based on the omg.lol API, defined at https://api.omg.lol/
Domains: omg.lol
Site: github.com/acmesh-official/acme.sh/wiki/DNS-API-Dev-Guide
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_duckdns
Options:
 omglolapikey API Key from omg.lol.  This is accesible from the bottom of the account page at https://home.omg.lol/account
 omgloladdress This is your omg.lol address, without the preceding @ - you can see your list on your dashboard at https://home.omg.lol/dashboard
Issues: github.com/acmesh-official/acme.sh
Author: @Kholin <kholin+omglolapi@omg.lol>  
'

#returns 0 means success, otherwise error.

########  Public functions #####################

# Please Read this guide first: https://github.com/acmesh-official/acme.sh/wiki/DNS-API-Dev-Guide

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_omglol_add() {
  fulldomain=$1
  txtvalue=$2
  omglol_apikey="${omglol_apikey:-$(_readaccountconf_mutable omglol_apikey)}"
  omglol_address="${omglol_address:-$(_readaccountconf_mutable omglol_address)}"

  # As omg.lol includes a leading @ for their addresses, pre-strip this before save
  omglol_address="$(echo "$omglol_address" | tr -d '@')"

  _saveaccountconf_mutable omglol_apikey "$omglol_apikey"
  _saveaccountconf_mutable omglol_address "$omglol_address"

  _info "Using omg.lol."
  _debug "Function" "dns_omglol_add()"
  _debug "Full Domain Name" "$fulldomain"
  _debug "txt Record Value" "$txtvalue"
  _secure_debug "omg.lol API key" "$omglol_apikey"
  _debug "omg.lol Address" "$omglol_address"

  omglol_validate "$omglol_apikey" "$omglol_address" "$fulldomain"

  dnsName=$(_getDnsRecordName "$fulldomain" "$omglol_address")
  authHeader="$(_createAuthHeader "$omglol_apikey")"

  _debug2 "  dns_omglol_add(): Address" "$dnsName"

  omglol_add "$omglol_address" "$authHeader" "$dnsName" "$txtvalue"

}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_omglol_rm() {
  fulldomain=$1
  txtvalue=$2
  omglol_apikey="${omglol_apikey:-$(_readaccountconf_mutable omglol_apikey)}"
  omglol_address="${omglol_address:-$(_readaccountconf_mutable omglol_address)}"

  # As omg.lol includes a leading @ for their addresses, strip this in case provided
  omglol_address="$(echo "$omglol_address" | tr -d '@')"

  _info "Using omg.lol"
  _debug fulldomain "$fulldomain"
  _secure_debug ApiKey "$omglol_apikey"
  _debug address "$omglol_address"

  omglol_validate "$omglol_apikey" "$omglol_address" "$fulldomain"

  dnsName=$(_getDnsRecordName "$fulldomain" "$omglol_address")
  authHeader="$(_createAuthHeader "$omglol_apikey")"

  omglol_delete "$omglol_address" "$authHeader" "$dnsName" "$txtvalue"
}

####################  Private functions below ##################################
# Check that the minimum requirements are present.  Close ungracefully if not
omglol_validate() {
  omglol_apikey=$1
  omglol_address=$2
  fulldomain=$3

  if [ "" = "$omglol_address" ]; then
    _err "omg.lol base address not provided.  Exiting"
    exit 1
  fi

  if [ "" = "$omglol_apikey" ]; then
    _err "omg.lol API key not provided.  Exiting"
    exit 1
  fi

  _endswith "$fulldomain" "omg.lol"
  if [ ! $? ]; then
    _err "Domain name requested is not under omg.lol"
    exit 1
  fi

  _endswith "$fulldomain" "$omglol_address.omg.lol"
  if [ ! $? ]; then
    _err "Domain name is not a subdomain of provided omg.lol address $omglol_address"
    exit 1
  fi

  _debug "omglol_validate(): Required environment parameters are all present"
}

# Add (or modify) an entry for a new ACME query
omglol_add() {
  address=$1
  authHeader=$2
  dnsName=$3
  txtvalue=$4

  _info "  Creating DNS entry for $dnsName"
  _debug2 "  omglol_add()"
  _debug2 "  omg.lol Address: " "$address"
  _secure_debug2 "  omg.lol authorization header: " "$authHeader"
  _debug2 "  Full Domain name:" "$dnsName.$address.omg.lol"
  _debug2 "  TXT value to set:" "$txtvalue"

  export _H1="$authHeader"

  endpoint="https://api.omg.lol/address/$address/dns"
  _debug2 "  Endpoint" "$endpoint"

  payload='{"type": "TXT", "name":"'"$dnsName"'", "data":"'"$txtvalue"'", "ttl":30}'
  _debug2 "  Payload" "$payload"

  response=$(_post "$payload" "$endpoint" "" "POST" "application/json")

  omglol_validate_add "$response" "$dnsName.$address" "$txtvalue"
}

omglol_validate_add() {
  response=$1
  name=$2
  content=$3

  _info "  Validating DNS record addition"
  _debug2 "  omglol_validate_add()"
  _debug2 "  Response" "$response"
  _debug2 "  DNS Name" "$name"
  _debug2 "  DNS value" "$content"

  _jsonResponseCheck "$response" "success" "true"
  if [ "1" = "$?" ]; then
    _err "Response did not report success"
    return 1
  fi

  _jsonResponseCheck "$response" "message" "Your DNS record was created successfully."
  if [ "1" = "$?" ]; then
    _err "Response message did not indicate DNS record was successfully created"
    return 1
  fi

  _jsonResponseCheck "$response" "name" "$name"
  if [ "1" = "$?" ]; then
    _err "Response DNS Name did not match the response received"
    return 1
  fi

  _jsonResponseCheck "$response" "content" "$content"
  if [ "1" = "$?" ]; then
    _err "Response DNS Name did not match the response received"
    return 1
  fi

  _debug "  Record Created successfully"
  return 0
}

omglol_getRecords() {
  address=$1
  authHeader=$2
  dnsName=$3
  txtValue=$4

  _debug2 "    omglol_getRecords()"
  _debug2 "    omg.lol Address: " "$address"
  _secure_debug2 "    omg.lol Auth Header: " "$authHeader"
  _debug2 "    omg.lol DNS name:" "$dnsName"
  _debug2 "    txt Value" "$txtValue"

  export _H1="$authHeader"

  endpoint="https://api.omg.lol/address/$address/dns"
  _debug2 "    Endpoint" "$endpoint"

  payload=$(_get "$endpoint")

  _debug2 "    Received Payload:" "$payload"

  # Reformat the JSON to be more parseable
  recordID=$(echo "$payload" | _stripWhitespace)
  recordID=$(echo "$recordID" | _exposeJsonArray)

  # Now find the one with the right value, and caputre its ID
  recordID=$(echo "$recordID" | grep -- "$txtValue" | grep -i -- "$dnsName.$address")
  _getJsonElement "$recordID" "id"
}

omglol_delete() {
  address=$1
  authHeader=$2
  dnsName=$3
  txtValue=$4

  _info "  Deleting DNS entry for $dnsName with value $txtValue"
  _debug2 "  omglol_delete()"
  _debug2 "  omg.lol Address: " "$address"
  _secure_debug2 "  omg.lol Auth Header: " "$authHeader"
  _debug2 "  Full Domain name:" "$dnsName.$address.omg.lol"
  _debug2 "  txt Value" "$txtValue"

  record=$(omglol_getRecords "$address" "$authHeader" "$dnsName" "$txtvalue")

  endpoint="https://api.omg.lol/address/$address/dns/$record"
  _debug2 "  Endpoint" "$endpoint"

  export _H1="$authHeader"
  output=$(_post "" "$endpoint" "" "DELETE")

  _debug2 "  Response" "$output"

  omglol_validate_delete "$output"
}

# Validate the response on request to delete.  Confirm stastus is success and
# Message indicates deletion was successful
# Input: Response - HTTP response received from delete request
omglol_validate_delete() {
  response=$1

  _info "  Validating DNS record deletion"
  _debug2 "    omglol_validate_delete()"
  _debug "    Response" "$response"

  _jsonResponseCheck "$output" "success" "true"
  if [ "1" = "$?" ]; then
    _err "Response did not report success"
    return 1
  fi

  _jsonResponseCheck "$output" "message" "OK, your DNS record has been deleted."
  if [ "1" = "$?" ]; then
    _err "Response message did not indicate DNS record was successfully deleted"
    return 1
  fi

  _info "  Record deleted successfully"
  return 0
}

########## Utility Functions #####################################
# All utility functions only log at debug3
_jsonResponseCheck() {
  response=$1
  field=$2
  correct=$3

  correct=$(echo "$correct" | _lower_case)

  _debug3 "  jsonResponseCheck()"
  _debug3 "    Response to parse" "$response"
  _debug3 "    Field to get response from" "$field"
  _debug3 "    What is the correct response" "$correct"

  responseValue=$(_jsonGetLastResponse "$response" "$field")

  if [ "$responseValue" != "$correct" ]; then
    _debug3 "    Expected: $correct"
    _debug3 "      Actual: $responseValue"
    return 1
  else
    _debug3 "    Matched: $responseValue"
  fi
  return 0
}

_jsonGetLastResponse() {
  response=$1
  field=$2

  _debug3 "    jsonGetLastResponse()"
  _debug3 "      Response provided" "$response"
  _debug3 "      Field to get responses for" "$field"
  responseValue=$(echo "$response" | grep -- "\"$field\"" | cut -f2 -d":")

  _debug3 "      Response lines found:" "$responseValue"

  responseValue=$(echo "$responseValue" | sed 's/^ //g' | sed 's/^"//g' | sed 's/\\"//g')
  responseValue=$(echo "$responseValue" | sed 's/,$//g' | sed 's/"$//g')
  responseValue=$(echo "$responseValue" | _lower_case)

  _debug3 "      Responses found" "$responseValue"
  _debug3 "      Response Selected" "$(echo "$responseValue" | tail -1)"

  echo "$responseValue" | tail -1
}

_stripWhitespace() {
  tr -d '\n' | tr -d '\r' | tr -d '\t' | sed -r 's/ +/ /g' | sed 's/\\"//g'
}

_exposeJsonArray() {
  sed -r 's/.*\[//g' | tr '}' '|' | tr '{' '|' | sed 's/|, |/|/g' | tr '|' '\n'
}

_getJsonElement() {
  content=$1
  field=$2

  # With a single JSON entry to parse, convert commas to newlines puts each element on
  # its own line - which then allows us to just grep teh name, remove the key, and
  # isolate the value
  output=$(echo "$content" | tr ',' '\n' | grep -- "\"$field\":" | sed 's/.*: //g')

  _debug3 "    String before unquoting: $output"

  _unquoteString "$output"
}

_createAuthHeader() {
  apikey=$1

  authheader="Authorization: Bearer $apikey"
  _secure_debug2 "    Authorization Header" "$authheader"
  echo "$authheader"
}

_getDnsRecordName() {
  fqdn=$1
  address=$2

  echo "$fqdn" | sed 's/\.omg\.lol//g' | sed 's/\.'"$address"'$//g'
}

_unquoteString() {
  output=$1
  quotes=0

  _startswith "$output" "\""
  if [ $? ]; then
    quotes=$((quotes + 1))
  fi

  _endswith "$output" "\""
  if [ $? ]; then
    quotes=$((quotes + 1))
  fi

  _debug3 "    Original String: $output"
  _debug3 "    Quotes found: $quotes"

  if [ $((quotes)) -gt 1 ]; then
    output=$(echo "$output" | sed 's/^"//g' | sed 's/"$//g')
    _debug3 "    Quotes removed: $output"
  fi

  echo "$output"
}

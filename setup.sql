--ServiceNow Integration via Snowflake External Access
------------------------
--ServiceNow pre-reqs
--1. Create oauth application within ServiceNow and capture client_id + client_secret
--2. Leverage REST API Explorer to formulate REST calls - https://[instance_name].service-now.com/now/nav/ui/classic/params/target/%24restapi.do
--If need to batch calls look at ServiceNow Batch API - https://docs.servicenow.com/bundle/washingtondc-api-reference/page/integrate/inbound-rest/concept/batch-api.html
------------------------
--Before running file replace following placeholders
--[instance_name] = ServiceNow Instance Endpoint
--[clientid] = Client ID from ServiceNow OAuth Application Registry
--[clientsecret] = Client Secret from ServiceNow OAuth Application Registry
--[username] = ServiceNow user you want to use for ServiceNow REST calls
--[password] = Password ServiceNow user identified above
USE ROLE ACCOUNTADMIN;
USE DATABASE SNOWPARK;
USE SCHEMA EXTERNAL_ACCESS;
--Create outbound network rule to allow Snowflake to communicate with ServiceNow instance
CREATE OR REPLACE NETWORK RULE servicenow
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('[instance_name].service-now.com');

--Create and store secret for oauth token generation
CREATE OR REPLACE SECRET servicenow_secret
    TYPE = GENERIC_STRING
    SECRET_STRING = 'grant_type=password&client_id=[clientid]&client_secret=[clientsecret]&username=[username]&password=[password]';

--Create external access integration for Python code to use
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION servicenow
  ALLOWED_NETWORK_RULES = (servicenow)
  ALLOWED_AUTHENTICATION_SECRETS = (servicenow_secret)
  ENABLED = true;

--Grant integration and secret usage to standard / custom role
GRANT USAGE ON INTEGRATION servicenow TO ROLE SYSADMIN;
GRANT USAGE, READ ON SECRET servicenow_secret TO ROLE SYSADMIN;

--Use non-accountadmin to create objects
USE ROLE SYSADMIN;

--Create Python function to perform incident creation
CREATE OR REPLACE FUNCTION create_servicenow_incident(short_description text, urgency integer)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = 3.10
HANDLER = 'create_incident'
EXTERNAL_ACCESS_INTEGRATIONS = (servicenow)
SECRETS = ('cred' = servicenow_secret)
PACKAGES = ('requests')
AS
$$
import requests
import _snowflake
import json

def generate_oauth_token():
    url = "https://[instance_name].service-now.com/oauth_token.do"

    payload = _snowflake.get_generic_secret_string('cred')
    headers = {'Content-Type': 'application/x-www-form-urlencoded'}

    response = requests.post(url, headers=headers, data=payload)

    auth = json.loads(response.content)
    return auth['access_token']

def create_incident(short_description, urgency):
    auth_token=generate_oauth_token()

    body = {'short_description':short_description, 'urgency':urgency}

    url = 'https://[instance_name].service-now.com/api/now/table/incident'
    headers = {"Authorization": "Bearer " + auth_token}
    response = requests.post(url, headers=headers, json=body)
    if response.status_code==201:
        return "ServiceNow Incident Created"
    else:
        return "ServiceNow Incident Creation Failed"

$$;

--Call function to create incident in ServiceNow
SELECT create_servicenow_incident('Snowflake Incident 2',1);
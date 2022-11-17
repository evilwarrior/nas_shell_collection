#!/usr/bin/env python3

import msal, threading, os, requests
from datetime import datetime
from urllib.parse import urlparse, parse_qs
from uuid import UUID
from http.server import BaseHTTPRequestHandler
from http.server import HTTPServer
from platform import system

IS_WIN = system().lower() == 'windows'

KEEP_RUNNING = True
AUTH_RESP = {}

def is_valid_uuid(uuid):
    try:
        UUID(uuid)
        return True
    except ValueError:
        return False

class MsOAthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global KEEP_RUNNING
        global AUTH_RESP
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        ## Success URL
        #  http://<Host>[:<Port>]/callback?code=<CODE>&session_state=<UUID>#
        ## Failed URL
        #  http://<Host>[:<Port>]/callback?error=<ERROR>&error_description=<REASON>#
        query = parse_qs(urlparse(self.path).query)
        if ('code' in query and
            'session_state' in query and
            is_valid_uuid(query['session_state'][0])
           ) or (
            'error' in query and
            'error_description' in query
           ):
            AUTH_RESP = dict(zip(query, map(lambda x: x[1][0], query.items())))
            KEEP_RUNNING = False

    def log_message(self, format, *args):
        return

class RunHttpd(threading.Thread):
    def __init__(self, timeout=30):
        self.__timeout = timeout
        self.__timer = 0
        super().__init__()

    def __keep_running(self):
        global KEEP_RUNNING
        return KEEP_RUNNING

    def run(self):
        with HTTPServer(('0.0.0.0', 18000), MsOAthHandler) as httpd:
            httpd.timeout = 1
            while self.__keep_running():
                httpd.handle_request()
                self.__timer += 1
                if self.__timer >= self.__timeout:
                    global KEEP_RUNNING
                    KEEP_RUNNING = False


class MsGraph:
    def __init__(self, client_id, secret, scopes, token_path=os.path.join(os.getcwd(), 'token.json')):
        assert isinstance(client_id, str)
        assert isinstance(secret, str)
        assert isinstance(scopes, list)
        assert all(isinstance(ins, str) for ins in scopes)
        self.client_id = str(UUID(client_id))
        self.secret = secret
        self.scopes = scopes
        self.token_path = token_path
        ## Get Token from files if exists
        self.__token_cache = msal.SerializableTokenCache()
        with open(token_path, 'a+') as file:
            file.seek(0); cache = file.read()
            self.__token_cache.deserialize(cache)
            #import json
            #expir = int(list(map(lambda x: x[1], json.loads(cache)['AccessToken'].items()))[0]['expires_on'])
            #if datetime.now().timestamp() > expir:
            #    pass
        self.__client = msal.ConfidentialClientApplication(
                client_id=self.client_id,
                client_credential=self.secret,
                token_cache=self.__token_cache
        )
        self.client_valid = False

    def __acquire_token_by_auth_code(self, scopes):
        # Create Thread of httpd for receiving Microsoft Response parameters
        httpd_th = RunHttpd()
        httpd_th.start()
        ## Get Authorization Code by querying Microsoft Graph Authorization Request URL
        auth_req_url = self.__client.get_authorization_request_url(scopes)
        print( ('Browser will open the link below and process authorization\n\n'
                if IS_WIN else 'Open Brower and paste the link listed below on '
                'local host for authorization\n\n') + auth_req_url, '\n')
        if IS_WIN:
            import webbrowser
            webbrowser.open(auth_req_url, new=True)

        # Wait util get response from Microsoft
        while KEEP_RUNNING:
            pass

        ## Generate Token by Authorization Code
        if not AUTH_RESP or 'error' in AUTH_RESP:
            return AUTH_RESP

        auth_code = AUTH_RESP['code']
        acq_res = self.__client.acquire_token_by_authorization_code(
                code=auth_code,
                scopes=scopes
        )

        return acq_res

    def authorization(self):
        # Check Token if in cache
        accounts = self.__client.get_accounts()
        if accounts:
            res = self.__client.acquire_token_silent(self.scopes, accounts[0])
        else:
            res = self.__acquire_token_by_auth_code(self.scopes)

        if res and "error" not in res:
            self.client_valid = True
            with open(self.token_path, 'w') as file:
                file.write(self.__token_cache.serialize())

        return res

    def get_user_profile(self):
        # Retrieve Access Token
        res = self.authorization()
        if res and 'access_token' in res:
            token = res['access_token']
        else:
            return res

        # Send GET request to Microsoft Graph
        base_url = 'https://graph.microsoft.com/v1.0'
        endpoint = f'{base_url}/me'

        headers = {'Authorization': f'Bearer {token}'}

        return requests.get(endpoint, headers=headers).json()

    def list_mails(self):
        # Retrieve Access Token
        res = self.authorization()
        if res and 'access_token' in res:
            token = res['access_token']
        else:
            return res

        # Send GET request to Microsoft Graph
        base_url = 'https://graph.microsoft.com/v1.0'
        endpoint = f'{base_url}/me/messages'

        headers = {'Authorization': f'Bearer {token}'}

        return requests.get(endpoint, headers=headers).json()

    def send_mail(self, subject, recipients, content, content_type):
        assert isinstance(subject, str)
        assert isinstance(recipients, list)
        assert all(isinstance(ins, str) for ins in recipients)
        assert isinstance(content, str)
        assert isinstance(content_type, str)
        # Retrieve Access Token
        res = self.authorization()
        if res and 'access_token' in res:
            token = res['access_token']
        else:
            return res

        # Send POST request to Microsoft Graph
        base_url = 'https://graph.microsoft.com/v1.0'
        endpoint = f'{base_url}/me/sendMail'

        headers = { 'Authorization': f'Bearer {token}',
                    'Content-Type': 'application/json'}
        body = {
          "message": {
            "subject": subject,
            "body": {
              "contentType":content_type,
              "content": content
            },
            "toRecipients": list(map(lambda x: {"emailAddress": {"address": x}}, recipients))
          },
          "saveToSentItems": "false"
        }

        return requests.post(endpoint, headers=headers, json=body).status_code

if __name__ == '__main__':
    ## Create Graph Client
    client_id = ''
    secret = ''
    scopes = ['User.Read', 'Mail.Read', 'Mail.Send',]
    graph = MsGraph(client_id, secret, scopes, token_path='/root/.shell/ms_graph/token.json')

    log_fd = open('out.log' if IS_WIN else '/var/log/ms_graph.log', 'a+')
    log = {}

    ## Validate Graph Client
    graph.authorization()
    if not graph.client_valid:
        msg = '{} [ERROR]: Client was not authorized by Graph'.format(datetime.now().isoformat())
        print(msg)
        log_fd.write(msg + '\n')

    if graph.client_valid:
        ## Fetch Microsoft E5 account name
        profile = graph.get_user_profile()
        if 'userPrincipalName' in profile:
            log['account'] = profile['userPrincipalName']
        else:
            msg = '{} [ERROR]: Cannot retrieve userPrincipalName'.format(datetime.now().isoformat())
            print(msg)
            log_fd.write(msg + '\n')

        ## Count Emails
        mails = graph.list_mails()
        if 'value' in mails:
            log['count'] = len(mails['value'])
        else:
            msg = '{} [ERROR]: Cannot count the number of Emails'.format(datetime.now().isoformat())
            print(msg)
            log_fd.write(msg + '\n')

        if 'account' in log and 'count' in log:
            log = '{} [INFO]: Read {} Email{} from {}'.format(
                    datetime.now().isoformat(),
                    log['count'],
                    '' if log['count'] == 1 else 's',
                    log['account'])
            print(log)
            log_fd.write(log + '\n')

    log_fd.close()

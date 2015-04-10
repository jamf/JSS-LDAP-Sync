# JSS LDAP Sync

## What were we trying to solve?

Departments and Buildings are objects in the JSS and do not sync from the directory. With the many changes in our org structure, the location data in our inventory was becoming inaccurate, showing blank department and/or building fields because we had yet to create the matching JSS object for the new label on the user's account in AD. To automate this process, we wrote a script that creates and deletes Departments and Buildings in the JSS based on our user accounts in AD.

## What does it do?

When run, the script will prompt for the address to an LDAP server, the JSS and then for credentials (in our environment I wrote this script to take the first.last username and parse it into 'First Last' for the LDAP authentication - it also assumed you are using the same account for both servers). The distinguished name (DN) of the OU is hardcoded inside the main() function (you can also optionally hard code the other values for LDAP server address, JSS address and credentials there).

It will then parse all of the accounts in the Staff OU to build two lists: departments and buildings. Then it will read from the JSS all departments and buildings into two other lists. The LDAP and JSS lists will be compared. All departments and buildings that do not exist in the JSS but do in LDAP will be added to a "Create" list. All departments and buildings that exist in the JSS but not in LDAP will be added to a "Delete" list. The script will then begin creating and deleting the required departments and buildings. Once complete the list of Department and Building objects in the JSS will match what is in LDAP.

## How to use this script

This Python script can be run on Mac, Linux and Windows (Python version 2.7.6 tested). The script requires the "python-ldap" and "requests" modules which you can install on your system or in a virtual environment using the requirements.txt file.

```
pip install -r /path/to/requirements.txt
``` 

If you do not hard code the values for the servers and credentials, you will be prompted for them.

## License

```
JAMF Software Standard License

Copyright (c) 2015, JAMF Software, LLC. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted
provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, this list of
      conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, this list of
      conditions and the following disclaimer in the documentation and/or other materials
      provided with the distribution.
    * Neither the name of the JAMF Software, LLC nor the names of its contributors may be
      used to endorse or promote products derived from this software without specific prior
      written permission.

THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

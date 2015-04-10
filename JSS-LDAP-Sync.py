import getpass
import ldap
import requests
import sys
import urllib
import xml.etree.cElementTree as etree


class LDAPs:
    def __init__(self, server, account, password, staff_ou):
        # Force ldap to use SSL and not TLS for connections
        self.staff_ou = staff_ou
        self.account = 'CN={0},{1}'.format(account, self.staff_ou)
        ldap.set_option(ldap.OPT_X_TLS_REQUIRE_CERT, ldap.OPT_X_TLS_NEVER)
        self.l = ldap.initialize(server)
        self.bind(password)

    def bind(self, password):
        try:
            self.l.simple_bind_s(self.account, password)
        except ldap.INVALID_CREDENTIALS:
            print("Invalid credentials")
            sys.exit(1)
        except ldap.SERVER_DOWN:
            print("Server unavailable")
            sys.exit(1)

    def staff_members(self, dn=None):
        if not dn:
            dn = self.staff_ou
        return self.l.search_s(dn, ldap.SCOPE_ONELEVEL)

    def unbind(self):
            self.l.unbind_s()


class JSS(object):
    def __init__(self, url, username, password):
        self.s = requests.Session()
        self.s.auth = (username, password)
        self.url = '{}/JSSResource'.format(url)

    def get_departments(self):
        """Returns a list of 'names'"""
        new_list = list()
        resp = self.s.get('{}/departments'.format(self.url))
        root = etree.fromstring(resp.text)
        for i in root.findall('department'):
            new_list.append(i.findtext('name'))

        return new_list

    def get_buildings(self):
        """Returns a list of 'names'"""
        new_list = list()
        resp = self.s.get('{}/buildings'.format(self.url))
        root = etree.fromstring(resp.text)
        for i in root.findall('building'):
            new_list.append(i.findtext('name'))

        return new_list

    def create_department(self, name):
        """Builds an XML string from 'name'"""
        root = etree.Element('department')
        etree.SubElement(root, 'name').text = name
        print("Creating department: {}".format(name))
        self.s.post('{}/departments/id/0'.format(self.url), data=etree.tostring(root))

    def create_building(self, name):
        """Builds an XML string from 'name'"""
        root = etree.Element('building')
        etree.SubElement(root, 'name').text = name
        print("Creating building: {}".format(name))
        self.s.post('{}/buildings/id/0'.format(self.url), data=etree.tostring(root))

    def delete_department(self, name):
        print("Deleting department: {}".format(name))
        self.s.delete('{}/departments/name/{}'.format(self.url, name))

    def delete_building(self, name):
        print("Deleting building: {}".format(name))
        self.s.delete('{}/buildings/name/{}'.format(self.url, name))


def ldap_lists(staff):
    print("Parsing {} staff records...".format(len(staff)))
    departments = list()
    buildings = list()
    for member in staff:
        try:
            dept = member[1]['department'][0]
        except KeyError:
            pass
        else:
            if dept not in departments:
                print('Found department "{}"'.format(dept))
                departments.append(dept)

        try:
            bldg = member[1]['physicalDeliveryOfficeName'][0]
        except KeyError:
            pass
        else:
            if bldg not in buildings:
                print('Found building "{}"'.format(bldg))
                buildings.append(bldg)

    print("{} departments and {} buildings exist in LDAP".format(len(departments), len(buildings)))
    return departments, buildings


def compare_lists(ldap_list, jss_list):
    create = list()
    delete = list()
    for i in ldap_list:
        if i not in jss_list:
            create.append(i)

    for i in jss_list:
        if i not in ldap_list:
            delete.append(i)

    return create, delete


def main():
    ldap_server = None
    jss_url = None
    jss_username = None
    ldap_account = None
    # Assumes the LDAP and JSS password for the user are the same
    password = None
    ldap_password = None

    # The staff OU that wil be used (it is assumed the authenticating user resides in this OU)
    staff_ou = 'OU=Staff,DC=yourorg,DC=corp'

    if not ldap_server:
        ldap_server = str(raw_input("LDAP Server: "))
        if not ldap_server.startswith('ldaps://'):
            ldap_server = 'ldaps://{0}'.format(ldap_server)

    if not jss_url:
        jss_url = str(raw_input("JSS URL: "))

    if not jss_username:
        jss_username = str(raw_input("Username: "))
        split = jss_username.split('.')
        # Assuming first.last naming convention, the script will attempt to auto-generate the LDAP user's CN
        if len(split) == 1:
            ldap_account = jss_username.capitalize()
        elif len(split) == 2:
            ldap_account = '{0} {1}'.format(split[0].capitalize(), split[1].capitalize())
        else:
            ldap_account = str(raw_input("LDAP User(CN): "))

    if not password:
        password = getpass.getpass("Password: ")
        if not ldap_password:
            ldap_password = password

    l = LDAPs(ldap_server, ldap_account, ldap_password, staff_ou)
    jss = JSS(jss_url, jss_username, password)

    print("Reading accounts in {} in LDAP".format(l.staff_ou))
    ldap_departments, ldap_buildings = ldap_lists(l.staff_members())
    l.unbind()
    # print ldap_departments
    # print ldap_buildings
    jss_departments = jss.get_departments()
    jss_buildings = jss.get_buildings()

    create_departments, delete_departments = compare_lists(ldap_departments, jss_departments)
    print("{} department(s) will be created and {} department(s) will be deleted in the JSS".format(
        len(create_departments), len(delete_departments)))
    create_buildings, delete_buildings = compare_lists(ldap_buildings, jss_buildings)
    print("{} buildings(s) will be created and {} building(s) will be deleted in the JSS".format(
        len(create_buildings), len(delete_buildings)))

    for i in create_departments:
        jss.create_department(i)

    for i in delete_departments:
        jss.delete_department(i)

    for i in create_buildings:
        jss.create_building(i)

    for i in delete_buildings:
        jss.delete_building(i)

    print("Done\n")
    sys.exit(0)

if __name__ == '__main__':
    main()
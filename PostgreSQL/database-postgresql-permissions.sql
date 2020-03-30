-- we create a role, or group
CREATE ROLE delivery NOLOGIN;

-- we create a user in that group

CREATE USER postie WITH LOGIN PASSWORD '[change me]' IN ROLE delivery;

-- we grant permission to the group

GRANT INSERT, SELECT                 ON incoming_packages TO GROUP delivery;
GRANT INSERT, SELECT, UPDATE         ON host              TO GROUP delivery;
GRANT INSERT, SELECT, UPDATE         ON package           TO GROUP delivery;
GRANT INSERT, SELECT, UPDATE         ON package_version   TO GROUP delivery;
GRANT INSERT, SELECT, UPDATE, DELETE ON host_package      TO GROUP delivery;


CREATE ROLE reporting NOLOGIN;

GRANT SELECT ON host TO GROUP reporting;

These are the proposed database tables and corresponding queries.

host
====
```
id
name
os
version
repo
```

package
=======
```
id
name (e.g. foo)
```

package_version
===============
```
id
package_id
version (e.g. 1.2.3)
````

host_package
============
```
host_id
package_version_id
````

Show me all host with foo-1.2.3 installed.

````
SELECT H.name
  FROM package P JOIN package_version PV ON P.name     = 'foo' 
                                        AND P.id       = PV.package_id
                                        AND PV.version = '1.2.3'
                 JOIN host_package HP    ON PV.id      = HP.package_version_id
                 JOIN host         H     ON PV.host_id = H.id
  ORDER BY 1;
```

Show me all the packages installed on HOST bar

```
SELECT P.name || '-' || PV.version
  FROM host H JOIN host_package    HP ON H.name                = 'bar'
                                     AND H.id                  = HP.host_id
              JOIN package_version PV ON HP.package_version_id = PV.id
              JOIN package         P  ON HP.package_id         = P.id
  ORDER BY 1;
```

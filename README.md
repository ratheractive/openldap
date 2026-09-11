# openldap

OpenLDAP 2.6 on Alpine, ~25 MB, built weekly from Alpine's package so security
fixes flow through. Configured from environment variables on first start, with
optional LDIF bootstrap. Made for the ratheractive platform; generic enough for
anyone who wants a small, standard OpenLDAP without a framework around it.

```
docker run -d -p 389:389 -v ldap:/data \
  -e LDAP_SUFFIX=dc=example,dc=org -e LDAP_ROOT_PASSWORD=secret \
  ghcr.io/ratheractive/openldap:2.6
```

## What you get

- `mdb` database at `/data/db`, `cn=config` at `/data/config` - one volume
- overlays: `memberof` (on `groupOfUniqueNames`/`uniqueMember`), `refint`, `ppolicy`
  (hashes clear-text passwords with SSHA; policy entry via `LDAP_PPOLICY_DEFAULT`)
- schemas: core, cosine, nis, inetorgperson, openssh-lpk (`sshPublicKey`)
- ACL: users read everything, write their own password; anonymous may only bind;
  the root DN writes; root on the container manages `cn=config` over `ldapi://`
- `ldap://` and `ldapi://` always; `ldaps://` when `LDAP_TLS_CERT` and `LDAP_TLS_KEY` exist

## Environment

| Variable | Default | |
| --- | --- | --- |
| `LDAP_SUFFIX` | required | `dc=example,dc=org` |
| `LDAP_ROOT_DN` | `cn=admin,$LDAP_SUFFIX` | |
| `LDAP_ROOT_PASSWORD` / `_FILE` | required | also the `cn=config` password |
| `LDAP_ORGANISATION` | the suffix | `o` of the base entry when no bootstrap LDIF |
| `LDAP_PPOLICY_DEFAULT` | none | DN of a `pwdPolicy` entry to apply to everyone |
| `LDAP_PASSWORD_MANAGER_DN` | none | a DN granted write on everyone's `userPassword` (a self-service password tool binds as this) |
| `LDAP_LOG_LEVEL` | `stats` | slapd `-d` level |
| `LDAP_TLS_CERT`, `LDAP_TLS_KEY`, `LDAP_TLS_CA` | none | file paths |
| `LDAP_URLS` | `ldap:/// ldapi://%2Frun%2Fopenldap%2Fldapi` | `+ ldaps:///` when TLS is configured |

## Bootstrap

Put `*.ldif` files in `/bootstrap`. On first start they are loaded with `slapadd`
in name order - a full `slapcat`/`ldapsearch` export of another directory works
as-is, password hashes included. Without them the base entry is created empty.
Nothing in `/bootstrap` is read again once `/data/config` exists.

## Managing

There is deliberately no admin UI in the image. `ldapadd`/`ldapmodify` with the
root DN, or from inside the container as root over the socket:

```
docker exec -it ldap ldapsearch -Y EXTERNAL -H ldapi://%2Frun%2Fopenldap%2Fldapi -b cn=config -LLL olcDatabase={1}mdb
```

#!/bin/sh
# First start (no config under /data/config): build the cn=config database from
# the environment, then load the data database from /bootstrap/*.ldif if any,
# else create the bare suffix entry. Every later start just runs slapd.
#
#   LDAP_SUFFIX            required   e.g. dc=example,dc=org
#   LDAP_ROOT_DN           default    cn=admin,$LDAP_SUFFIX
#   LDAP_ROOT_PASSWORD     required   (or LDAP_ROOT_PASSWORD_FILE)
#   LDAP_ORGANISATION      default    the suffix - only used when no bootstrap LDIF
#   LDAP_PPOLICY_DEFAULT   optional   DN of the default pwdPolicy entry
#   LDAP_PASSWORD_MANAGER_DN optional DN allowed to write userPassword of everyone (for a self-service password tool)
#   LDAP_LOG_LEVEL         default    stats
#   LDAP_TLS_CERT/KEY/CA   optional   file paths; when cert+key exist ldaps:/// is served too
#   LDAP_URLS              default    "ldap:/// ldapi://%2Frun%2Fopenldap%2Fldapi" (+ ldaps:/// with TLS)
set -eu
DATA=${LDAP_DATA_DIR:-/data}; CONF=$DATA/config; DB=$DATA/db
: "${LDAP_SUFFIX:?LDAP_SUFFIX is required}"
LDAP_ROOT_DN=${LDAP_ROOT_DN:-cn=admin,$LDAP_SUFFIX}
if [ -n "${LDAP_ROOT_PASSWORD_FILE:-}" ]; then LDAP_ROOT_PASSWORD=$(cat "$LDAP_ROOT_PASSWORD_FILE"); fi
: "${LDAP_ROOT_PASSWORD:?LDAP_ROOT_PASSWORD (or _FILE) is required}"
LOG=${LDAP_LOG_LEVEL:-stats}
# Alpine compiles the default ldapi socket path under /var/lib/openldap, which this
# image does not keep; the socket lives at /run/openldap/ldapi (URL-encoded below)
LDAPI="ldapi://%2Frun%2Fopenldap%2Fldapi"
URLS=${LDAP_URLS:-"ldap:/// $LDAPI"}
TLS=""
if [ -n "${LDAP_TLS_CERT:-}" ] && [ -f "$LDAP_TLS_CERT" ] && [ -f "${LDAP_TLS_KEY:-/nonexistent}" ]; then
  TLS="olcTLSCertificateFile: $LDAP_TLS_CERT
olcTLSCertificateKeyFile: $LDAP_TLS_KEY"
  [ -n "${LDAP_TLS_CA:-}" ] && TLS="$TLS
olcTLSCACertificateFile: $LDAP_TLS_CA"
  [ "${LDAP_URLS:-}" = "" ] && URLS="ldap:/// ldaps:/// $LDAPI"
fi
mkdir -p /run/openldap && chown ldap:ldap /run/openldap

if [ ! -f "$CONF/cn=config.ldif" ]; then
  echo "entrypoint: no configuration in $CONF - bootstrapping"
  mkdir -p "$CONF" "$DB"
  HASH=$(slappasswd -s "$LDAP_ROOT_PASSWORD")
  PPOLICY=""
  [ -n "${LDAP_PPOLICY_DEFAULT:-}" ] && PPOLICY="olcPPolicyDefault: $LDAP_PPOLICY_DEFAULT"
  PWMGR=""
  [ -n "${LDAP_PASSWORD_MANAGER_DN:-}" ] && PWMGR="by dn.exact=$LDAP_PASSWORD_MANAGER_DN write"
  cat > /tmp/config.ldif <<CFG
dn: cn=config
objectClass: olcGlobal
cn: config
olcPidFile: /run/openldap/slapd.pid
olcArgsFile: /run/openldap/slapd.args
olcLogLevel: $LOG
$TLS

dn: cn=module{0},cn=config
objectClass: olcModuleList
cn: module{0}
olcModulePath: /usr/lib/openldap
olcModuleLoad: back_mdb.so
olcModuleLoad: memberof.so
olcModuleLoad: ppolicy.so
olcModuleLoad: refint.so

dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema

include: file:///etc/openldap/schema/core.ldif
include: file:///etc/openldap/schema/cosine.ldif
include: file:///etc/openldap/schema/nis.ldif
include: file:///etc/openldap/schema/inetorgperson.ldif
include: file:///etc/openldap/schema/openssh-lpk.ldif

dn: olcDatabase={-1}frontend,cn=config
objectClass: olcDatabaseConfig
objectClass: olcFrontendConfig
olcDatabase: {-1}frontend
olcAccess: to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break
olcPasswordHash: {SSHA}

dn: olcDatabase={0}config,cn=config
objectClass: olcDatabaseConfig
olcDatabase: {0}config
olcRootDN: cn=admin,cn=config
olcRootPW: $HASH
olcAccess: to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break

dn: olcDatabase={1}mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: {1}mdb
olcDbDirectory: $DB
olcSuffix: $LDAP_SUFFIX
olcRootDN: $LDAP_ROOT_DN
olcRootPW: $HASH
olcDbMaxSize: 1073741824
olcDbIndex: objectClass eq
olcDbIndex: uid eq
olcDbIndex: cn,sn,mail eq,sub
olcDbIndex: member,uniqueMember,memberUid eq
olcDbIndex: entryUUID,entryCSN eq
olcLastMod: TRUE
olcAccess: to attrs=userPassword,shadowLastChange by self write by dn.exact=$LDAP_ROOT_DN write $PWMGR by anonymous auth by * none
olcAccess: to * by self read by dn.exact=$LDAP_ROOT_DN write by users read by anonymous auth

dn: olcOverlay={0}memberof,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcMemberOf
olcOverlay: {0}memberof
olcMemberOfRefInt: TRUE
olcMemberOfGroupOC: groupOfUniqueNames
olcMemberOfMemberAD: uniqueMember
olcMemberOfMemberOfAD: memberOf

dn: olcOverlay={1}refint,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcRefintConfig
olcOverlay: {1}refint
olcRefintAttribute: uniqueMember
olcRefintAttribute: member

dn: olcOverlay={2}ppolicy,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcPPolicyConfig
olcOverlay: {2}ppolicy
olcPPolicyHashCleartext: TRUE
olcPPolicyUseLockout: FALSE
$PPOLICY
CFG
  slapadd -F "$CONF" -n 0 -l /tmp/config.ldif
  rm -f /tmp/config.ldif
  if ls /bootstrap/*.ldif >/dev/null 2>&1; then
    # The memberof overlay only maintains memberOf for entries that pass through
    # slapd; slapadd bypasses it. So: slapadd everything that is not a group, then
    # start slapd on the socket only and ldapadd the groups through it.
    mkdir -p /tmp/bootstrap; rm -f /tmp/bootstrap/*
    for f in /bootstrap/*.ldif; do
      b=$(basename "$f" .ldif)
      awk -v RS= -v ORS='\n\n' -v u="/tmp/bootstrap/$b.users.ldif" -v g="/tmp/bootstrap/$b.groups.ldif" \
        '/objectClass: groupOf(Unique)?Names/ {print > g; next} {print > u}' "$f"
    done
    for f in /tmp/bootstrap/*.users.ldif; do [ -s "$f" ] || continue; echo "entrypoint: loading $f"; slapadd -F "$CONF" -n 1 -q -l "$f"; done
    chown -R ldap:ldap "$DATA"
    if ls /tmp/bootstrap/*.groups.ldif >/dev/null 2>&1 && cat /tmp/bootstrap/*.groups.ldif | grep -q '^dn:'; then
      slapd -F "$CONF" -h "$LDAPI" -u ldap -g ldap
      for i in $(seq 1 50); do ldapwhoami -x -H "$LDAPI" -D "$LDAP_ROOT_DN" -w "$LDAP_ROOT_PASSWORD" >/dev/null 2>&1 && break; sleep 0.2; done
      for f in /tmp/bootstrap/*.groups.ldif; do [ -s "$f" ] || continue; echo "entrypoint: loading $f (through slapd, for memberOf)"; ldapadd -x -H "$LDAPI" -D "$LDAP_ROOT_DN" -w "$LDAP_ROOT_PASSWORD" -f "$f" >/dev/null; done
      pid=$(cat /run/openldap/slapd.pid); kill "$pid"
      while [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
    fi
    rm -rf /tmp/bootstrap
  else
    ORG=${LDAP_ORGANISATION:-$LDAP_SUFFIX}
    RDN=${LDAP_SUFFIX%%,*}; ATTR=${RDN%%=*}; VAL=${RDN#*=}
    printf 'dn: %s\nobjectClass: top\nobjectClass: dcObject\nobjectClass: organization\n%s: %s\no: %s\n' "$LDAP_SUFFIX" "$ATTR" "$VAL" "$ORG" | slapadd -F "$CONF" -n 1 -q
  fi
  chown -R ldap:ldap "$DATA"
  echo "entrypoint: bootstrap complete"
fi
chown -R ldap:ldap "$DATA" /run/openldap
exec slapd -F "$CONF" -h "$URLS" -u ldap -g ldap -d "$LOG"

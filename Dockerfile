# OpenLDAP on Alpine - the ratheractive platform's directory server.
# Alpine packages OpenLDAP 2.6 and tracks upstream security fixes; the image
# is rebuilt weekly by .github/workflows/build.yaml so those flow through.
FROM alpine:3.22
RUN apk add --no-cache \
      openldap openldap-back-mdb \
      openldap-overlay-memberof openldap-overlay-ppolicy openldap-overlay-refint \
      openldap-clients \
  && mkdir -p /data /bootstrap /run/openldap \
  && chown ldap:ldap /run/openldap \
  && rm -rf /var/lib/openldap /etc/openldap/slapd.d /etc/openldap/slapd.ldif
COPY schema/openssh-lpk.ldif /etc/openldap/schema/openssh-lpk.ldif
COPY entrypoint.sh /entrypoint.sh
VOLUME /data
EXPOSE 389 636
HEALTHCHECK --interval=30s --timeout=5s CMD ldapsearch -x -H ldap://127.0.0.1 -b '' -s base 1.1 >/dev/null || exit 1
ENTRYPOINT ["/entrypoint.sh"]

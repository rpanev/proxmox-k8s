apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare
spec:
  acme:
    email: ${ACME_EMAIL}
    server: ${ACME_SERVER}
    privateKeySecretRef:
      name: letsencrypt-cloudflare-account-key
    solvers:
      - selector:
          dnsZones:
            - "${CLOUDFLARE_DNS_ZONE}"
        dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token

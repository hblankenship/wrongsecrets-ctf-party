apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: ctfd
  name: ctfd
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: instance
    alb.ingress.kubernetes.io/success-codes: 200-399
    #uncomment and configure below if you want to use tls, don't forget to override the cookie to a secure value!
    # alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
    # alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS":443}]'
    # alb.ingress.kubernetes.io/ssl-redirect: "443"
    # external-dns.alpha.kubernetes.io/hostname: ${CTFD_DOMAIN_NAME}
    # The certificate ARN can be discovered automatically by the ALB Ingress Controller based on the host value in the ingress, or you can specify it manually by uncommenting and customizing the line below
    # alb.ingress.kubernetes.io/certificate-arn: <certificate-arn>
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ctfd
                port:
                  number: 80
      host: ${CTFD_DOMAIN_NAME} # Specify the hostname to route to the service

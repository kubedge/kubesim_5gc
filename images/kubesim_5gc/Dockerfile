FROM scratch
ADD kubesim_5gc/ca-certificates.crt /etc/ssl/certs/
ADD kubesim_5gc/goserv /goserv
EXPOSE 8080
CMD ["/goserv"]

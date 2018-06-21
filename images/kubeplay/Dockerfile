FROM amd64/scratch
ADD kubeplay/ca-certificates.crt /etc/ssl/certs/
ADD kubeplay/goserv /goserv
EXPOSE 8080
CMD ["/goserv"]

Enabling SSL for the web configuration pages requires some setup work. You will
need either a valid SSL certificate and its corresponding private key, or a
self-signed certificate. StilleBot can automatically generate a self-signed
cert, but a new one will be created each time the bot is restarted, making it
inadvisable *and* inconvenient. Instead, create a certificate externally, and
have StilleBot make use of it.

If you do not already own a valid certificate, one option is LetsEncrypt, which
can generate browser-supported certs fairly conveniently. However, you may need
to reformat the private key:

    openssl rsa -in ....../privkey.pem >..../privkey.pem

The "fullchain" certificate from LetsEncrypt is directly usable. If you obtain
a certificate that comes with a separate authority chain (GoDaddy is known to
do this), simply concatenate the two files.

Store the private key in `privkey.pem` and the cert(s) in `certificate.pem`.
Note that protecting your private key is important. StilleBot is entirely okay
with these files being symlinks or named pipes or other non-normal files.

Configure the server's externally-accessible address and port in "Authenticate
Manually", specifying `https://` to enable encryption. To have StilleBot listen
on a different port, specify that in the listen port - not normally necessary,
but can allow fancy tricks like redirecting to different port numbers in NAT.
By default, StilleBot will listen on all available addresses (IPv4 and IPv6);
if this causes problems, explicitly select a listening address such as
`"0.0.0.0:6789"` (any IPv4 address, no IPv6) or `"192.168.1.1:443"` (specific
address - any other address won't be responsive).

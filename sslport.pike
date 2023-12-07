void accept(object mainsock) {
	object sock = mainsock->accept();
	mapping certinfo = sock->get_peer_certificate_info();
	if (certinfo) werror("Got connection, certificate is for %O\n", certinfo->cn[0][0][-1]->value);
	//werror("Cert info: %O\n", certinfo);
	//werror("Certs: %O\n", sock->get_peer_certificates());
	sock->set_nonblocking(sockread);
}

void sockread(object sock, string data) {werror("Data from client: %O\n", data); sock->close();}

int main() {
	string key = Stdio.read_file("privkey_local.pem");
	string cert = Stdio.read_file("certificate_local.pem");
	object ctx = SSL.Context();
	ctx->add_cert(Standards.PEM.simple_decode(key), Standards.PEM.Messages(cert)->get_certificates(), ({"*"}));
	array issuers = ({
		"/etc/ssl/certs/ISRG_Root_X1.pem",
	});
	array roots = Standards.PEM.Messages(Stdio.read_file(issuers[*])[*])->get_certificates();
	ctx->set_trusted_issuers(roots);
	ctx->set_authorities(roots * ({ }));
	ctx->auth_level = SSL.Constants.AUTHLEVEL_ask;
	if (!SSL.Port(ctx)->bind(2211, accept)) exit(1, "Unable to bind to port\n");
	werror("Listening on 2211.\n");
	return -1;
}

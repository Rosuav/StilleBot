class SSLContext {
	inherit SSL.Context;
	array|zero find_cert_issuer(array(string) ders) {
		if (sizeof(cert_chains_issuer)) return values(cert_chains_issuer)[0]; //Return the first available cert
		return ::find_cert_issuer(ders);
	}
}

int main() {
	string key = Stdio.read_file("privkey.pem");
	string cert = Stdio.read_file("certificate.pem");
	object ctx = SSLContext();
	array(string) root = Standards.PEM.Messages(Stdio.read_file("/etc/ssl/certs/ISRG_Root_X1.pem"))->get_certificates();
	ctx->add_cert(Standards.PEM.simple_decode(key), Standards.PEM.Messages(cert)->get_certificates() + root);
	//* //Attempt to use the new ssl_context feature
	object sql = Sql.Sql("pgsql://rosuav@sikorsky.rosuav.com/stillebot", ([
		"force_ssl": 1, "ssl_context": ctx, "application_name": "pgssl-test",
	]));
	werror("Connection: %O\n", sql);
	sql->set_notify_callback("readonly") {
		werror("GOT NOTIFY %O\n", __ARGS__);
		werror("Read-only now %O\n", sql->query("show default_transaction_read_only")[0]->default_transaction_read_only);
	};
	sql->query("listen readonly");
	werror("Query result: %O\n", sql->query("table stillebot.user_followed_categories")); // */
	return -1; //To get notifications, activate the backend, then use "notify readonly, 'new-state'" in another session
	/* //Done manually, it works fine, as long as all is nonblocking.
	object sock = Stdio.File();
	int port = 5432;
	sock->connect("192.168.0.19", port);
	if (port == 5432) {
		sock->write("\0\0\0\b\4\322\26/");
		werror("Got: %O\n", sock->read(1));
	}
	object output = Stdio.Buffer(
		port == 5432 ? "\0\0\0%\0\3\0\0user\0rosuav\0database\0rosuav\0\0"
		: "Hello, world!"
	);
	sock->set_nonblocking(0) {
		SSL.File ssl = SSL.File(sock, ctx);
		ssl->connect();
		ssl->set_nonblocking(
			lambda(object sock, string data) {werror("Data from server: %O\n", data);},
			lambda(object sock) {
				if (!sizeof(output)) return;
				object cert = Standards.X509.decode_certificate(sock->get_peer_certificates()[0]);
				werror("Server cert: %O\n", cert->subject[0][0][-1]->value);
				output->output_to(sock);
			},
			lambda(object sock) {exit(0, "Closed.\n");},
		);
	};
	return -1; // */
}

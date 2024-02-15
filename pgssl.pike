class SSLContext {
	inherit SSL.Context;
	array|zero find_cert_issuer(array(string) ders) {
		if (sizeof(cert_chains_issuer)) return values(cert_chains_issuer)[0]; //Return the first available cert
		return ::find_cert_issuer(ders);
	}
}

class Database(string host, object ctx) {
	Stdio.File|SSL.File sock;
	Stdio.Buffer in, out;
	string state;
	protected void create() {
		//TODO: Do this nonblocking too
		sock = Stdio.File();
		sock->open_socket();
		sock->set_nonblocking(rawread, 0, sockclosed);
		sock->connect("sikorsky.rosuav.com", 5432);
		state = "handshake";
		sock->write("\0\0\0\b\4\322\26/");
		return;
	}
	void rawread(object sock, string data) {
		if (data != "S") {sock->close(); return;} //Bad handshake
		sock = SSL.File(sock, ctx);
		sock->set_nonblocking(sockread, 0, sockclosed, 0, 0) {
			werror("Accepted!\n");
			sock->set_buffer_mode(in = Stdio.Buffer(), out = Stdio.Buffer());
			out->add_hstring("\0\3\0\0user\0rosuav\0database\0rosuav\0\0", 4, 4);
			out->output_to(sock);
			state = "auth";
		};
		sock->connect();
	}
	void sockread() {
		switch (state) {
			case "auth": werror("Got auth: %O\n", in->read()); break;
			default: werror("Got unknown: %O\n", in); break;
		}
	}
	void sockclosed() {werror("Closed.\n"); exit(0);}
}

int main() {
	string key = Stdio.read_file("privkey.pem");
	string cert = Stdio.read_file("certificate.pem");
	object ctx = SSLContext();
	array(string) root = Standards.PEM.Messages(Stdio.read_file("/etc/ssl/certs/ISRG_Root_X1.pem"))->get_certificates();
	ctx->add_cert(Standards.PEM.simple_decode(key), Standards.PEM.Messages(cert)->get_certificates() + root);
	object sql = Database("sikorsky.rosuav.com", ctx);
	return -1;
}

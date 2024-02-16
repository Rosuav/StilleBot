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
	int backendpid, secretkey;
	mapping server_params = ([]);
	protected void create() {
		//TODO: Do this nonblocking too
		sock = Stdio.File();
		sock->open_socket();
		sock->set_nonblocking(rawread, 0, sockclosed);
		sock->connect("sikorsky.rosuav.com", 5432);
		state = "handshake";
		sock->write("\0\0\0\b\4\322\26/"); //Magic packet to request SSL
		return;
	}
	void rawread(object sock, string data) {
		if (data != "S") {sock->close(); return;} //Bad handshake
		sock = SSL.File(sock, ctx);
		sock->set_nonblocking(sockread, 0, sockclosed, 0, 0) {
			sock->set_buffer_mode(in = Stdio.Buffer(), out = Stdio.Buffer());
			out->add_hstring("\0\3\0\0user\0rosuav\0database\0stillebot\0application_name\0stillebot\0\0", 4, 4);
			out->output_to(sock);
			state = "auth";
		};
		sock->connect();
	}
	void sockread() {
		while (1) {
			object rew = in->rewind_on_error();
			int msgtype = in->read_int8();
			string msg = in->read_hstring(4, 4);
			if (!msg) return; //Hopefully it'll rewind, leave the partial message in buffer, and retrigger us when there's more data
			rew->release();
			switch (msgtype) {
				case 'E': { //Error. See https://www.postgresql.org/docs/current/protocol-error-fields.html
					mapping fields = ([]);
					while (sscanf(msg, "%1s%s\0%s", string field, string value, msg) == 3)
						fields[field] = value;
					werror("Error: %O\n", fields);
					if (state == "auth") state = "authfailed";
					break;
				}
				case 'R': {
					if (msg == "\0\0\0\0") {state = "ready"; break;}
					//Otherwise it's some sort of request for more auth, not supported here.
					//We require password-free authentication, meaning it has to be trusted,
					//peer-authenticated, or SSL certificate authenticated (mainly that one).
					state = "error";
					sscanf(msg, "%4d", int authtype);
					werror("ERROR: Unsupported authentication type [%d]\n", authtype);
					break;
				}
				case 'K': sscanf(msg, "%4d%4d", backendpid, secretkey); break;
				case 'Z': state = (["I": "ready", "T": "transaction", "E": "transacterr"])[msg]; break;
				case 'S': { //Note that this is ParameterStatus from the back end, but if the front end sends it, it's Sync
					sscanf(msg, "%s\0%s\0", string param, string value);
					server_params[param] = value;
					break;
				}
				default: werror("Got unknown message [state %s]: %c %O\n", state, msgtype, msg);
			}
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

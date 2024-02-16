class SSLContext {
	inherit SSL.Context;
	array|zero find_cert_issuer(array(string) ders) {
		if (sizeof(cert_chains_issuer)) return values(cert_chains_issuer)[0]; //Return the first available cert
		return ::find_cert_issuer(ders);
	}
}

mapping parse_result_row(array fields, string row) {
	mapping ret = ([]);
	foreach (fields, array field) {
		if (sscanf(row, "\377\377\377\377%s", row)) {ret[field[0]] = Val.null; continue;}
		sscanf(row, "%4H%s", mixed val, row);
		switch (field[3]) { //type OID
			case 20: case 21: case 23: sscanf(val, "%" + field[4] + "c", val); break;
			default: break;
		}
		ret[field[0]] = val;
	}
	return ret;
}

class Database(string host, object ctx) {
	Stdio.File|SSL.File sock;
	Stdio.Buffer in, out;
	string state;
	int backendpid, secretkey;
	mapping server_params = ([]);
	array(Concurrent.Promise) pending = ({ });
	mapping inflight = ([]); //Map a portal name to some info about the query-to-be
	int(1bit) writable = 1;
	array(string) preparing_statements = ({ });

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
	void rawread(object s, string data) {
		if (data != "S") {sock->close(); return;} //Bad handshake
		sock = SSL.File(sock, ctx);
		sock->set_nonblocking(sockread, sockwrite, sockclosed, 0, 0) {
			sock->set_buffer_mode(in = Stdio.Buffer(), out = Stdio.Buffer());
			out->add_hstring("\0\3\0\0user\0rosuav\0database\0stillebot\0application_name\0stillebot\0\0", 4, 4);
			write();
			state = "auth";
		};
		sock->connect();
	}
	void sockread() {
		while (sizeof(in)) {
			object rew = in->rewind_on_error();
			int msgtype = in->read_int8();
			string msg = in->read_hstring(4, 4);
			if (!msg) {werror("Incomplete message %O\n", (string)in); return;} //Hopefully it'll rewind, leave the partial message in buffer, and retrigger us when there's more data
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
					if (msg == "\0\0\0\0") break;
					//Otherwise it's some sort of request for more auth, not supported here.
					//We require password-free authentication, meaning it has to be trusted,
					//peer-authenticated, or SSL certificate authenticated (mainly that one).
					state = "error";
					sscanf(msg, "%4d", int authtype);
					werror("ERROR: Unsupported authentication type [%d]\n", authtype);
					break;
				}
				case 'K': sscanf(msg, "%4d%4d", backendpid, secretkey); break;
				case 'Z':
					if (msg == "I") ready();
					else state = (["T": "transaction", "E": "transacterr"])[msg];
					break;
				case 'S': { //Note that this is ParameterStatus from the back end, but if the front end sends it, it's Sync
					sscanf(msg, "%s\0%s\0", string param, string value);
					server_params[param] = value;
					break;
				}
				case '1': case '2': break; //ParseComplete, BindComplete (not important, we'll already have queued other packets)
				case 't': {
					sscanf(msg, "%2c%{%4c%}", int nparams, array params);
					werror("For portal %O, %d params: %O\n", preparing_statements[0], nparams, params);
					string portalname = preparing_statements[0];
					mapping stmt = inflight[portalname];
					stmt->params = params[*][0];
					array packet = ({portalname, 0, portalname, "\0\0\1\0\1", sprintf("%2c", nparams)});
					foreach (params, array param) {
						//TODO: If value is NULL, packet += ({"\xFF\xFF\xFF\xFF"});
						packet += ({sprintf("%4H", "")}); //TODO
					}
					packet += ({"\0\1\0\1"});
					out->add_int8('B')->add_hstring(packet, 4, 4);
					out->add_int8('E')->add_hstring(({portalname, "\0\0\0\0\0"}), 4, 4);
					flushsend();
					break;
				}
				case 'T': { //RowDescription
					string portalname = preparing_statements[0];
					mapping stmt = inflight[portalname];
					sscanf(msg, "%2c%{%s\0%4c%2c%4c%2c%4c%2c%}", int nfields, stmt->fields);
					//Each field is [tableoid, attroid, typeoid, typesize, typemod, format]
					//Most interesting here will be typeoid
					werror("Fields: %O\n", stmt->fields);
					break;
				}
				case 'D': { //DataRow
					string portalname = preparing_statements[0];
					mapping stmt = inflight[portalname];
					stmt->results += ({msg[2..]});
					break;
				}
				case 'C': { //CommandComplete
					[string portalname, preparing_statements] = Array.shift(preparing_statements);
					mapping stmt = inflight[portalname];
					stmt->completion->success(1);
					break;
				}
				default: werror("Got unknown message [state %s]: %c %O\n", state, msgtype, msg);
			}
		}
	}
	void sockwrite() {werror("sockwrite\n"); writable = 1;}
	void sockclosed() {werror("Closed.\n"); exit(0);}
	void write() {
		if (!writable) return;
		werror("Attempting to send %d bytes...\n", sizeof(out));
		out->output_to(sock);
		werror("Sent. Remaining: %d bytes.\n", sizeof(out));
		if (sizeof(out)) writable = 0;
	}
	void flushsend() {
		out->add("H\0\0\0\4");
		write();
	}

	//This kind of idea would be nice, but how do I distinguish Int16 from Int32?
	/*string build_packet(int type, mixed ... args) {
		string packet = "";
		foreach (args, mixed arg) add_arg_to_packet;
		return sprintf("%c%4H", type, packet);
	}*/

	void ready() { //Must be atomic. If multithreading is added, put a lock around this.
		state = "ready";
		if (sizeof(pending)) {
			state = "busy";
			[Concurrent.Promise next, pending] = Array.shift(pending);
			next->success(1);
		}
	}

	__async__ array(mapping) query(string sql, mapping|void bindings) {
		//Must be atomic with ready()
		if (state == "ready") state = "busy";
		else {
			object p = Concurrent.Promise();
			pending += ({p});
			await(p->future()); //Enqueue us until ready() declares that we're done
		}
		//NOTE: For now, I am assuming that portals and prepared statements will always
		//use the same names. We're not really using concurrent inflight queries here,
		//so it'll just be to take advantage of pre-described statements. Thus, in this
		//class, a "portalname" sometimes actually refers to a prepared statement.
		string portalname = ""; //Do we need portal support?
		//if (inflight[portalname]) ...

		array|zero ret = 0;
		mixed ex = catch {
			werror("Starting query: %s\n", sql);
			//string packet = sprintf("%s\0%s\0%2c%{%4c%}", portalname, sql, sizeof(params), params);
			object completion = Concurrent.Promise();
			mapping stmt = inflight[portalname] = ([
				"query": sql, //For debugging only
				"bindings": bindings || ([]),
				"completion": completion,
				"results": ({ }),
			]);
			preparing_statements += ({portalname});
			out->add_int8('P')->add_hstring(({portalname, 0, sql, "\0\0\0"}), 4, 4);
			out->add_int8('D')->add_hstring(({'S', portalname, 0}), 4, 4);
			flushsend();
			await(completion->future());
			m_delete(inflight, portalname);
			out->add("S\0\0\0\4"); write();
			//Now to parse out those rows and properly comprehend them.
			ret = parse_result_row(stmt->fields, stmt->results[*]);
		};

		if (ex) throw(ex);
		return ret;
	}
}

int main() {
	string key = Stdio.read_file("privkey.pem");
	string cert = Stdio.read_file("certificate.pem");
	object ctx = SSLContext();
	array(string) root = Standards.PEM.Messages(Stdio.read_file("/etc/ssl/certs/ISRG_Root_X1.pem"))->get_certificates();
	ctx->add_cert(Standards.PEM.simple_decode(key), Standards.PEM.Messages(cert)->get_certificates() + root);
	object sql = Database("sikorsky.rosuav.com", ctx);
	sql->query("select 1+2+3, current_user")->then() {werror("Simple query: %O\n", __ARGS__[0]);};
	sql->query("select * from stillebot.commands where twitchid = :twitchid and cmdname = :cmd and active",
		(["twitchid": "49497888", "cmd": "iidpio"]))->then() {
			werror("Command lookup: %O\n", __ARGS__[0]);
		};
	return -1;
}

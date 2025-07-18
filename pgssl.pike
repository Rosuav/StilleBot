/* There are a couple of really weird bugs in the Pike PGSQL handler
that I don't understand well enough to fix. This module is my attempt
to reimplement PostgreSQL wire protocol in the grasping-at-straws hope
that it'll help me figure out what's going on so I can track down the
actual issues. It also has a couple of tiny improvements over Pike's
library that haven't yet been upstreamed (eg UUID/JSON parsing). */

#if !constant(G)
mapping G = (["G": ([])]);
#endif

//Offset between 1970 and 2000
#define EPOCH2000 (10957*24*3600*1000000)

//List the category for every OID in pg_type. Used for determining wire format
//where not specifically listed.
mapping(int:string) typcategory = G->G->typcategory || ([]);
//If an OID represents an array, this is the element type. Note that this comes
//not from the typelem column but from typarray, as there are other ways for
//typelem to be filled in. Required for encoding, but not for decoding.
mapping(int:int) array_oid = G->G->array_oid || ([1009: 25]); //Bootstrap by knowing about text[].

#ifdef SHOW_UNKNOWN_OIDS
//Improve debugging? Maybe?
multiset(int) sighted_unknowns = (< >);
mapping(int:string) typname = ([]);
#endif

mixed decode_as_type(string val, int type) {
	//First off, fast check for known OIDs. This group *must* include all data types
	//required for bootstrapping up to the point of fetching pg_type.
	switch (type) {
		case 16: return val == "\1"; //Boolean
		case 18: case 19: case 25: case 1042: case 1043: return utf8_to_string(val);
		case 20: case 21: case 23: case 26: { //Integers, various
			sscanf(val, "%" + sizeof(val) + "c", int v); //Assumes that all int-like values (eg OID etc) have the correct size
			return v;
		}
		case 114: return Standards.JSON.decode_utf8(val);
		case 3802: return Standards.JSON.decode_utf8(val[1..]);
		case 700: case 701: { //Float
			sscanf(val, "%" + sizeof(val) + "F", float v);
			return v;
		}
		case 1184: { //Timestamp with time zone
			sscanf(val, "%+8c", int usec);
			object v = Val.Timestamp();
			v->usecs = usec + EPOCH2000;
			return v;
		}
		case 1700: { //NUMERIC
			//It seems to have two integer portions, but either one can be
			//omitted. For example, 1::numeric(10, 5) will not have any fraction
			//portion - it's completely omitted - but also, 0.125::numeric(10, 5)
			//will omit the integer portion. So far, not supported.
			return String.string2hex(val);
		}
		case 2950: { //UUID
			sscanf(val, "%{%2c%}", array words);
			return sprintf("%04x%04x-%04x-%04x-%04x-%04x%04x%04x", @words[*][0]);
		}
		case 3220: { //LSN
			sscanf(val, "%4c%4c", int n1, int n2);
			return sprintf("%X/%X", n1, n2);
		}
		default: break;
	}
	//Okay, we don't know the type directly. Do we know what *kind* of type it is?
	switch (typcategory[type]) {
		case "A": {
			//It's an array of something. The element OID is essential here.
			sscanf(val, "%4c%4c%4c%s", int dim, int unknown, int elemoid, val);
			if (!dim) { //Zero-dimensional array. For our purposes, this is treated as a 1-dimensional empty array.
				//assert val == ""
				return ({ });
			}
			array dims = allocate(dim);
			for (int d = 0; d < dim; ++d) sscanf(val, "%4c%*4c%s", dims[d], val); //Is always followed by int4 1, not sure the meaning.
			sscanf(val, "%{%4H%}", array values);
			values = decode_as_type(values[*][0][*], elemoid);
			//Split the array according to the dimensions. The last (or rather, first)
			//is not split, but we could assert that sizeof(values) == dims[0] if we
			//felt like it.
			for (int d = sizeof(dims) - 1; d > 0; --d) values /= dims[d];
			return values;
		}
		break;
		//case "D": //Date/time
		//case "G": //Geometric
		//case "I": //Internet address
		case "N": {sscanf(val, "%" + sizeof(val) + "c", int v); return v;} //Numeric. Anything non-integer needs to be in the primary switch above.
		//case "R": //Range types (including multiranges)
		case "S": return utf8_to_string(val);
		//case "T": //Timespan types (but there's only one)
		//case "U": //User-defined types
		//case "V": //Bit-string types
		//case "X": //Unknown types
		//case "Z": //Internal types
		default: break;
	}
	#ifdef SHOW_UNKNOWN_OIDS
	if (!sighted_unknowns[type]) {
		werror("Unknown type OID %d: %s (category %O)\n", type, typname[type] || "unknown", typcategory[type]);
		sighted_unknowns[type] = 1;
	}
	#endif
	return val;
}

mapping parse_result_row(array fields, string row) {
	//Each field is [tableoid, attroid, typeoid, typesize, typemod, format]
	//Most interesting here will be typeoid
	mapping ret = ([]);
	foreach (fields, array field) {
		if (sscanf(row, "\377\377\377\377%s", row)) {ret[field[0]] = Val.null; continue;}
		sscanf(row, "%4H%s", mixed val, row);
		ret[field[0]] = decode_as_type(val, field[3]);
	}
	return ret;
}

string encode_as_type(mixed value, int typeoid) {
	if (objectp(value) && value->is_val_null) return "\377\377\377\377"; //Any NULL is encoded as length -1
	switch (typeoid) {
		case 16: value = value ? "\1" : "\0"; break;
		case 18: case 25: value = string_to_utf8((string)value); break;
		case 20: value = sprintf("%8c", (int)value); break;
		case 21: value = sprintf("%2c", (int)value); break;
		case 23: value = sprintf("%4c", (int)value); break;
		case 114: value = Standards.JSON.encode(value, 5); break;
		case 3802: value = "\1" + Standards.JSON.encode(value, 5); break; //I think? It seems to expect a version number but otherwise be JSON.
		case 700: value = sprintf("%4F", (float)value); break;
		case 701: value = sprintf("%8F", (float)value); break;
		case 1184: value = sprintf("%8c", value->usecs - EPOCH2000); break;
		case 2950: {
			array words = array_sscanf(value, "%4x%4x-%4x-%4x-%4x-%4x%4x%4x");
			if (sizeof(words) != 8) error("Malformed UUID string %O\n", value);
			value = sprintf("%@2c", words);
			break;
		}
		case 3220: { //LSN
			sscanf(value, "%x/%x", int n1, int n2);
			value = sprintf("%4c%4c", n1, n2);
			break;
		}
		default:
			if (int elemoid = arrayp(value) && array_oid[typeoid]) {
				if (!sizeof(value)) {
					value = sprintf("%4c%4c%4c", 0, 0, elemoid);
					break;
				}
				array dims = ({sizeof(value)});
				//Not sure what to happen if we hit an empty array rather than finding scalars.
				//I think it would be considered malformed?? Can't have emptiness, other than a
				//zero-dimensional array which we generate from an empty array above.
				for (mixed inner = value[0]; arrayp(inner); inner = inner[0]) {
					dims += ({sizeof(inner)});
					value *= ({ });
				}
				value = sprintf("%4c%4c%4c%{%4c\0\0\0\1%}%{%s%}",
					sizeof(dims), 0, elemoid,
					dims, encode_as_type(value[*], elemoid));
				break;
			}
			else value = (string)value;
	}
	return sprintf("%4H", value);
}

//Sql.Sql-compatible API.
class PromiseResult(array data) {
	array get() {return data;}
}

class SSLDatabase(string|mapping connect_to, mapping|void cfg) {
	Stdio.File|SSL.File sock;
	Stdio.Buffer in, out;
	string state;
	int backendpid, secretkey;
	mapping server_params = ([]);
	array(Concurrent.Promise) pending = ({ });
	mapping inflight = ([]); //Map a portal name to some info about the query-to-be
	int(1bit) writable = 1;
	array(string) preparing_statements = ({ });
	int(1bit) in_transaction = 0; //If true, we're in a transaction, and autocommitted queries have to wait.
	Concurrent.Promise|zero transaction_pending = 0;
	mapping connect_params = (["user": System.get_user() || "postgres"]);

	protected void create() {
		if (!cfg) cfg = ([]);
		//TODO: Do this nonblocking too
		sock = Stdio.File();
		sock->open_socket();
		sock->set_nonblocking(rawread, rawwrite, sockclosed);
		if (mappingp(connect_to)) {
			connect_params = connect_to;
			connect_to = m_delete(connect_params, "host");
		}
		if (has_value(connect_to, "://")) {
			object uri = Standards.URI(connect_to);
			connect_to = uri->host;
			connect_params->user = uri->user;
			connect_params->database = uri->path[1..];
		}
		sock->connect(connect_to, 5432);
		state = "connect";
	}
	void rawwrite() {
		state = "handshake";
		sock->write("\0\0\0\b\4\322\26/"); //Magic packet to request SSL
		sock->set_write_callback(0); //Once only. We assume that the magic packet really is just one packet.
	}
	void rawread(object s, string data) {
		if (data != "S") {sock->close(); return;} //Bad handshake
		sock = SSL.File(sock, cfg->ctx || SSL.Context());
		sock->set_nonblocking(sockread, sockwrite, sockclosed, 0, 0) {
			out = Stdio.Buffer(); //Not actually using buffer mode for output
			sock->set_buffer_mode(in = Stdio.Buffer(), 0);
			out->add_hstring(sprintf("\0\3\0\0%{%s\0%s\0%}\0", (array)connect_params), 4, 4);
			write();
			state = "auth";
			if (!sizeof(typcategory)) {
				//Type categories have not been loaded. (Not redone on reconnect.)
				query("select oid, typcategory, typname, typarray from pg_type where typtype in ('b', 'r', 'm')")->then() {
					G->G->typcategory = typcategory = mkmapping(__ARGS__[0]->oid, __ARGS__[0]->typcategory);
					#ifdef SHOW_UNKNOWN_OIDS
					typname = mkmapping(__ARGS__[0]->oid, __ARGS__[0]->typname);
					#endif
					G->G->array_oid = array_oid = mkmapping(__ARGS__[0]->typarray, __ARGS__[0]->oid);
				};
			}
		};
		sock->connect();
	}
	void sockread() {
		if (mixed ex = catch {while (sizeof(in)) {
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
					if (state == "busy" && sizeof(preparing_statements)) {
						[string portalname, preparing_statements] = Array.shift(preparing_statements);
						mapping stmt = inflight[portalname];
						stmt->completion->failure(({
							sprintf("Error in query: %O\n%s\n%s\n",
								stmt->query,
								fields->M || "Unknown query error",
								fields->D || ""),
							backtrace(),
						}));
					}
					else if (state == "auth") {
						//We can't really throw an error here as it all happens asynchronously,
						//but we can at least dump something to the console. TODO: Support
						//password-based authentication methods??
						state = "authfailed";
						werror("Database authentication failure:\n%s\n", fields->M);
					}
					else werror("Database error, unknown cause: %O\n", fields);
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
				case 'K': sscanf(msg, "%4c%4c", backendpid, secretkey); break;
				case 'Z':
					if (msg == "I") ready();
					else if (msg == "T" || msg == "E") transaction_ready(); //Note that in the error state, the only query we expect is "rollback"
					break;
				case 'S': { //Note that this is ParameterStatus from the back end, but if the front end sends it, it's Sync
					sscanf(msg, "%s\0%s\0", string param, string value);
					server_params[param] = value;
					break;
				}
				case '1': case '2': break; //ParseComplete, BindComplete (not important, we'll already have queued other packets)
				case 't': { //ParameterDescription
					sscanf(msg, "%2c%{%4c%}", int nparams, array params);
					string portalname = preparing_statements[0];
					mapping stmt = inflight[portalname];
					array packet = ({portalname, 0, portalname, "\0\0\1\0\1", sprintf("%2c", nparams)});
					packet += encode_as_type(stmt->paramvalues[*], params[*][0][*]);
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
					break;
				}
				case 'D': { //DataRow
					string portalname = preparing_statements[0];
					mapping stmt = inflight[portalname];
					stmt->results += ({msg[2..]});
					break;
				}
				case 'n': break; //NoData. Sent when there are no DataRows.
				case 'C': { //CommandComplete
					[string portalname, preparing_statements] = Array.shift(preparing_statements);
					mapping stmt = inflight[portalname];
					if (!--stmt->query_count) stmt->completion->success(1);
					break;
				}
				case 'A': { //NotificationResponse
					sscanf(msg, "%4c%s\0%s\0", int pid, string channel, string payload);
					if (cfg->notify_callback) cfg->notify_callback(this, pid, channel, payload);
					break;
				}
				case 'N': break; //NoticeResponse - not currently being reported anywhere
				case '3': break; //Close complete. Only happens if we raise an error.
				default: werror("PGSSL got unknown message [state %s]: %c %O\n", state, msgtype, msg);
			}
		}}) {
			//If we hit an exception while parsing responses to a query, report the query as failed,
			//and resync with the server. If we hit one at any other time, just log it to the console
			//and resync; no value raising it. Ideally, we should interrupt the current transaction
			//with an error, but queueing a call to throw() is not sufficient as it will happen AFTER
			//all other processing.
			if (sizeof(preparing_statements)) {
				string portalname = preparing_statements[0];
				mapping stmt = inflight[portalname];
				out->add_int8('C')->add_hstring(({'S', portalname, 0}), 4, 4);
				flushsend();
				//Is it okay to report failure here? There may still be queued subparts to this statement,
				//so we're not removing it from preparing_statements yet. It should eventually get either
				//a CommandComplete or an ErrorResponse. There'll also be a CloseComplete from the 'C'
				//above; this doesn't currently affect anything.
				stmt->completion->failure(ex);
			}
			else werror("PGSSL parse failure:\n%s\n", describe_backtrace(ex));
		}
	}
	void sockwrite() {
		out->output_to(sock);
		if (!sizeof(out)) writable = 1;
	}
	void sockclosed() {werror("Closed.\n"); destruct();}
	void write() {
		if (!writable) return;
		out->output_to(sock);
		if (sizeof(out)) writable = 0;
	}
	void flushsend() {
		out->add("H\0\0\0\4");
		write();
	}

	void close() {sock->close();}

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
	void transaction_ready() { //Like ready() but when we're in transaction state. Note that this is slightly broader than PG's "we're in a transaction" marker.
		if (transaction_pending) {transaction_pending->success(1); transaction_pending = 0;}
		else state = "transactionready";
	}

	__async__ array(mapping) _low_query(string readystate, string sql, mapping|void bindings) {
		#ifdef PGSSL_TIMING
		string label = sprintf("%O", replace(sql, "\n", " ")[..100]);
		if (sql == "select data from stillebot.config where twitchid = :twitchid and keyword = :kwd")
			label = sprintf("load_config(%O, %O)", bindings->twitchid, bindings->kwd);
		else if (sql == "insert into stillebot.user_login_sightings (twitchid, login) values (:id, :login) on conflict do nothing")
			label = sprintf("notice_user_name(%O, %O)", bindings->login, bindings->id);
		werror("[%d] Init query %s\n", time(), label);
		#endif
		//Preparse the query and bindings
		array paramvalues = ({ });
		if (bindings) foreach (bindings; string param; mixed val) {
			param = ":" + param;
			if (!has_value(sql, param)) continue; //It's fine to have unnecessary bindings (see eg group/transaction handling)
			paramvalues += ({val});
			sql = replace(sql, param, "$" + sizeof(paramvalues)); //TODO for performance: Replace all at once
		}

		//Must be atomic with ready()
		if (state == readystate) state = "busy";
		else {
			object p = Concurrent.Promise();
			if (readystate == "ready") pending += ({p});
			else transaction_pending = p;
			await(p->future()); //Enqueue us until ready() or equiv declares that we're done
		}
		//NOTE: For now, I am assuming that portals and prepared statements will always
		//use the same names. We're not really using concurrent inflight queries here,
		//so it'll just be to take advantage of pre-described statements. Thus, in this
		//class, a "portalname" sometimes actually refers to a prepared statement.
		string portalname = ""; //Do we need portal support?
		//if (inflight[portalname]) ...
		#ifdef PGSSL_TIMING
		werror("[%d] Exec query %s\n", time(), label);
		#endif

		array|zero ret = 0;
		//string packet = sprintf("%s\0%s\0%2c%{%4c%}", portalname, sql, sizeof(params), params);
		object completion = Concurrent.Promise();
		mapping stmt = inflight[portalname] = ([
			"query": sql, //Context for error messages
			"paramvalues": paramvalues,
			"completion": completion,
			"results": ({ }),
			"query_count": 1,
		]);
		preparing_statements += ({portalname});
		out->add_int8('P')->add_hstring(({portalname, 0, sql, "\0\0\0"}), 4, 4);
		out->add_int8('D')->add_hstring(({'S', portalname, 0}), 4, 4);
		flushsend();
		mixed ex = catch (await(completion->future()));
		m_delete(inflight, portalname);
		out->add("S\0\0\0\4"); write(); //After the query, synchronize, whether we succeeded or failed.
		#ifdef PGSSL_TIMING
		werror("[%d] Done query %s\n", time(), label);
		#endif
		if (ex) throw(ex);
		//Now to parse out those rows and properly comprehend them.
		return parse_result_row(stmt->fields, stmt->results[*]);
	}
	Concurrent.Future query(string sql, mapping|void bindings) {
		//if (in_transaction) error("Use transaction() OR query(), don't mix them.\n");
		//NOTE: If you call this from inside a transaction callback, it will deadlock.
		//This would be bad. Don't do that. TODO: Figure out a way to check the call
		//stack for a transaction() and error out in that case. It should still be
		//valid to call this from other tasks, and it should queue.
		return _low_query("ready", sql, bindings);
	}
	//Sql.Sql-compatible API
	__async__ PromiseResult promise_query(string sql, mapping|void bindings) {
		array ret = await(query(sql, bindings));
		return PromiseResult(ret);
	}

	Concurrent.Future transaction_query(string sql, mapping|void bindings) {
		//Version of query() to be called ONLY from inside a transaction block.
		if (!in_transaction) error("Use transaction() or query(), don't use this directly.\n");
		return _low_query("transactionready", sql, bindings);
	}

	//Execute the given function in a transaction context. Kinda like a 'with' block
	//in Python, this will propagate the return value or exception from the body,
	//while managing the transaction (rolling back if exception, committing else).
	//The callback will be passed a function equivalent to query(), followed by any
	//additional arguments. NOTE: Keep this function short and fast! All other DB
	//queries will be queued until this transaction completes.
	__async__ mixed transaction(function body, mixed ... args) {
		await(_low_query("ready", "begin read write")); //Not transaction_query here. Queue us like any autocommitted call.
		in_transaction = 1;
		mixed ret;
		mixed ex = catch {
			ret = await(body(transaction_query, @args));
		};
		if (ex) {
			catch {await(transaction_query("rollback"));}; //Ignore errors from the rollback itself, they'll just be cascaded.
			in_transaction = 0;
			throw(ex);
		}
		await(transaction_query("commit")); //Don't ignore errors from commit. Let 'em bubble.
		in_transaction = 0;
		return ret;
	}

	//A batch of queries is executed in quick succession without waiting for
	//individual responses. Bindings are not supported and results are not fetched.
	//Bracket the queries in BEGIN/COMMIT if transactional integrity is desired;
	//without this, some measure of rollback may happen automatically on error, but
	//if it matters, be explicit. Note that errors will be blamed on the first
	//query in the batch; perhaps having the remaining query_count would be useful?
	__async__ void batch(array(string) queries) {
		//Wait for our turn in queue, same as regular query() does
		if (state == "ready") state = "busy";
		else {
			object p = Concurrent.Promise();
			pending += ({p});
			await(p->future());
		}
		string portalname = "";
		object completion = Concurrent.Promise();
		mapping stmt = inflight[portalname] = ([
			"query": queries[0], //Context for error messages
			"completion": completion,
			"results": ({ }),
			"query_count": sizeof(queries),
		]);
		preparing_statements += ({portalname}) * sizeof(queries);
		foreach (queries, string sql) {
			out->add_int8('P')->add_hstring(({portalname, 0, sql, "\0\0\0"}), 4, 4);
			out->add_int8('B')->add_hstring(({portalname, 0, portalname, "\0\0\0\0\0\0\0"}), 4, 4);
			out->add_int8('E')->add_hstring(({portalname, "\0\0\0\0\0"}), 4, 4);
		}
		flushsend();
		mixed ex = catch (await(completion->future()));
		m_delete(inflight, portalname);
		out->add("S\0\0\0\4"); write(); //After the query, synchronize, whether we succeeded or failed.
		if (ex) throw(ex);
	}
}

#if !constant(G)
//Stand-alone testing
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
	object sql = SSLDatabase("sikorsky.mustardmine.com", (["ctx": ctx]));
	sql->query("select 1+2+3, current_user")->then() {werror("Simple query: %O\n", __ARGS__[0]);};
	sql->query("select * from stillebot.commands where twitchid = :twitchid and cmdname = :cmd",
		(["twitchid": "49497888", "cmd": "tz"]))->then() {
			werror("Command lookup: %O\n", __ARGS__[0]);
		};
	sql->query("select * from stillebot.commands where id = :id",
		(["id": "3b482366-b032-48db-8572-d4ffa56e7bb4"]))->then() {
			werror("Command lookup: %O\n", __ARGS__[0]);
		};
	sql->query("insert into stillebot.commands (twitchid, cmdname, active, content) values (:twitchid, :cmdname, true, :content)",
		(["twitchid": "49497888", "cmdname": "tz", "content": "test"]))->then() {
			werror("Command insertion: %O\n", __ARGS__[0]);
		};
	sql->query("LISTEN testing");
	sql->query("NOTIFY testing, 'hello'");
	sql->query("select table_schema, count(*) from information_schema.columns group by table_schema")->then() {
		werror("Schema column counts: %O\n", mkmapping(__ARGS__[0]->table_schema, __ARGS__[0]->count));
	};
	//Now let's do the same thing less efficiently, to stress-test the fetching.
	sql->query("select * from information_schema.columns")->then() {
		mapping counts = ([]);
		foreach (__ARGS__[0], array row) counts[row->table_schema]++;
		werror("Schema column counts: %O\n", counts);
	};
	return -1;
}
#else
protected void create(string name) {
	add_constant("SSLDatabase", SSLDatabase);
}
#endif

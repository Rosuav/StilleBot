inherit annotated;
inherit hook;

//For each table, we have a set of columns, plus some other info. Any entry
//beginning with a space is included in the CREATE TABLE but will not be added
//subsequently in an ALTER TABLE; any entry ending with a semicolon will also
//be used only on table creation, but will be executed as its own statement in
//the same transaction. Otherwise, any column entry where the first word is not
//found as an existing column will be altered into the table on next check.
//NOTE: We assume that no table will ever exist without columns. I mean, why?!?
//Altering of tables is extremely simplistic and will only ever drop or add a
//column. For more complex changes, devise a system when one becomes needed.
//NOTE: Tables will never be dropped, although columns removed from tables will.
//CAUTION: Avoid using serial/identity primary keys as they may cause conflicts
//due to the sequence not being replicated. UUIDs are safer.
constant tables = ([
	"user_followed_categories": ({ //Not actually used, other than for testing
		"twitchid bigint not null",
		"category integer not null",
		" primary key (twitchid, category)",
	}),
	"commands": ({
		"id uuid primary key default gen_random_uuid()",
		"twitchid bigint not null",
		"cmdname text not null",
		"active boolean not null",
		"content jsonb not null",
		"created timestamp with time zone not null default now()",
		"create unique index on stillebot.commands (twitchid, cmdname) where active;",
		//Yet more untested.
		//"create or replace function send_command_notification() returns trigger language plpgsql as $$begin perform pg_notify('stillebot.commands', concat(new.twitchid, ':', new.cmdname)); return null; end$$;",
		//"create or replace trigger command_created after insert on stillebot.commands for each row execute function send_command_notification();",
		//"alter table stillebot.commands enable always trigger command_created;",
	}),
	//Generic channel/user info. Formerly in persist_config, persist_status, or channels/USERID.json
	"config": ({
		"twitchid bigint not null",
		"keyword varchar not null",
		"data jsonb not null",
		" primary key (twitchid, keyword)",
		//If ever I start over, there's gonna be a lot of these to test.
		//"create or replace function send_config_notification() returns trigger language plpgsql as $$begin perform pg_notify(concat('stillebot.config', ':', new.keyword), new.twitchid::text); return null; end$$;",
		//"create or replace trigger config_changed after insert or update on stillebot.config for each row execute function send_config_notification();",
		//"alter table stillebot.config enable always trigger config_changed;",
	}),
	//Simple list of the "exportable" configs as stored in stillebot.config above.
	//A user may (when implemented) request their exportable data, as a backup etc.
	//Can be used in an outer join to recognize non-exportable rows.
	"config_exportable": ({
		"keyword varchar primary key",
	}),
	//Single-row table for fundamental bot config. Trust this only if the database is
	//read-write; otherwise, consider it advisory.
	"settings": ({
		"asterisk char primary key", //There's only one row, but give it a PK anyway for the sake of replication.
		"active_bot varchar",
		"credentials jsonb not null default '{}'",
		"insert into stillebot.settings (asterisk) values ('*');",
		//Not tested as part of database recreation, has been done manually.
		//"create or replace function send_settings_notification() returns trigger language plpgsql as $$begin perform pg_notify('stillebot.settings', ''); return null; end$$;",
		//"create trigger settings_update_notify after update on stillebot.settings for each row execute function send_settings_notification();",
		//"alter table stillebot.settings enable always trigger settings_update_notify;",
		//TODO: Have a deletion trigger to avoid stale data in in-memory caches
	}),
	"http_sessions": ({
		"cookie varchar primary key",
		"active timestamp with time zone default now()",
		"data bytea not null",
		//Also not tested.
		//"create or replace function send_session_notification() returns trigger language plpgsql as $$begin perform pg_notify('stillebot.http_sessions', old.cookie); return null; end$$;",
		//"create or replace trigger http_session_deleted after delete on stillebot.http_sessions for each row execute function send_session_notification();",
		//"alter table stillebot.http_sessions enable always trigger http_session_deleted;",
	}),
	//Array of raids from fromid to toid. At least one of fromid and toid will be
	//a channel that I monitor.
	"raids": ({
		"fromid bigint not null",
		"toid bigint not null",
		"data jsonb not null",
		" primary key (fromid, toid)",
	}),
	"uploads": ({
		"id uuid primary key default gen_random_uuid()",
		"channel bigint not null",
		"uploader bigint not null",
		"metadata jsonb not null default '{}'",
		"expires timestamp with time zone", //NULL means it never expires
		"data bytea not null", //The actual blob.
		//TODO: Figure out what would make useful indexes
	}),
	"botservice": ({
		"twitchid bigint primary key",
		"deactivated timestamp with time zone", //Active channels have this set to NULL.
		"login text not null",
		"display_name text not null",
		"create or replace function send_botservice_notification() returns trigger language plpgsql as $$begin perform pg_notify('stillebot.botservice', new.twitchid::text); return null; end$$;",
		"create or replace trigger botservice_changed after insert or update on stillebot.botservice for each row execute function send_botservice_notification();",
		"alter table stillebot.botservice enable always trigger botservice_changed;",
	}),
	"user_login_sightings": ({
		"twitchid bigint not null",
		"login text not null",
		"sighted timestamp with time zone not null default now()",
		" primary key (twitchid, login)",
	}),
]);
multiset precached_config = (<"channel_labels", "variables", "monitors", "voices">); //TODO: Have other modules submit requests?
@retain: mapping pcc_loadstate = ([]);
@retain: mapping pcc_cache = ([]);

//NOTE: Despite this retention, actual connections are not currently retained across code
//reloads - the old connections will be disposed of and fresh ones acquired. There may be
//some sort of reference loop - it seems that we're not disposing of old versions of this
//module properly - but the connections themselves should be closed by the new module.
@retain: mapping(string:mapping(string:mixed)) pg_connections = ([]);
string active; //Host name only, not the connection object itself
@retain: mapping waiting_for_active = ([ //If active is null, use these to defer database requests.
	"queue": ({ }), //Add a Promise to this to be told when there's an active.
	"saveme": ({ }), //These will be asynchronously saved as soon as there's an active.
]);
array(string) database_ips = ({"sikorsky.rosuav.com", "ipv4.rosuav.com"});
mapping notify_channels = ([]);

#if constant(SSLDatabase)
//SSLDatabase automatically parses and encodes JSON.
#define JSONDECODE(x) (x)
#define JSONENCODE(x) (x)
#else
#define JSONDECODE(x) Standards.JSON.decode_utf8(x)
#define JSONENCODE(x) Standards.JSON.encode(x, 4)
#endif

//ALL queries should go through this function.
//Is it more efficient, with queries where we don't care about the result, to avoid calling get()?
//Conversely, does failing to call get() result in risk of problems?
//If the query is an array of strings, they all share the same bindings, and will be performed in
//a single transaction (ie if the connection fails, they will be requeued as a set). The return
//value in this case is an array of results (not counting the implicit BEGIN and COMMIT).
__async__ array query(mapping(string:mixed) db, string|array sql, mapping|void bindings) {
	#if constant(SSLDatabase)
	if (arrayp(sql)) {
		array ret = ({ });
		await(db->conn->transaction(__async__ lambda(function query) {
			foreach (sql, string q) {
				//A null entry in the array of queries is ignored, and will not have a null return value to correspond.
				if (q) ret += ({await(query(q, bindings))});
			}
		}));
		return ret;
	}
	else return await(db->conn->query(sql, bindings));
	#else
	object pending = db->pending;
	object completion = db->pending = Concurrent.Promise();
	if (pending) await(pending->future()); //If there's a queue, put us at the end of it.
	mixed ret, ex;
	if (arrayp(sql)) {
		ret = ({ });
		ex = catch {await(db->conn->promise_query("begin"))->get();};
		if (!ex) foreach (sql, string q) {
			//A null entry in the array of queries is ignored, and will not have a null return value to correspond.
			if (ex = q && catch {ret += ({await(db->conn->promise_query(q, bindings))->get()});}) break;
		}
		//Ignore errors from rolling back - the exception that gets raised will have come from
		//the actual query (or possibly the BEGIN), not from rolling back.
		if (ex) catch {await(db->conn->promise_query("rollback"))->get();};
		//But for committing, things get trickier. Technically an exception here leaves the
		//transaction in an uncertain state, but I'm going to just raise the error. It is
		//possible that the transaction DID complete, but we can't be sure.
		else ex = catch {await(db->conn->promise_query("commit"))->get();};
	}
	else {
		//Implicit transaction is fine here; this is also suitable for transactionless
		//queries (of which there are VERY few).
		ex = catch {ret = await(db->conn->promise_query(sql, bindings))->get();};
	}
	completion->success(1);
	if (db->pending == completion) db->pending = 0;
	if (ex) throw(ex);
	return ret;
	#endif
}

__async__ void _got_active(mapping db) {
	//Pull all the pendings and reset the array before actually saving any of them.
	array wfa = waiting_for_active->saveme; waiting_for_active->saveme = ({ });
	foreach (wfa, [string sql, mapping bindings]) {
		mixed err = catch {await((mixed)query(db, sql, bindings));};
		if (err) werror("Unable to save pending to database!\n%s\n", describe_backtrace(err));
	}
}
void _have_active(string a) {
	if (G->G->DB != this) return; //Let the current version of the code handle them
	werror("*** HAVE ACTIVE: %O\n", a);
	active = a;
	array wa = waiting_for_active->queue; waiting_for_active->queue = ({ });
	wa->success(active);
	spawn_task(_got_active(pg_connections[active]));
}
Concurrent.Future await_active() {
	Concurrent.Promise pending = Concurrent.Promise();
	waiting_for_active->queue += ({pending});
	return pending->future();
}

class SSLContext {
	inherit SSL.Context;
	array|zero find_cert_issuer(array(string) ders) {
		if (sizeof(cert_chains_issuer)) return values(cert_chains_issuer)[0]; //Return the first available cert
		return ::find_cert_issuer(ders);
	}
}

void notify_readonly(int pid, string cond, string extra, string host) {
	mapping db = pg_connections[host];
	if (extra == "on" && !db->readonly) {
		werror("SWITCHING TO READONLY MODE: %O\n", host);
		db->conn->query(#"select set_config('application_name', 'stillebot-ro', false),
				set_config('default_transaction_read_only', 'on', false)");
		db->readonly = 1;
		if (active == host) {active = 0; spawn_task(reconnect(0));}
	} else if (extra == "off" && db->readonly) {
		werror("SWITCHING TO READ-WRITE MODE: %O\n", host);
		db->conn->query(#"select set_config('application_name', 'stillebot', false),
				set_config('default_transaction_read_only', 'off', false)");
		db->readonly = 0;
		if (!active) _have_active(host);
	}
	//Else we're setting the mode we're already in. This may indicate a minor race
	//condition on startup, but we're already going to be in the right state anyway.
}

void notify_unknown(int pid, string cond, string extra, string host) {
	werror("[%s] Unknown notification %O from pid %O, extra %O\n", host, cond, pid, extra);
}

//Called whenever we have settings available, notably after any change or potential change.
//Note that if you require _actual_ change detection, you'll need to do it yourself.
@create_hook: constant database_settings = ({"mapping settings"});
__async__ void fetch_settings(mapping db) {
	G->G->dbsettings = await((mixed)query(db, "select * from stillebot.settings"))[0];
	G->G->dbsettings->credentials = JSONDECODE(G->G->dbsettings->credentials);
	G->G->bot_uid = (int)G->G->dbsettings->credentials->userid; //Convenience alias. We use this in a good few places.
	werror("Got settings from %s: active bot %O\n", db->host, G->G->dbsettings->active_bot);
	event_notify("database_settings", G->G->dbsettings);
}

@"stillebot.settings":
void notify_settings_change(int pid, string cond, string extra, string host) {
	werror("SETTINGS CHANGED [%s]\n", host);
	spawn_task(fetch_settings(pg_connections[host]));
}

@"stillebot.http_sessions":
void notify_session_gone(int pid, string cond, string extra, string host) {
	werror("SESSION DELETED [%s, %s]\n", cond, extra);
	G->G->http_sessions_deleted[extra] = 1;
}

@"stillebot.commands":
void notify_command_added(int pid, string cond, string extra, string host) {
	if (!G->G->irc) return; //Interactive mode - no need to push updates out
	sscanf(extra, "%d:%s", int twitchid, string cmdname);
	if (!cmdname || cmdname == "") return;
	object channel = G->G->irc->id[twitchid]; if (!channel) return;
	spawn_task(load_commands(twitchid, cmdname))->then() {echoable_message cmd = __ARGS__[0];
		cmd = sizeof(cmd) && cmd[0]->content;
		G->G->cmdmgr->_save_command(channel, cmdname, cmd, (["nosave": 1]));
	};
}

void notify_callback(object conn, int pid, string channel, string payload) {
	(notify_channels[channel] || notify_unknown)(pid, channel, payload, conn->host);
}

__async__ void connect(string host) {
	object tm = System.Timer();
	werror("[%.3f] Connecting to Postgres on %O...\n", tm->peek(), host);
	mapping db = pg_connections[host] = (["host": host]); //Not a floop, strings are just strings :)
	string key = Stdio.read_file("privkey.pem");
	string cert = Stdio.read_file("certificate.pem");
	object ctx = SSLContext();
	array(string) root = Standards.PEM.Messages(Stdio.read_file("/etc/ssl/certs/ISRG_Root_X1.pem"))->get_certificates();
	ctx->add_cert(Standards.PEM.simple_decode(key), Standards.PEM.Messages(cert)->get_certificates() + root);
	#if constant(SSLDatabase)
	db->conn = SSLDatabase(host, (["ctx": ctx, "notify_callback": notify_callback]));
	werror("[%.3f] Established Sql.Sql, listening...\n", tm->peek());
	foreach (notify_channels; string channel; mixed callback)
		await(db->conn->query("listen \"" + channel + "\""));
	string ro = db->conn->server_params->default_transaction_read_only;
	#else
	while (1) {
		//Establishing the connection is synchronous, might not be ideal.
		db->conn = Sql.Sql("pgsql://rosuav@" + host + "/stillebot", ([
			"force_ssl": 1, "ssl_context": ctx, "application_name": "stillebot",
		]));
		db->conn->set_notify_callback("readonly", notify_readonly, 1, host);
		//Sometimes, the connection fails, but we only notice it here at this point when the
		//first query goes through. It won't necessarily even FAIL fail, it just stalls here.
		//So we limit how long this can take. When working locally, it takes about 100ms or
		//so; talking to a remote server, a couple of seconds. If it's been ten seconds, IMO
		//there must be a problem.
		mixed ex = catch {await(db->conn->promise_query("listen readonly")->timeout(10));};
		if (ex) {
			werror("Timeout connecting to %s, retrying...\n", host);
			continue;
		}
		break;
	}
	werror("[%.3f] Established pgssl, listening...\n", tm->peek());
	foreach (notify_channels; string channel; mixed callback) {
		db->conn->set_notify_callback(channel, callback, 1, host);
		await(query(db, "listen \"" + channel + "\""));
	}
	db->conn->set_notify_callback("", notify_unknown, 1, host);
	string ro = await(query(db, "show default_transaction_read_only"))[0]->default_transaction_read_only;
	#endif
	werror("[%.3f] Connected to %O - %s.\n", tm->peek(), host, ro == "on" ? "r/o" : "r-w");
	if (ro == "on") {
		await(query(db, "set application_name = 'stillebot-ro'"));
		db->readonly = 1;
	} else {
		//Any time we have a read-write database connection, update settings.
		//....????? I don't understand why, but if I don't store this in a
		//variable, it results in an error about ?: and void. My best guess is
		//the optimizer has replaced this if/else with a ?: maybe???
		mixed _ = await((mixed)fetch_settings(db));
	}
	db->connected = 1;
}

__async__ void reconnect(int force, int|void both) {
	if (force) {
		foreach (pg_connections; string host; mapping db) {
			if (!db->connected) {werror("Still connecting to %s...\n", host); continue;} //Will probably need a timeout somewhere
			werror("Closing connection to %s.\n", host);
			db->conn->close();
			destruct(db->conn); //Might not be necessary with SSLDatabase
		}
		m_delete(pg_connections, indices(pg_connections)[*]); //Mutate the existing mapping so all clones of the module see that there are no connections
	}
	foreach (database_ips, string host) {
		if (!pg_connections[host]) await((mixed)connect(host));
		if (!both && !pg_connections[host]->readonly) {_have_active(host); return;}
	}
	werror("No active DB, suspending saves\n");
	active = 0;
}

__async__ string save_sql(string|array sql, mapping bindings) {
	if (active) {
		mixed err = catch {await(query(pg_connections[active], sql, bindings));};
		if (!err) return "ok"; //All good!
		//Report the error to the console, since the caller isn't hanging around.
		//TODO: If the error is because there's actually no database available,
		//put ourselves in the queue.
		werror("Unable to save to database!\n%s\n", describe_backtrace(err));
		return "fail";
	}
	werror("Save pending! %s\n", sql);
	waiting_for_active->saveme += ({({sql, bindings})});
	return "retry";
}

Concurrent.Future save_config(string|int twitchid, string kwd, mixed data) {
	//TODO: If data is an empty mapping, delete it instead
	if (precached_config[kwd] && pcc_loadstate[kwd] == 2) {
		//Immediately (and synchronously) update the local cache.
		//Note that it will not be re-updated by the database trigger, to avoid trampling on ourselves.
		pcc_cache[kwd][(int)twitchid] = data;
	}
	data = JSONENCODE(data);
	return save_sql("insert into stillebot.config values (:twitchid, :kwd, :data) on conflict (twitchid, keyword) do update set data=:data",
		(["twitchid": (int)twitchid, "kwd": kwd, "data": data]));
}

__async__ mapping load_config(string|int twitchid, string kwd, mixed|void dflt) {
	//NOTE: If there's no database connection, this will block. For higher speed
	//queries, do we need a try_load_config() that would error out (or return null)?
	if (!active) await(await_active());
	array rows = await(query(pg_connections[active], "select data from stillebot.config where twitchid = :twitchid and keyword = :kwd",
		(["twitchid": (int)twitchid, "kwd": kwd])));
	if (!sizeof(rows)) return dflt || ([]);
	return JSONDECODE(rows[0]->data);
}

//Collect all configs of a particular keyword, returning them keyed by Twitch user ID.
__async__ mapping load_all_configs(string kwd) {
	if (!active) await(await_active());
	array rows = await(query(pg_connections[active], "select twitchid, data from stillebot.config where keyword = :kwd",
		(["kwd": kwd])));
	mapping ret = ([]);
	foreach (rows, mapping r) ret[r->twitchid] = JSONDECODE(r->data);
	return ret;
}

mapping load_cached_config(string|int twitchid, string kwd) {
	if (!precached_config[kwd]) error("Can only load_cached_config() with the keywords listed\n");
	if (pcc_loadstate[kwd] < 2) error("Config not yet loaded\n");
	return pcc_cache[kwd][(int)twitchid] || ([]);
}

//There's no decorator on this as the actual channel list is set by precached_config[]
void update_cache(int pid, string cond, string extra, string host) {
	if (pid == pg_connections[host]->?backendpid) return; //Ignore signals from our own updates
	sscanf(cond, "%*s:%s", string kwd);
	load_config(extra, kwd)->then() {pcc_cache[kwd][(int)extra] = __ARGS__[0];};
}

__async__ void preload_configs(array(string) kwds) {
	foreach (kwds, string kwd) {
		pcc_loadstate[kwd] = 1;
		pcc_cache[kwd] = ([]);
	}
	if (!active) await(await_active());
	array rows = await(query(pg_connections[active],
		"select twitchid, keyword, data from stillebot.config where keyword = any(:kwd)",
		(["kwd": kwds])));
	foreach (rows, mapping row)
		pcc_cache[row->keyword][(int)row->twitchid] = JSONDECODE(row->data);
	foreach (kwds, string kwd) pcc_loadstate[kwd] = 2;
}

//Doesn't currently support Sql.Sql().
__async__ mapping mutate_config(string|int twitchid, string kwd, function mutator) {
	if (!active) await(await_active());
	if (precached_config[kwd]) {
		//No transaction necessary here; we have the data in memory.
		if (pcc_loadstate[kwd] < 2) error("Config not yet loaded\n"); //Or maybe we don't.
		mapping data = pcc_cache[kwd][(int)twitchid] || ([]);
		mapping|void ret = mutator(data);
		if (mappingp(ret)) data = ret;
		return await(save_config(twitchid, kwd, data));
	}
	return await(pg_connections[active]->conn->transaction(__async__ lambda(function query) {
		//TODO: Is it worth having load_config/save_config support transactional mode?
		array rows = await(query("select data from stillebot.config where twitchid = :twitchid and keyword = :kwd",
			(["twitchid": (int)twitchid, "kwd": kwd])));
		mapping data = sizeof(rows) ? rows[0]->data : ([]);
		mapping|void ret = mutator(data, (int)twitchid, kwd); //Note that the mutator currently is expected to be synchronous. Is there need for awaits in here??
		if (mappingp(ret)) data = ret; //Otherwise, assume that the original mapping was mutated.
		await(query(
			sizeof(rows) ? "update stillebot.config set data = :data where twitchid = :twitchid and keyword = :kwd"
			: "insert into stillebot.config values (:twitchid, :kwd, :data)",
			(["twitchid": (int)twitchid, "kwd": kwd, "data": data])));
		return data;
	}));
}

//Call with two IDs for raids between those two channels, or with one ID for
//all raids involving that channel. If bidi is set, will also include raids
//the opposite direction.
__async__ array load_raids(string|int fromid, string|int toid, int|void bidi) {
	if (!active) await(await_active());
	if (!toid && !fromid) return ({ }); //No you can't get "every raid, ever".
	string sql;
	if (!toid) { //TODO: Tidy this up a bit, it's a mess.
		if (bidi) sql = "fromid = :fromid or toid = :fromid";
		else sql = "fromid = :fromid";
	} else if (!fromid) {
		if (bidi) sql = "toid = :toid or fromid = :toid";
		else sql = "toid = :toid";
	} else {
		if (bidi) sql = "(fromid = :fromid and toid = :toid) or (fromid = :toid and toid = :fromid)";
		else sql = "fromid = :fromid and toid = :toid";
	}
	array rows = await(query(pg_connections[active], "select * from stillebot.raids where " + sql,
		(["fromid": (int)fromid, "toid": (int)toid])));
	return rows; //TODO upon switching back to Sql.Sql: JSONDECODE the data fields
}

//NOTE: Automatically appends to the raids, does not replace.
__async__ void add_raid(string|int fromid, string|int toid, mapping raid) {
	array raids = await(load_raids(fromid, toid));
	if (!sizeof(raids)) raids = ({raid}); //No raids recorded, start fresh
	else if (raids[0]->data[-1]->time > raid->time - 60) return; //Ignore duplicate raids within 60s
	else raids = raids[0]->data + ({raid});
	await(save_sql("insert into stillebot.raids values (:fromid, :toid, :data) on conflict (fromid, toid) do update set data=:data",
		(["fromid": (int)fromid, "toid": toid, "data": JSONENCODE(raids)])));
}

//Command IDs are UUIDs. They come back in binary format, which is fine for comparisons,
//but not for human readability. Try this:
//sprintf("%x%x-%x-%x-%x-%x%x%x", @array_sscanf("F\255C|\377gK\316\223iW\351\215\37\377=", "%{%2c%}")[0][*][0]);
//or:
//sscanf("F\255C|\377gK\316\223iW\351\215\37\377=", "%{%2c%}", array words);
//sprintf("%x%x-%x-%x-%x-%x%x%x", @words[*][0]);
__async__ array(mapping) load_commands(string|int twitchid, string|void cmdname, int|void allversions) {
	if (!active) await(await_active());
	string sql = "select * from stillebot.commands where twitchid = :twitchid";
	mapping bindings = (["twitchid": twitchid]);
	if (cmdname) {sql += " and cmdname = :cmdname"; bindings->cmdname = cmdname;}
	if (!allversions) sql += " and active";
	array rows = await(query(pg_connections[active], sql, bindings));
	foreach (rows, mapping command) command->content = JSONDECODE(command->content); //Unnecessary with SSLDatabase
	return rows;
}

Concurrent.Future save_command(string|int twitchid, string cmdname, echoable_message content) {
	return save_sql(({
		"update stillebot.commands set active = false where twitchid = :twitchid and cmdname = :cmdname and active = true",
		content && content != ""
			? "insert into stillebot.commands (twitchid, cmdname, active, content) values (:twitchid, :cmdname, true, :content)"
			: "select pg_notify('stillebot.commands', concat(cast(:twitchid as text), ':', cast(:cmdname as text)))",
	}), ([
		"twitchid": twitchid, "cmdname": cmdname,
		"content": JSONENCODE(content),
	]));
}

//NOTE: In the future, this MAY be changed to require that data be JSON-compatible.
//The mapping MUST include a 'cookie' which is a short string.
Concurrent.Future save_session(mapping data) {
	if (!stringp(data->cookie)) return Concurrent.resolve(0);
	if (sizeof(data) == 1)
		//Saving (["cookie": "nomnom"]) with no data will delete the session.
		return save_sql("delete from stillebot.http_sessions where cookie = :cookie", data);
	else return save_sql("insert into stillebot.http_sessions (cookie, data) values (:cookie, :data) on conflict (cookie) do update set data=:data, active = now()",
		(["cookie": data->cookie, "data": encode_value(data)]));
}

__async__ mapping load_session(string cookie) {
	if (!cookie || cookie == "") return ([]); //Will trigger new-cookie handling on save
	if (!active) await(await_active());
	array rows = await(query(pg_connections[active], "select data from stillebot.http_sessions where cookie = :cookie",
		(["cookie": cookie])));
	if (!sizeof(rows)) return (["cookie": cookie]);
	//For some reason, sometimes I get an array of strings instead of an array of mappings.
	mapping|string data = rows[0];
	if (mappingp(data)) data = data->data;
	return decode_value(data);
}

//Generate a new session cookie that definitely doesn't exist
__async__ string generate_session_cookie() {
	if (!active) await(await_active());
	while (1) {
		string cookie = random(1<<64)->digits(36);
		mixed ex = catch {await(query(pg_connections[active], "insert into stillebot.http_sessions (cookie, data) values(:cookie, '')",
			(["cookie": cookie])));};
		if (!ex) return cookie;
		//TODO: If it wasn't a PK conflict, let the exception bubble up
		werror("COOKIE INSERTION\n%s\n", describe_backtrace(ex));
		await(task_sleep(1));
	}
}

//Generic SQL query on the current database. Not recommended; definitely not recommended for
//any mutation; use the proper load_config/save_config/save_sql instead. This is deliberately
//NOT exported - avoid it unless there's no better way.
__async__ mapping generic_query(string sql, mapping|void bindings) {
	if (!pg_connections[active]) {
		await(reconnect(0));
		if (!active) error("No database connection available.\n");
	}
	return await(query(pg_connections[active], sql, bindings));
}

//Don't use this. If you are in a proper position to violate that rule, you already know what
//you're doing. Future me: Past me sincerely hopes that you decide you can't justify using this.
__async__ mapping for_each_db(string sql, mapping|void bindings) {
	await(reconnect(0, 1));
	mapping ret = ([]);
	foreach (pg_connections; string host; mapping db)
		ret[host] = await(query(db, sql, bindings));
	return ret;
}

//Credentials are stored in stillebot.confing under (twitchid, 'credentials')
//and have the following keys (or some subset of them):
//userid    - Twitch user ID, as an integer
//login     - Twitch user name (mandatory)
//token     - the actual Twitch OAuth login (mandatory)
//authcookie- returned by the OAuth process and contains most other info, encode_value()'d
//scopes    - sorted array of strings of Twitch scopes. May be empty.
//validated - time() when the login was last checked. This is either when the login was done, or
//            when /oauth2/validate was used on it. This does NOT count other calls using the token.
//user_info - mapping of additional info from Twitch. Advisory only, may have changed. Will often
//            contain display_name though, which could be handy.
//TODO: What happens as things get bigger? Eventually this will be a lot of loading. Should
//the credentials query functions be made async and do the fetching themselves?
//Note that this is nearly identical to the more general precached config feature, but the
//cache is dual-keyed. It might be better to have the cache keyed only by ID?
__async__ void preload_user_credentials() {
	G->G->user_credentials_loading = 1;
	mapping cred = G->G->user_credentials = ([]);
	if (!active) await(await_active());
	array rows = await(query(pg_connections[active], "select twitchid, data from stillebot.config where keyword = 'credentials'"));
	foreach (rows, mapping row) {
		mapping data = JSONDECODE(row->data);
		cred[(int)row->twitchid] = cred[data->login] = data;
	}
	G->G->user_credentials_loaded = 1;
	m_delete(G->G, "user_credentials_loading");
}

@create_hook: constant credentials_changed = ({"mapping cred"});
@"stillebot.config:credentials":
void notify_credentials_changed(int pid, string cond, string extra, string host) {
	load_config(extra, "credentials")->then() {[mapping data] = __ARGS__;
		mapping cred = G->G->user_credentials;
		cred[(int)extra] = cred[data->login] = data;
		event_notify("credentials_changed", data);
	};
}

//Save credentials, but also synchronously update the local version. Using save_config() would
//not do the latter, resulting in a short delay before the new credentials are used.
Concurrent.Future save_user_credentials(mapping data) {
	mapping cred = G->G->user_credentials;
	cred[data->userid] = cred[data->login] = data;
	return save_config(data->userid, "credentials", data);
}

__async__ array(mapping) list_ephemeral_files(string|int channel, string|int uploader, string|void id, int|void include_blob) {
	if (!active) await(await_active());
	return await(G->G->DB->generic_query(
		"select id, metadata" + (include_blob ? ", data" : "") +
		" from stillebot.uploads where channel = :channel and uploader = :uploader and expires is not null"
		+ (id ? " and id = :id" : ""),
		(["channel": channel, "uploader": uploader, "id": id]),
	));
}

__async__ array(mapping) list_channel_files(string|int channel, string|void id) {
	if (!active) await(await_active());
	return await(G->G->DB->generic_query(
		"select id, metadata from stillebot.uploads where channel = :channel and expires is null"
		+ (id ? " and id = :id" : ""),
		(["channel": channel, "id": id]),
	));
}

__async__ mapping|zero get_file(string id, int|void include_blob) {
	if (!active) await(await_active());
	array rows = await(G->G->DB->generic_query(
		"select id, channel, uploader, metadata, expires" + (include_blob ? ", data" : "") +
		" from stillebot.uploads where id = :id",
		(["id": id]),
	));
	return sizeof(rows) && rows[0];
}

__async__ string prepare_file(string|int channel, string|int uploader, mapping metadata, int(1bit) ephemeral) {
	if (!active) await(await_active());
	return await(G->G->DB->generic_query(
		"insert into stillebot.uploads (channel, uploader, data, metadata, expires) values (:channel, :uploader, '', :metadata, "
			+ (ephemeral ? "now() + interval '24 hours'" : "NULL") + ") returning id",
		(["channel": channel, "uploader": uploader, "metadata": metadata]),
	))[0]->id;
}

void update_file(string(21bit) id, mapping metadata, string(8bit)|void raw) {
	G->G->DB->save_sql(
		"update stillebot.uploads set " + (raw ? "data = :data, " : "") + "metadata = :metadata where id = :id",
		(["id": id, "data": raw, "metadata": metadata]),
	);
}

//TODO: Use save_sql? What if we need to be able to await this?
Concurrent.Future purge_ephemeral_files(string|int channel, string|int uploader, string|void id) {
	return G->G->DB->generic_query(
		"delete from stillebot.uploads where channel = :channel and uploader = :uploader"
			+ (id ? " and id = :id" : "") + " and expires is not null returning id, metadata",
		(["channel": channel, "uploader": uploader, "id": id]),
	);
}

void delete_file(string id) {
	G->G->DB->save_sql("delete from stillebot.uploads where id = :id", (["id": id]));
}

@"stillebot.config:botconfig":
void notify_botconfig_changed(int pid, string cond, string extra, string host) {
	load_config(extra, "botconfig")->then() {[mapping data] = __ARGS__;
		werror("botconfig changed for %O\n", extra);
		mapping channel = G->G->irc->?id[?(int)extra];
		if (channel) channel->reconfigure(data);
	};
}

@"stillebot.botservice":
void notify_botservice_changed(int pid, string cond, string extra, string host) {
	werror("botservice changed!\n");
	if (function f = is_active_bot() && G->G->on_botservice_change) f();
}

//Attempt to create all tables and alter them as needed to have all columns
__async__ void create_tables() {
	await(reconnect(1, 1)); //Ensure that we have at least one connection, both if possible
	array(mapping) dbs;
	if (active) {
		//We can't make changes, but can verify and report inconsistencies.
		dbs = ({pg_connections[active]});
	} else if (!sizeof(pg_connections)) {
		//No connections, nothing succeeded
		error("Unable to verify database status, no PostgreSQL connections\n");
	} else {
		//Update all databases. This is what we normally want.
		dbs = values(pg_connections);
	}
	foreach (dbs, mapping db) {
		array cols = await(query(db, "select table_name, column_name from information_schema.columns where table_schema = 'stillebot' order by table_name, ordinal_position"));
		array stmts = ({ });
		mapping(string:array(string)) havecols = ([]);
		foreach (cols, mapping col) havecols[col->table_name] += ({col->column_name});
		foreach (tables; string tbname; array cols) {
			if (!havecols[tbname]) {
				//The table doesn't exist. Create it from scratch.
				array extras = filter(cols, has_suffix, ";");
				stmts += ({
					sprintf("create table stillebot.%s (%s)", tbname, (cols - extras) * ", "),
				}) + extras;
				continue;
			}
			//If we have columns that aren't in the table's definition,
			//drop them. If the converse, add them. There is no provision
			//here for altering columns.
			string alter = "";
			multiset sparecols = (multiset)havecols[tbname];
			foreach (cols, string col) {
				if (has_suffix(col, ";") || has_prefix(col, " ")) continue;
				sscanf(col, "%s ", string colname);
				if (sparecols[colname]) sparecols[colname] = 0;
				else alter += ", add " + col;
			}
			//If anything hasn't been removed from havecols, it should be dropped.
			foreach (sparecols; string colname;) alter += ", drop " + colname;
			if (alter != "") stmts += ({"alter table stillebot." + tbname + alter[1..]}); //There'll be a leading comma
			else write("Table %s unchanged\n", tbname);
		}
		if (sizeof(stmts)) {
			if (active) error("Table structure changes needed!\n%O\n", stmts);
			werror("Making changes on %s: %O\n", db->host, stmts);
			#if constant(SSLDatabase)
			await(db->conn->transaction(__async__ lambda(function query) {
				foreach (stmts, string stmt) await(query(stmt));
			}));
			#else
			await(query(db, "begin read write"));
			foreach (stmts, string stmt) await(query(db, stmt));
			await(query(db, "commit"));
			#endif
			werror("Be sure to `./dbctl refreshrepl` on both ends!\n");
		}
	}
}

__async__ void create_tables_and_stop() {
	await(create_tables());
	exit(0);
}

protected void create(string name) {
	::create(name);
	#if !constant(INTERACTIVE)
	foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
		if (ann) foreach (indices(ann), mixed anno)
			if (stringp(anno)) notify_channels[anno] = this[key];
	}
	array needkwd = ({ });
	foreach (precached_config; string kwd;) {
		notify_channels["stillebot.config:" + kwd] = update_cache;
		if (!pcc_loadstate[kwd]) needkwd += ({kwd});
	}
	if (sizeof(needkwd)) preload_configs(needkwd);
	#endif
	//For testing, force the opposite connection order
	if (has_value(G->G->argv, "--gideondb")) database_ips = ({"ipv4.rosuav.com", "sikorsky.rosuav.com"});
	G->G->DB = this;
	spawn_task(reconnect(1));
	if (!G->G->http_sessions_deleted) G->G->http_sessions_deleted = ([]);
	if (!G->G->user_credentials_loading && !G->G->user_credentials_loaded) preload_user_credentials();
}

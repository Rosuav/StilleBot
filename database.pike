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

		//This has nothing to do with stillebot.settings, but it needs to go somewhere.
		//Or maybe not. It isn't currently being used. Kept in case it's useful.
		//"create or replace function throw(msg varchar) returns void language plpgsql as $$begin raise '%', msg; end$$;",
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
		//Another not tested.
		//"create or replace function send_upload_notification() returns trigger language plpgsql as $$begin perform pg_notify('stillebot.uploads', old.channel::text || '-' || old.id::text); return null; end$$;",
		//"create or replace trigger uploads_update_notify after update or delete on stillebot.uploads for each row execute function send_upload_notification();",
		//"alter table stillebot.uploads enable always trigger uploads_update_notify;",
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
		"bot text not null",
		"sighted timestamp with time zone not null default now()",
		" primary key (twitchid, login, bot)",
	}),
]);
//TODO: Have other modules submit requests for configs to be precached??
multiset precached_config = (<"channel_labels", "variables", "monitors", "voices">);
@retain: mapping pcc_loadstate = ([]);
@retain: mapping pcc_cache = ([]);

//NOTE: Despite this retention, actual connections are not currently retained across code
//reloads - the old connections will be disposed of and fresh ones acquired. There may be
//some sort of reference loop - it seems that we're not disposing of old versions of this
//module properly - but the connections themselves should be closed by the new module.
@retain: mapping(string:mapping(string:mixed)) pg_connections = ([]);
string livedb, fastdb; //Host name for the current read-write database, and possibly a local fast (but read-only) db
@retain: mapping waiting_for_database = ([
	"livequeue": ({ }), //Add a Promise to this to be told when there's a read-write database.
	"fastqueue": ({ }), //Ditto but can be handled from a read-only database
]);
array(string) database_ips = ({"sikorsky.mustardmine.com", "gideon.mustardmine.com"});
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
	G->G->serverstatus_statistics->db_request_count++;
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

void _have_fastdb(string host) {
	if (G->G->DB != this) return; //Let the current version of the code handle them
	werror("*** HAVE FAST DB: %O\n", host);
	fastdb = host;
	array wa = waiting_for_database->fastqueue; waiting_for_database->fastqueue = ({ });
	wa->success(1);
}
void _have_livedb(string host) {
	if (G->G->DB != this) return;
	werror("*** HAVE LIVE DB: %O\n", host);
	livedb = host;
	array wa = waiting_for_database->livequeue + waiting_for_database->fastqueue;
	waiting_for_database->livequeue = waiting_for_database->fastqueue = ({ });
	wa->success(1);
}
Concurrent.Future await_fastdb() {
	Concurrent.Promise pending = Concurrent.Promise();
	waiting_for_database->fastqueue += ({pending});
	return pending->future();
}
Concurrent.Future await_livedb() {
	Concurrent.Promise pending = Concurrent.Promise();
	waiting_for_database->livequeue += ({pending});
	return pending->future();
}

//Generic SQL query handlers. Use _ro for potentially higher performance local database,
//no mutations allowed; use _rw to guarantee that it's the live DB.
__async__ array query_ro(string|array sql, mapping|void bindings) {
	if (!fastdb && !livedb) await(await_fastdb());
	return await(query(pg_connections[fastdb] || pg_connections[livedb], sql, bindings));
}

__async__ array query_rw(string|array sql, mapping|void bindings) {
	if (!livedb) await(await_livedb());
	return await(query(pg_connections[livedb], sql, bindings));
}

class SSLContext {
	inherit SSL.Context;
	array|zero find_cert_issuer(array(string) ders) {
		if (sizeof(cert_chains_issuer)) return values(cert_chains_issuer)[0]; //Return the first available cert
		return ::find_cert_issuer(ders);
	}
}

@"readonly":
void notify_readonly(int pid, string cond, string extra, string host) {
	mapping db = pg_connections[host];
	if (extra == "on" && !db->readonly) {
		werror("SWITCHING TO READONLY MODE: %O\n", host);
		db->conn->query(#"select set_config('application_name', 'stillebot-ro', false),
				set_config('default_transaction_read_only', 'on', false)");
		db->readonly = 1;
		//If this one was the live (read-write) DB, we no longer have a read-write DB.
		//However, it's still allowed to continue serving as the fast DB.
		if (livedb == host) {livedb = 0; spawn_task(reconnect(0));}
		if (G->G->database_status_changed) G->G->database_status_changed();
	} else if (extra == "off" && db->readonly) {
		werror("SWITCHING TO READ-WRITE MODE: %O\n", host);
		db->conn->query(#"select set_config('application_name', 'stillebot', false),
				set_config('default_transaction_read_only', 'off', false)");
		db->readonly = 0;
		if (!livedb) _have_livedb(host);
		if (G->G->database_status_changed) G->G->database_status_changed();
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
	G->G->http_sessions_deleted[extra] = 1;
	//If there are any session decryption keys for that session (at any channel), purge them too
	array purge = filter(indices(G->G->session_decryption_key), has_suffix, ":" + extra);
	if (sizeof(purge)) m_delete(G->G->session_decryption_key, purge[*]);
}

@"stillebot.conduit_broken":
void notify_conduit_broken(int pid, string cond, string extra, string host) {
	werror("Conduit broken, signalled via database - %O\n", extra);
	Stdio.append_file("conduit_reconnect.log", sprintf("%sDATABASE CONDUIT BROKEN: %O\n", ctime(time()), (["host": host, "extra": extra])));
	if (is_active_bot()) G->G->setup_conduit();
	else werror("Not active bot, ignoring (active is %O)\n", get_active_bot());
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
	(notify_channels[channel] || notify_unknown)(pid, channel, payload, conn->cfg->host);
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
	db->conn = SSLDatabase((["host": host, "user": "rosuav", "application_name": "stillebot", "database": "stillebot"]),
		(["ctx": ctx, "host": host, "notify_callback": notify_callback]));
	werror("[%.3f] Established pgssl, listening...\n", tm->peek());
	if (sizeof(notify_channels)) await(db->conn->batch(sprintf("listen \"%s\"", indices(notify_channels)[*])));
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
	werror("[%.3f] Established Sql.Sql, listening...\n", tm->peek());
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
		fastdb = livedb = 0; //Signal that we have no databases (they'll be made available again after reconnection)
		foreach (pg_connections; string host; mapping db) {
			if (!db->connected) {werror("Still connecting to %s...\n", host); continue;} //Will probably need a timeout somewhere
			werror("Closing connection to %s.\n", host);
			if (db->conn) db->conn->close();
			destruct(db->conn); //Might not be necessary with SSLDatabase
		}
		m_delete(pg_connections, indices(pg_connections)[*]); //Mutate the existing mapping so all clones of the module see that there are no connections
	}
	foreach (database_ips, string host) {
		if (!pg_connections[host]) await((mixed)connect(host));
		if (!both && host == G->G->instance_config->local_address) _have_fastdb(host);
		if (!both && !pg_connections[host]->readonly) {_have_livedb(host); return;}
	}
	werror("No read-write DB, suspending saves\n");
	livedb = 0;
}

Concurrent.Future save_sql(string|array sql, mapping bindings) {return query_rw(sql, bindings);}

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

//TODO maybe: If we get a signal to update_cache for something we're already halfway through
//loading, ignore it and let the existing request go through. Would save a little traffic.
//multiset pcc_loading = (<>);
__async__ mapping load_config(string|int twitchid, string kwd, mixed|void dflt, int|void force) {
	//NOTE: If there's no database connection, this will block. For higher speed
	//queries, do we need a try_load_config() that would error out (or return null)?
	if (precached_config[kwd] && !force) {
		while (pcc_loadstate[kwd] < 2) sleep(0.25); //Simpler than having a load-state promise
		return pcc_cache[kwd][(int)twitchid] || ([]);
	}
	array rows = await(query_ro("select data from stillebot.config where twitchid = :twitchid and keyword = :kwd",
		(["twitchid": (int)twitchid, "kwd": kwd])));
	if (!sizeof(rows)) return dflt || ([]);
	return JSONDECODE(rows[0]->data);
}

//Collect all configs of a particular keyword, returning them keyed by Twitch user ID.
__async__ mapping load_all_configs(string kwd) {
	array rows = await(query_ro("select twitchid, data from stillebot.config where keyword = :kwd",
		(["kwd": kwd])));
	mapping ret = ([]);
	foreach (rows, mapping r) ret[r->twitchid] = JSONDECODE(r->data);
	return ret;
}

//Fully synchronous, works only on precached configs.
mapping load_cached_config(string|int twitchid, string kwd) {
	if (!precached_config[kwd]) error("Can only load_cached_config() with the keywords listed\n");
	if (pcc_loadstate[kwd] < 2) error("Config not yet loaded\n");
	return pcc_cache[kwd][(int)twitchid] || ([]);
}

//There's no decorator on this as the actual channel list is set by precached_config[]
void update_cache(int pid, string cond, string extra, string host) {
	if (pid == pg_connections[host]->?conn->?backendpid) return; //Ignore signals from our own updates
	sscanf(cond, "%*s:%s", string kwd);
	#ifdef PGSSL_TIMING
	werror("[%d] Got update_cache signal %O %O\n", time(), cond, extra);
	#endif
	load_config(extra, kwd, 0, 1)->then() {
		pcc_cache[kwd][(int)extra] = __ARGS__[0];
		#ifdef PGSSL_TIMING
		werror("[%d] Done update_cache for %O %O\n", time(), cond, extra);
		#endif
	};
}

__async__ void preload_configs(array(string) kwds) {
	foreach (kwds, string kwd) {
		pcc_loadstate[kwd] = 1;
		pcc_cache[kwd] = ([]);
	}
	array rows = await(query_ro("select twitchid, keyword, data from stillebot.config where keyword = any(:kwd)",
		(["kwd": kwds])));
	foreach (rows, mapping row)
		pcc_cache[row->keyword][(int)row->twitchid] = JSONDECODE(row->data);
	foreach (kwds, string kwd) pcc_loadstate[kwd] = 2;
}

//Doesn't currently support Sql.Sql().
__async__ mapping mutate_config(string|int twitchid, string kwd, function mutator) {
	if (!livedb) await(await_livedb());
	if (precached_config[kwd]) {
		//No transaction necessary here; we have the data in memory.
		if (pcc_loadstate[kwd] < 2) error("Config not yet loaded\n"); //Or maybe we don't.
		mapping data = pcc_cache[kwd][(int)twitchid] || ([]);
		mapping|void ret = mutator(data);
		if (mappingp(ret)) data = ret;
		return await(save_config(twitchid, kwd, data));
	}
	return await(pg_connections[livedb]->conn->transaction(__async__ lambda(function query) {
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
	array rows = await(query_ro("select * from stillebot.raids where " + sql,
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
	string sql = "select * from stillebot.commands where twitchid = :twitchid";
	mapping bindings = (["twitchid": twitchid]);
	if (cmdname) {sql += " and cmdname = :cmdname"; bindings->cmdname = cmdname;}
	if (allversions) sql += " order by created desc, cmdname";
	else sql += " and active";
	array rows = await(query_ro(sql, bindings));
	//foreach (rows, mapping command) command->content = JSONDECODE(command->content); //Unnecessary with SSLDatabase
	return rows;
}

__async__ mapping(int:array(mapping)) preload_commands(array(int) twitchids) {
	array rows = await(query_ro("select * from stillebot.commands where twitchid = any(:twitchids) and active", (["twitchids": twitchids])));
	mapping ret = mkmapping(twitchids, allocate(sizeof(twitchids), ({ }))); //Ensure that there's an array for every ID checked, even if no actual commands are found
	foreach (rows, mapping row) ret[row->twitchid] += ({row});
	return ret;
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

Concurrent.Future revert_command(string|int twitchid, string cmdname, string uuid) {
	return save_sql(({
		"update stillebot.commands set active = false where twitchid = :twitchid and cmdname = :cmdname and active = true",
		"update stillebot.commands set active = true where twitchid = :twitchid and cmdname = :cmdname and id = :uuid",
		"select pg_notify('stillebot.commands', concat(cast(:twitchid as text), ':', cast(:cmdname as text)))",
	}), ([
		"twitchid": twitchid, "cmdname": cmdname,
		"uuid": uuid,
	]));
}

//NOTE: In the future, this MAY be changed to require that data be JSON-compatible.
//The mapping may include a 'cookie' which is a short string; if none is included and
//other session data exists, one will be generated; if a cookie is included but nothing
//else is specified, that session will be deleted.
//The session cookie (possibly freshly generated) will be returned, unless none existed
//and there was no data to save, in which case 0 is returned.
__async__ string|zero save_session(mapping data) {
	if (!data->cookie && sizeof(data)) {
		int retry = 2;
		while (1) {
			data->cookie = random(1<<64)->digits(36);
			mixed ex = catch {await(query_rw("insert into stillebot.http_sessions (cookie, data) values(:cookie, :data)",
				(["cookie": data->cookie, "data": encode_value(data)])));};
			if (!ex) return data->cookie;
			//TODO: If it wasn't a PK conflict, let the exception bubble up. Simplified check here - if the PK is mentioned, retry.
			if (!has_value(ex[0], "http_sessions_pkey") || !retry) throw(ex);
			--retry;
			werror("COOKIE INSERTION\n%s\n", describe_backtrace(ex));
		}
	}
	if (data->cookie && sizeof(data) == 1)
		//Saving (["cookie": "nomnom"]) with no data will delete the session.
		await(query_rw("delete from stillebot.http_sessions where cookie = :cookie", data));
	if (sizeof(data) < 2) return 0;
	await(query_rw("insert into stillebot.http_sessions (cookie, data) values (:cookie, :data) on conflict (cookie) do update set data=:data, active = now()",
		(["cookie": data->cookie, "data": encode_value(data)])));
	return data->cookie;
}

__async__ mapping load_session(string cookie) {
	if (!cookie || cookie == "") return ([]); //Will trigger new-cookie handling on save
	array rows = await(query_ro("select data from stillebot.http_sessions where cookie = :cookie",
		(["cookie": cookie])));
	if (!sizeof(rows)) return (["cookie": cookie]);
	//For some reason, sometimes I get an array of strings instead of an array of mappings.
	mapping|string data = rows[0];
	if (mappingp(data)) data = data->data;
	if (data == "") return (["cookie": cookie]); //Freshly-inserted sessions might exist but with blank data
	return decode_value(data);
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
	array rows = await(query_ro("select twitchid, data from stillebot.config where keyword = 'credentials'"));
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
	return await(query_ro(
		"select id, metadata" + (include_blob ? ", data" : "") +
		" from stillebot.uploads where channel = :channel and uploader = :uploader and expires is not null"
		+ (id ? " and id = :id" : ""),
		(["channel": channel, "uploader": uploader, "id": id]),
	));
}

__async__ array(mapping) list_channel_files(string|int channel, string|void id) {
	return await(query_ro(
		"select id, metadata from stillebot.uploads where channel = :channel and expires is null"
		+ (id ? " and id = :id" : ""),
		(["channel": channel, "id": id]),
	));
}

__async__ mapping|zero get_file(string id, int|void include_blob) {
	array rows = await(query_ro(
		"select id, channel, uploader, metadata, expires" + (include_blob ? ", data" : "") +
		" from stillebot.uploads where id = :id",
		(["id": id]),
	));
	return sizeof(rows) && rows[0];
}

constant MAX_PER_FILE = 16, MAX_TOTAL_STORAGE = 128; //MB
//Returns (["id": "some_urlsafe_string"]) on success, or (["error": "Human readable message"]) on failure.
//May in the future provide additional info eg remaining upload capacity
__async__ mapping prepare_file(string|int channel, string|int uploader, mapping metadata, int(1bit) ephemeral) {
	if (ephemeral) {
		//Currently ephemeral file permissions checking is all done in chan_share.pike - it may need to be moved
		//here also.
	} else {
		if (!intp(metadata->size) || metadata->size < 0) return 0; //Protocol error, not permitted. (Zero-length files are fine, although probably useless.)
		int used = await(query_ro(
			"select sum((metadata->'allocation')::int) from stillebot.uploads where channel = :channel and expires is null",
			(["channel": channel]),
		))[0]->allocation;
		//Count 1KB chunks, rounding up, and adding one chunk for overhead. Won't make much
		//difference to most files, but will stop someone from uploading twenty-five million
		//one-byte files, which would be just stupid :)
		int allocation = (metadata->size + 2047) / 1024;
		array mimetype = (metadata->mimetype || "") / "/";
		if (sizeof(mimetype) != 2)
			return (["error": sprintf("Unrecognized MIME type %O", metadata->mimetype)]);
		else if (!(<"image", "audio", "video">)[mimetype[0]])
			return (["error": "Only audio and image (including video) files are supported"]);
		else if (metadata->size > MAX_PER_FILE * 1048576)
			return (["error": "File too large (limit " + MAX_PER_FILE + " MB)"]);
		else if (used + allocation > MAX_TOTAL_STORAGE * 1024)
			return (["error": "Unable to upload, storage limit of " + MAX_TOTAL_STORAGE + " MB exceeded. Delete other files to make room."]);
		//Sanitize the attribute list, excluding anything we don't recognize.
		mapping attrs = ([
			"name": metadata->name, //TODO: Sanitize the name - at least a length check.
			"size": metadata->size, "allocation": allocation,
			"mimetype": metadata->mimetype,
			"owner": metadata->owner,
		]);
		if (metadata->autocrop) attrs->autocrop = metadata->autocrop;
		metadata = attrs;
	}
	return await(query_rw(
		"insert into stillebot.uploads (channel, uploader, data, metadata, expires) values (:channel, :uploader, '', :metadata, "
			+ (ephemeral ? "now() + interval '24 hours'" : "NULL") + ") returning id",
		(["channel": channel, "uploader": uploader, "metadata": metadata]),
	))[0];
}

Concurrent.Future update_file(string(21bit) id, mapping metadata, string(8bit)|void raw) {
	return query_rw(
		"update stillebot.uploads set " + (raw ? "data = :data, " : "") + "metadata = :metadata where id = :id",
		(["id": id, "data": raw, "metadata": metadata]),
	);
}

Concurrent.Future purge_ephemeral_files(string|int channel, string|int uploader, string|void id) {
	return query_rw(
		"delete from stillebot.uploads where channel = :channel and uploader = :uploader"
			+ (id ? " and id = :id" : "") + " and expires is not null returning id, metadata",
		(["channel": channel, "uploader": uploader, "id": id]),
	);
}

void delete_file(string|int channel, string id) {
	G->G->DB->save_sql("delete from stillebot.uploads where channel = :channel and id = :id", (["channel": channel, "id": id]));
}

//Identical, but the first is called if the file doesn't expire, the second if it does. Rarely will
//any module need both. NOTE: When a file is deleted, a notification will be sent out with the
//file ID and channel, and nothing else. Notably, file->metadata will be absent for deleted files.
//Note also that file deletion is always signalled via the first hook, not the second.
@create_hook: constant uploaded_file_edited = ({"mapping file"});
@create_hook: constant ephemeral_file_edited = ({"mapping file"});

@"stillebot.uploads":
__async__ void notify_file_updated(int pid, string cond, string extra, string host) {
	//Note that this could be a fresh upload (just received its blob), a simple
	//metadata edit, or file removal. Regardless, force it out to the websockets.
	if (!is_active_bot()) return; //Should be no websockets on an inactive bot anyway.
	sscanf(extra, "%d-%s", int channel, string id);
	if (!id) id = extra; //Legacy notification - no channel ID available
	mapping file = await(get_file(id)) || (["id": id, "channel": channel]);
	if (file->expires) event_notify("ephemeral_file_edited", file);
	else event_notify("uploaded_file_edited", file);
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
	if (function f = G->G->on_botservice_change) f();
}

@"scream.emergency":
void emergency(int pid, string cond, string extra, string host) {
	werror("EMERGENCY NOTIFICATION from %O: %O\n", host, extra);
	if (G->G->emergency) G->G->emergency();
}

string|zero last_desync_lsn = 0; //Null if the last check showed we were in sync
__async__ void replication_watchdog() {
	G->G->repl_wdog_call_out = call_out(replication_watchdog, 60);
	//Check to see if replication appears stalled.
	//If the R/W database is advancing, the fast database isn't, and they're different,
	//then we may have a stall. "Advancing" means the position isn't the same as it was
	//last check; we don't actually enforce monotonicity here.
	if (!livedb || !fastdb || livedb == fastdb) return; //Only worth doing this if we have separate DBs.
	//Note that we use query_rw to ensure that this lands on the live db. It's not actually mutating anything.
	array live = await(query_rw("select * from pg_replication_slots"));
	array repl = await(query_ro("select * from pg_stat_subscription"));
	if (!sizeof(live) || !sizeof(repl)) {
		//Might be down somewhere. Not sure what to do here.
		werror("REPL WDOG: %d live %d repl\n", sizeof(live), sizeof(repl));
		query_rw(sprintf("notify \"scream.emergency\", 'REPL WDOG: %d live %d repl'", sizeof(live), sizeof(repl)));
		return;
	}
	if (live[0]->confirmed_flush_lsn == repl[0]->received_lsn &&
			repl[0]->received_lsn == repl[0]->latest_end_lsn) {
		if (last_desync_lsn) werror("REPL WDOG: Back in sync %O\n", live[0]->confirmed_flush_lsn);
		last_desync_lsn = 0;
		return; //All good, in sync.
	}
	werror("REPL WDOG: live %O repl %O %O\n",
		live[0]->confirmed_flush_lsn,
		repl[0]->received_lsn, repl[0]->latest_end_lsn,
	);
	//I'm not sure what causes the LSN to be null, but I suspect it means replication isn't happening.
	if (!repl[0]->latest_end_lsn) query_rw("notify \"scream.emergency\", 'REPL WDOG: LSN is null!!'");
	//If the local LSN hasn't advanced in an entire minute, scream.
	if (repl[0]->latest_end_lsn == last_desync_lsn) query_rw("notify \"scream.emergency\", 'REPL WDOG: LSN has not advanced'");
	last_desync_lsn = repl[0]->latest_end_lsn;
}

//Attempt to create all tables and alter them as needed to have all columns
__async__ void create_tables() {
	await(reconnect(1, 1)); //Ensure that we have at least one connection, both if possible
	array(mapping) dbs;
	if (livedb) {
		//We can't make changes, but can verify and report inconsistencies.
		dbs = ({pg_connections[livedb]});
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
			if (livedb) error("Table structure changes needed!\n%O\n", stmts);
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

protected void create(string name) {
	::create(name);
	#if constant(INTERACTIVE)
	//In interactive mode, most notifications are disabled, but we still want to know about
	//changes to read-only/read-write status of a database.
	notify_channels->readonly = notify_readonly;
	#else
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
	//Move the local database to the front. If both are up, this will allow fast read-only
	//transactions even if the primary DB is the remote one.
	string addr = G->G->instance_config->local_address;
	if (has_value(database_ips, addr)) database_ips = ({addr}) + (database_ips - ({addr}));
	//For testing, allow inversion of the natural connection order
	if (G->G->args->swapdb) database_ips = ({database_ips[1], database_ips[0]});
	G->G->DB = this;
	spawn_task(reconnect(1));
	if (!G->G->http_sessions_deleted) G->G->http_sessions_deleted = ([]);
	if (!G->G->user_credentials_loading && !G->G->user_credentials_loaded) preload_user_credentials();
	remove_call_out(G->G->repl_wdog_call_out);
	G->G->repl_wdog_call_out = call_out(replication_watchdog, 60);
}

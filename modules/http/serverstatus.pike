#charset utf-8
inherit http_websocket;
inherit annotated;
constant valid_on_inactive_bot = 1;

constant markdown = #"# StilleBot server status

[Mini-view](#mini) $$guest||[Manage active servers](: .opendlg data-dlg=servercontrol)$$

<script src=\"https://cdn.jsdelivr.net/npm/chart.js\"></script>

<p id=content></p>
<figure id=graph><div style=\"width: 900px; height: 450px;\"><canvas></canvas></div><figcaption></figcaption></figure>

> ### Server Control
>
> <div id=servers></div>
>
> [Close](:.dialog_close)
{: tag=dialog #servercontrol}

<style>
.label {
	width: 5em;
	display: inline-block;
	font-weight: bold;
}
.percent {
	width: 2em;
	display: inline-block;
}
.percent::after {
	content: \"%\";
}
.db {
	margin-right: 1em;
}

#graph {
	display: flex;
	gap: 16px;
	margin: 0;
}
#graph figcaption {
	max-width: unset;
}
#servers {
	display: flex;
	gap: 0.5em;
	padding-inline-start: 0;
}
#servers fieldset {
	background: aliceblue;
	display: flex;
	flex-direction: column;
	gap: 2px;
}
</style>
";
mapping state = ([]), admin_state = ([]);
mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	state->responder = G->G->instance_config->local_address;
	if (req->variables->which) return jsonify(([
		"responder": G->G->instance_config->local_address, //If you ask for https://mustardmine.com/serverstatus?which, you will be told which bot actually responded.
		"active_bot": G->G->dbsettings->?active_bot || "",
		"db_fast": G->G->DB->fastdb,
		"db_live": G->G->DB->livedb,
	]));
	mapping params = (["vars": (["ws_group": ""])]);
	if (req->misc->session->user->?id == (string)G->G->bot_uid)
		params->vars->ws_group = "control"; //If logged in as the bot's intrinsic voice, permit interaction.
	else
		params->guest = ""; //Otherwise, hide all the admin-specific controls.
	return render(req, params);
}

array(int) cputime() {
	sscanf(Stdio.read_file("/proc/stat"), "cpu %d %d %d %d", int user, int nice, int sys, int idle);
	return ({user + nice + sys + idle, idle});
}

__async__ void updater() {
	while (G->G->serverstatus_updater) {
		await(task_sleep(1));
		mixed ex = catch {G->G->serverstatus_updatefunc();};
		if (ex) {G->G->serverstatus_updater = 0; werror("ERROR IN SERVER STATUS UPDATE:\n%s\n", describe_backtrace(ex));}
	}
}

void ensure_updater() {
	//Make sure we have the updater task running, if not, start it
	if (G->G->serverstatus_updater) return;
	G->G->serverstatus_updater = 1;
	G->G->serverstatus_cputime = cputime() + ({0});
	spawn_task(updater());
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//The bot's intrinsic voice is the only one permitted to use the control connection.
	if (msg->group == "control") {
		if (conn->session->user->?id != (string)G->G->bot_uid) return "Control connection restricted to admin";
		//If this is the first control connection, trigger an update to get the extra info.
		if (!sizeof(websocket_groups["control"] || ({ }))) call_out(update, 0.125);
	}
	//return "Server status unavailable"; //If desired, control access based on IP or whatever
	ensure_updater();
}

mapping get_state(string|int group) {
	if (group == "control") return state | admin_state; //More info for the control connection
	return state;
}

__async__ void checkdb(string which) {
	string db = G->G->DB[which];
	if (!db || (which == "fastdb" && db == G->G->DB->livedb)) {state[which] = ([]); return;}
	System.Timer tm = System.Timer();
	await(G->G->DB->pg_connections[db]->conn->query("select 1"));
	state[which] = (["host": (db / ".")[0], "ping": tm->peek()]);
}

__async__ void database_status() {
	admin_state->readonly = await(G->G->DB->query_ro("show default_transaction_read_only"))[0]->default_transaction_read_only;
	admin_state->replication = (int)await(G->G->DB->query_ro("select pid from pg_stat_subscription where subname = 'multihome'"))[0]->pid ? "active" : "inactive";
	//Not currently reporting this. You can see it in ./dbctl stat, just not in the UI.
	//It might be worth querying this, and then reporting only the lines that could represent issues, eg:
	// - An active bot on a read-only database (application_name == "stillebot" and readonly == "on")
	// - An external connection not from the bot IPs??
	// - The absence of replication??
	//This will be important during an automated hop procedure though (wait for all active bots to disappear).
	//admin_state->clients = await(G->G->DB->query_ro("select client_addr, application_name, xact_start, state from pg_stat_activity where usename = 'rosuav' and pid != pg_backend_pid()"));
	send_updates_all("control");
}

int lastdbcheck;
void update() {
	string spinner = "⠇⠦⠴⠸⠙⠋";
	catch { //If no nvidia-settings, leave those absent
		mapping proc = Process.run(({"nvidia-settings", "-t",
			"-q=:0/VideoEncoderUtilization",
			"-q=:0/VideoDecoderUtilization",
			"-q=:0/GPUUtilization",
		}));
		sscanf(proc->stdout, "%d\n%d\ngraphics=%d, memory=%d", state->enc, state->dec, state->gpu, state->vram);
	};
	[int lasttot, int lastidle, int spinnerpos] = G->G->serverstatus_cputime;
	[int tot, int idle] = cputime();
	if (tot == lasttot) --lasttot; //Prevent division by zero
	state->cpu = 100 - 100 * (idle - lastidle) / (tot - lasttot);
	state->spinner = (string)({spinner[spinnerpos % sizeof(spinner)]});
	G->G->serverstatus_cputime = ({tot, idle, spinnerpos + 1});
	sscanf(Stdio.read_file("/proc/meminfo"), "MemTotal: %d kB\nMemFree: %d kB\nMemAvailable: %d B", int memtotal, int memfree, int memavail);
	//Unsure whether it's better to report memfree or memavail
	state->ram = 100 - memavail * 100 / memtotal;
	state->ramtotal = memtotal / 1048576;
	//Check database timings periodically
	if (time() - lastdbcheck > 30) {
		lastdbcheck = time();
		checkdb("fastdb");
		checkdb("livedb");
	}
	//How many current websocket connections do we have?
	state->socket_count = concurrent_websockets();
	state->active_bot = get_active_bot();
	//If the control connection is active, gather additional stats.
	if (sizeof(websocket_groups["control"] || ({ }))) database_status();
	//If there's nobody listening, stop monitoring.
	send_updates_all("");
	if (!sizeof(websocket_groups[""] || ({ })) && !sizeof(websocket_groups["control"] || ({ }))) G->G->serverstatus_updater = 0;
}

constant LOAD_DEFINITIONS = ([
	"WS": (["color": ({0x66, 0x33, 0x99}), "unit": "concurrent users", "unscaled": 1, "desc": "WebSocket users"]),
	"HTTP": (["color": ({0x80, 0x10, 0x10}), "unit": "req/sec", "desc": "Web pages sent"]),
	"API": (["color": ({0x10, 0x80, 0x10}), "unit": "req/sec", "desc": "Twitch API calls"]),
	"IRC": (["color": ({0x10, 0x10, 0x80}), "unit": "msgs/sec", "desc": "Chat messages sent"]),
	"DB": (["color": ({0x10, 0x80, 0x80}), "unit": "req/sec", "desc": "Database requests"]),
]);

void send_graph(array socks) {
	//Read the log, grab the latest N entries, and plot them
	array lines = ((Stdio.read_file("serverstatus.log") || "") / "\n")[<144..]; //Assuming ten-minute stats, this is a day's data.
	array data = ({ }), colors = ({ }), defns = ({ }), times = ({ });
	mapping plots = ([]);
	foreach ("WS HTTP API IRC DB" / " ", string pfx) { //Predefine the order to ensure consistency. Needs to cover everything from LOAD_DEFINITIONS.
		mapping ld = LOAD_DEFINITIONS[pfx];
		plots[pfx] = sizeof(data);
		data += ({({ })});
		colors += ({ld->color});
		defns += ({ld});
		ld->prefix = pfx;
		ld->hexcolor = sprintf("#%02X%02X%02X", @ld->color);
	}
	int active = 0;
	foreach (lines, string line) {
		array parts = line / " ";
		if (sizeof(parts) < 2) continue;
		//parts[0] is date, parts[1] is time. We really only need the HH:MM from that.
		times += ({parts[1][..<3]});
		float duration = 1.0;
		foreach (parts[2..], string part) {
			sscanf(part, "%[A-Za-z]%d", string pfx, int|float val);
			if (pfx == "D") {if (!val) break; duration = (float)val;} //Duration zero? Ignore the line.
			if (pfx == "A") active = (int)val; //Retain the active status from the very last parseable line
			mapping ld = LOAD_DEFINITIONS[pfx]; if (!ld) continue; //Unknowns do not get displayed
			if (!ld->unscaled) val /= duration; //Some plots are not per-second (most are)
			data[plots[pfx]] += ({val});
		}
	}
	if (!sizeof(data)) return; //Nothing to plot
	array peaks = ({ });
	foreach (data, array plot) peaks += ({max(@plot)});
	string msg = Standards.JSON.encode(([
		"cmd": "graph", "active": active,
		"defns": defns, "peaks": peaks,
		"plots": data, "times": times,
	]), 4);
	foreach (socks, mapping sock)
		if (sock && sock->state == 1) sock->send_text(msg);
}

constant LOADSTATS_PERIOD = 600;
void loadstats() {
	G->G->serverstatus_loadstats = call_out(loadstats, LOADSTATS_PERIOD);
	mapping stats = G->G->serverstatus_statistics;
	//Format of log:
	//Date Time Token [token [token]]
	//Each token (after the date and time) has an alphabetic prefix followed by a numeric value
	//eg "WS26" means there were 26 websockets active during this time (high water mark).
	//All queries of the server stats should be atomically destructive, ensuring that consistent
	//numbers are used even if other operations are concurrently incrementing them.
	Stdio.append_file("serverstatus.log", sprintf("%s D%d A%d WS%d HTTP%d API%d IRC%d DB%d\n",
		Calendar.ISO.Second()->format_time(),
		stats->time && time() - stats->time, //Duration of statistical period
		is_active_bot(), //Note that this does not show whether we were active DURING the time, just at the end of it.
		m_delete(stats, "websocket_hwm"),
		m_delete(stats, "http_request_count"),
		m_delete(stats, "api_request_count"),
		m_delete(stats, "irc_message_count"),
		m_delete(stats, "db_request_count"),
	));
	stats->time = time();
	stats->websocket_hwm = concurrent_websockets();
	array ws = (websocket_groups[""] || ({ })) + (websocket_groups["control"] || ({ }));
	if (sizeof(ws)) send_graph(ws);
}

void websocket_cmd_graph(mapping(string:mixed) conn, mapping(string:mixed) msg) {send_graph(({conn->sock}));}

void websocket_cmd_hello(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	werror("HELLO! I am %O and the active bot is %O\n", G->G->instance_config->local_address, get_active_bot());
}

__async__ void websocket_cmd_db_down(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->group != "control") return;
	werror("Bringing database down...\n");
	//Using query_ro to keep it on the local database.
	await(G->G->DB->query_ro(({
		"alter database stillebot set default_transaction_read_only = on",
		"notify readonly, 'on'",
	})));
	//When the change takes effect, we should get a notification.
}

__async__ void websocket_cmd_db_up(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->group != "control") return;
	werror("Bringing database up...\n");
	await(G->G->DB->local_read_write_transaction(__async__ lambda(function query) {
		await(query("alter database stillebot reset default_transaction_read_only"));
		await(query("notify readonly, 'off'"));
	}));
}

void websocket_cmd_irc_reconnect(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->group != "control") return;
	werror("Forcing IRC reconnect.\n");
	foreach (G->G->irc_callbacks; string name; object module) {
		werror("IRC module %O:\n", name);
		foreach (module->connection_cache; string voice; object irc) {
			werror("\t%s: %O\n", voice, irc->sock);
			irc->options->outdated = 1;
			irc->quit();
		}
		werror("%d connections kicked.\n", sizeof(module->connection_cache));
	}
	G->G->on_botservice_change();
}

void websocket_cmd_activate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->group != "control") return;
	werror("TODO: Activate the bot here.\n");
	//This should take care of everything with a single click.
	//The front end should first send a "DB down" request to the up database, unless that is the one being activated.
	//TODO: Add a logging system so that updates can be pushed out smoothly
	//1) If the database is Up here, skip to step 7.
	//2) Wait until database is Down on both nodes (when we have no G->G->DB->livedb).
	//3) Check replication status. Report if not synchronized.
	//4) Check currently-connected clients. Report if any are read-write (application_name == "stillebot").
	//5) Repeat from step 3 until all is clear.
	//6) Bring database Up here. Monitor until we get the notification that the DB is now up.
	//7) update stillebot.settings set active_bot = :self, (["self": instance_config->local_address]);
	//8) Notify in the log when we are fully active, by some definition.
	//Until we reach step 8, disable all the buttons in the UI?
}

protected void create(string name) {
	::create(name);
	G->G->database_status_changed = database_status; //Called by database.pike whenever vital status changes
	G->G->serverstatus_updatefunc = update;
	remove_call_out(G->G->serverstatus_loadstats);
	G->G->serverstatus_loadstats = call_out(loadstats, LOADSTATS_PERIOD - (time() % LOADSTATS_PERIOD));
}

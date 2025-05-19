#charset utf-8
inherit http_websocket;
inherit annotated;

constant markdown = #"# StilleBot server status

[Mini-view](#mini)

<script src=\"https://cdn.jsdelivr.net/npm/chart.js\"></script>

<p id=content></p>
<figure id=graph><div style=\"width: 900px; height: 450px;\"><canvas></canvas></div><figcaption></figcaption></figure>

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
</style>
";
mapping state = ([]);
mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	state->responder = G->G->instance_config->local_address;
	if (req->variables->which) return jsonify(([
		"responder": G->G->instance_config->local_address, //If you ask for https://mustardmine.com/serverstatus?which, you will be told which bot actually responded.
		"active_bot": G->G->dbsettings->?active_bot || "",
		"db_fast": G->G->DB->fastdb,
		"db_live": G->G->DB->livedb,
	]));
	return render(req, (["vars": (["ws_group": ""])]));
}

array(int) cputime() {
	sscanf(Stdio.read_file("/proc/stat"), "cpu %d %d %d %d", int user, int nice, int sys, int idle);
	return ({user + nice + sys + idle, idle});
}

__async__ void updater() {
	while (G->G->serverstatus_updater) {
		await(task_sleep(0.25));
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
	//return "Server status unavailable"; //If desired, control access based on IP or whatever
	ensure_updater();
}

mapping get_state(string|int group) {return state;}

__async__ void checkdb(string which, System.Timer tm) {
	string db = G->G->DB[which];
	if (!db || (which == "fastdb" && db == G->G->DB->livedb)) {state[which] = ([]); return;}
	await(G->G->DB->pg_connections[db]->conn->query("select 1"));
	state[which] = (["host": (db / ".")[0], "ping": tm->peek()]);
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
		System.Timer tm = System.Timer();
		checkdb("fastdb", tm);
		checkdb("livedb", tm);
	}
	//How many current websocket connections do we have?
	state->socket_count = concurrent_websockets();
	//If there's nobody listening, stop monitoring.
	send_updates_all("");
	if (!sizeof(websocket_groups[""])) G->G->serverstatus_updater = 0;
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
	foreach (lines, string line) {
		array parts = line / " ";
		if (sizeof(parts) < 2) continue;
		//parts[0] is date, parts[1] is time. We really only need the HH:MM from that.
		times += ({parts[1][..<3]});
		float duration = 1.0;
		foreach (parts[2..], string part) {
			sscanf(part, "%[A-Za-z]%d", string pfx, int|float val);
			if (pfx == "D") {if (!val) break; duration = (float)val;} //Duration zero? Ignore the line.
			mapping ld = LOAD_DEFINITIONS[pfx]; if (!ld) continue; //Unknowns do not get displayed
			if (!ld->unscaled) val /= duration; //Some plots are not per-second (most are)
			data[plots[pfx]] += ({val});
		}
	}
	if (!sizeof(data)) return; //Nothing to plot
	array peaks = ({ });
	foreach (data, array plot) peaks += ({max(@plot)});
	string msg = Standards.JSON.encode(([
		"cmd": "graph",
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
	array ws = websocket_groups[""] || ({ });
	if (sizeof(ws)) send_graph(ws);
}

void websocket_cmd_graph(mapping(string:mixed) conn, mapping(string:mixed) msg) {send_graph(({conn->sock}));}

protected void create(string name) {
	::create(name);
	G->G->serverstatus_updatefunc = update;
	remove_call_out(G->G->serverstatus_loadstats);
	G->G->serverstatus_loadstats = call_out(loadstats, LOADSTATS_PERIOD - (time() % LOADSTATS_PERIOD));
}

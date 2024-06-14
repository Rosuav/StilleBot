#charset utf-8
inherit http_websocket;

constant markdown = #"# StilleBot server status

[Mini-view](#mini)

<p id=content></p>

<style>
.percent {
	width: 2em;
	display: inline-block;
}
.percent::after {
	content: \"%\";
}
</style>
";
mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
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

mapping state = ([]);
mapping get_state(string|int group) {return state;}

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
	//If there's nobody listening, stop monitoring.
	send_updates_all("");
	if (!sizeof(websocket_groups[""])) G->G->serverstatus_updater = 0;
}

protected void create(string name) {
	::create(name);
	G->G->serverstatus_updatefunc = update;
}

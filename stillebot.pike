/* Chat bot for Twitch.tv
See API docs:
https://dev.twitch.tv/docs/api/reference

Requires OAuth authentication, which is by default handled by the GUI.
*/

array(string) bootstrap_files = ({"globals.pike", "pgssl.pike", "database.pike", "poll.pike", "connection.pike", "window.pike", "modules", "modules/http", "zz_local"});
array(string) restricted_update;
mapping G = (["consolecmd": ([]), "dbsettings": ([]), "instance_config": ([])]);

void console(object stdin, string buf) {
	while (has_value(buf, "\n")) {
		sscanf(buf, "%s\n%s", string line, buf);
		if (line == "update") bootstrap_all();
		else if (function f = G->consolecmd[line]) f(line); //TODO: Allow word splitting, look up based on first word, provide others
	}
	if (buf == "update") bootstrap_all(); //TODO: Dedup with the above
	else if (function f = G->consolecmd[buf]) f(buf);
}

void report(strict_sprintf_format format, sprintf_args ... args) {
	string msg = sprintf(format, @args);
	werror(msg);
	if (object adm = G->websocket_types->?admin) adm->report(msg);
}

class CompilerErrors {
	int(1bit) reported;
	void compile_error(string filename, int line, string msg) {
		reported = 1;
		werror("\e[1;31m%s:%d\e[0m: %s\n", filename, line, msg);
		if (object adm = G->websocket_types->?admin) adm->report(sprintf("%s:%d: %s\n", filename, line, msg), "error");
	}
	void compile_warning(string filename, int line, string msg) {
		reported = 1;
		werror("\e[1;33m%s:%d\e[0m: %s\n", filename, line, msg);
		if (object adm = G->websocket_types->?admin) adm->report(sprintf("%s:%d: %s\n", filename, line, msg), "warning");
	}
}

object bootstrap(string c)
{
	sscanf(explode_path(c)[-1], "%s.pike", string name);
	program|object compiled;
	object handler = CompilerErrors();
	mixed ex = catch {compiled = compile_file(c, handler);};
	if (handler->reported) return 0; //ANY error or warning, fail the build.
	if (ex) {report("Exception in compile!\n%s\n", ex->describe()); return 0;} //Compilation exceptions indicate abnormal failures eg unable to read the file.
	if (!compiled) report("Compilation failed for "+c+"\n"); //And bizarre failures that report nothing but fail to result in a working program should be reported too.
	if (mixed ex = catch {compiled = compiled(name);}) {G->warnings++; report(describe_backtrace(ex)+"\n");}
	report("Bootstrapped "+c+"\n");
	return compiled;
}

int bootstrap_all()
{
	if (restricted_update) bootstrap_files = restricted_update;
	else {
		object main = bootstrap(__FILE__);
		if (!main || !main->bootstrap_files) {report("UNABLE TO RESET ALL\n"); return 1;}
		bootstrap_files = main->bootstrap_files;
	}
	int err = 0;
	foreach (bootstrap_files, string fn)
		if (file_stat(fn)->isdir)
		{
			foreach (sort(get_dir(fn)), string f)
				if (has_suffix(f, ".pike")) err += !bootstrap(fn + "/" + f);
		}
		else err += !bootstrap(fn);
	return err;
}

class Hilfe {
	inherit Tools.Hilfe.StdinHilfe;
	protected void create() {
		function orig_reswrite = reswrite;
		reswrite = lambda(function w, string sres, int num, mixed res) {
			if (objectp(res) && res->then) res->then() {orig_reswrite(w, sprintf("%O", __ARGS__[0]), num, __ARGS__[0]);};
			else orig_reswrite(w, sres, num, res);
		};
		G->Hilfe = this;
		//The superclass won't return till the user is done.
		::create(({"start backend",
			"mixed _ignore = G->bootstrap(\"globals.pike\");",
			"mixed _ignore = G->bootstrap(\"pgssl.pike\");",
			"mixed _ignore = G->bootstrap(\"database.pike\");",
			"object poll = G->bootstrap(\"poll.pike\"); function req = poll->twitch_api_request;",
		}));
	}
}

int|Concurrent.Future main(int argc,array(string) argv) {
	add_constant("G", this);
	G->args = Arg.parse(G->argv = argv); //Note that G->G->argv is deprecated; use G->G->args instead.
	if (G->args->i) {
		add_constant("INTERACTIVE", 1);
		Hilfe();
		return 0;
	}
	foreach ("test dbupdate lookup script help" / " ", string cmd) if (G->args[cmd]) G->args->exec = cmd; //"--test" is a synonym for "--exec=test"
	if (string fn = G->args->exec) {
		add_constant("INTERACTIVE", 1);
		restricted_update = ({"globals.pike", "pgssl.pike", "database.pike", "poll.pike", "utils.pike"});
		bootstrap_all();
		if (fn == 1)
			if (sizeof(G->args[Arg.REST])) [fn, G->args[Arg.REST]] = Array.shift(G->args[Arg.REST]);
			else fn = "help";
		return (G->utils[replace(fn, "-", "_")] || G->utils->help)();
	}
	if (G->args->headless) {
		werror("Running bot in headless mode - GUI facilities disabled.\n");
		add_constant("HEADLESS", 1);
		signal(1) {call_out(bootstrap_all, 0);};
	}
	bootstrap_all();
	foreach ("spawn_task send_message window" / " ", string vital)
		if (!all_constants()[vital])
			exit(1, "Vital core files failed to compile, cannot continue [missing %O].\n", vital);
	Stdio.stdin->set_read_callback(console);
	return -1;
}

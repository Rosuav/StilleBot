/* Chat bot for Twitch.tv
See API docs:
https://dev.twitch.tv/docs/api/reference

Requires OAuth authentication, which is by default handled by the GUI.
*/

array(string) bootstrap_files = ({"persist.pike", "globals.pike", "database.pike", "poll.pike", "connection.pike", "window.pike", "modules", "modules/http", "zz_local"});
array(string) restricted_update;
mapping G = (["consolecmd": ([]), "dbsettings": ([])]);

void console(object stdin, string buf) {
	while (has_value(buf, "\n")) {
		sscanf(buf, "%s\n%s", string line, buf);
		if (line == "update") bootstrap_all();
		else if (function f = G->consolecmd[line]) f(line); //TODO: Allow word splitting, look up based on first word, provide others
	}
	if (buf == "update") bootstrap_all(); //TODO: Dedup with the above
	else if (function f = G->consolecmd[buf]) f(buf);
}

object bootstrap(string c)
{
	sscanf(explode_path(c)[-1], "%s.pike", string name);
	program|object compiled;
	mixed ex = catch {compiled = compile_file(c);};
	if (ex) {werror("Exception in compile!\n"); werror(ex->describe()+"\n"); return 0;}
	if (!compiled) werror("Compilation failed for "+c+"\n");
	if (mixed ex = catch {compiled = compiled(name);}) {G->warnings++; werror(describe_backtrace(ex)+"\n");}
	werror("Bootstrapped "+c+"\n");
	return compiled;
}

int bootstrap_all()
{
	if (restricted_update) bootstrap_files = restricted_update;
	else {
		object main = bootstrap(__FILE__);
		if (!main || !main->bootstrap_files) {werror("UNABLE TO RESET ALL\n"); return 1;}
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
			mixed spawn_task = all_constants()["spawn_task"];
			if (spawn_task) spawn_task(res) {orig_reswrite(w, sprintf("%O", __ARGS__[0]), num, __ARGS__[0]);};
			else orig_reswrite(w, sres, num, res); //Fallback if we can't spawn tasks yet
		};
		G->Hilfe = this;
		//The superclass won't return till the user is done.
		::create(({"start backend",
			"mixed _ignore = G->bootstrap(\"persist.pike\");",
			"mixed _ignore = G->bootstrap(\"globals.pike\");",
			"mixed _ignore = G->bootstrap(\"database.pike\");",
			"object poll = G->bootstrap(\"poll.pike\"); function req = poll->twitch_api_request;",
		}));
	}
}

int main(int argc,array(string) argv)
{
	add_constant("G", this);
	G->argv = argv;
	if (has_value(argv, "-i")) {
		add_constant("INTERACTIVE", 1);
		Hilfe();
		return 0;
	}
	if (has_value(argv, "--test")) {
		add_constant("INTERACTIVE", 1);
		restricted_update = ({"persist.pike", "globals.pike", "database.pike", "poll.pike", "testing.pike"});
		bootstrap_all();
		Stdio.stdin->set_read_callback(console);
		return -1;
	}
	if (has_value(argv, "--modules")) {
		add_constant("INTERACTIVE", 1);
		add_constant("HEADLESS", 1);
		restricted_update = ({"persist.pike", "globals.pike", "database.pike", "poll.pike", "connection.pike", "window.pike"});
		if (bootstrap_all()) return 1;
		foreach (({"modules", "modules/http", "zz_local"}), string path)
			foreach (sort(get_dir(path)), string f)
				if (has_suffix(f, ".pike") && !bootstrap(path + "/" + f)) {
					Process.create_process(({"SciTE", path + "/" + f}));
					return 1;
				}
		return 0;
	}
	if (has_value(argv, "--dbupdate")) {
		add_constant("INTERACTIVE", 1);
		restricted_update = ({"persist.pike", "globals.pike", "database.pike", "poll.pike"});
		bootstrap_all();
		all_constants()["spawn_task"](G->DB->create_tables_and_stop());
		return -1;
	}
	if (has_value(argv, "--script")) {
		//Test MustardScript parsing and reconstitution.
		add_constant("INTERACTIVE", 1);
		restricted_update = ({"persist.pike", "globals.pike", "database.pike", "poll.pike"});
		bootstrap_all();
		mapping get_channel_config(string|int chan) {error("Channel configuration unavailable.\n");}
		add_constant("get_channel_config", get_channel_config);
		//Rather than actually load up all the builtins, just make sure the names can be validated.
		//List is correct as of 20231210.
		constant builtin_names = ({"chan_share", "chan_giveaway", "shoutout", "cmdmgr", "hypetrain", "chan_mpn", "tz", "chan_alertbox", "raidfinder", "uptime", "renamed", "log", "quote", "nowlive", "calc", "chan_monitors", "chan_errors", "argsplit", "chan_pointsrewards", "chan_labels", "uservars"});
		G->builtins = mkmapping(builtin_names, allocate(sizeof(builtin_names), 1));
		bootstrap("modules/cmdmgr.pike");
		object mustard = bootstrap("modules/mustard.pike");
		argv -= ({"--script"});
		int quiet = 0;
		foreach (argv[1..], string arg) {
			if (arg == "-q") quiet = 1;
			else mustard->run_test(arg, quiet);
		}
		return 0;
	}
	//TODO: Invert this and have --gui to enable the GUI
	if (has_value(argv, "--headless")) {
		werror("Running bot in headless mode - GUI facilities disabled.\n");
		add_constant("HEADLESS", 1);
		signal(1, bootstrap_all);
	}
	//Ensure that G->G->dbsettings can be indexed even before we load from the database
	G->dbsettings = ([]);
	bootstrap_all();
	foreach ("persist_config spawn_task send_message window" / " ", string vital)
		if (!all_constants()[vital])
			exit(1, "Vital core files failed to compile, cannot continue [missing %O].\n", vital);
	#ifndef __NT__
	//Windows has big problems with read callbacks on both stdin and one or more sockets.
	//(I suspect it's because the select() function works on sockets, not file descriptors.)
	//Since this is just for debug/emergency anyway, we just suppress it; worst case, you
	//have to restart StilleBot in a situation where an update would have been sufficient.
	Stdio.stdin->set_read_callback(console);
	#endif
	return -1;
}

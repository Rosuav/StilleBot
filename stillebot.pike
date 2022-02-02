/* Chat bot for Twitch.tv
See API docs:
https://dev.twitch.tv/docs/v5/

Requires OAuth authentication, which is by default handled by the GUI.
*/

array(string) bootstrap_files = ({"persist.pike", "globals.pike", "poll.pike", "connection.pike", "window.pike", "modules", "modules/http", "zz_local"});
mapping G = ([]);

void console(object stdin, string buf)
{
	while (has_value(buf, "\n"))
	{
		sscanf(buf, "%s\n%s", string line, buf);
		if (line == "update") bootstrap_all();
	}
	if (buf == "update") bootstrap_all();
}

object bootstrap(string c)
{
	sscanf(explode_path(c)[-1], "%s.pike", string name);
	program|object compiled;
	mixed ex = catch {compiled = compile_file(c);};
	if (ex) {werror("Exception in compile!\n"); werror(ex->describe()+"\n"); return 0;}
	if (!compiled) werror("Compilation failed for "+c+"\n");
	if (mixed ex = catch {compiled = compiled(name);}) werror(describe_backtrace(ex)+"\n");
	werror("Bootstrapped "+c+"\n");
	return compiled;
}

int bootstrap_all()
{
	object main = bootstrap(__FILE__);
	if (!main || !main->bootstrap_files) {werror("UNABLE TO RESET ALL\n"); return 1;}
	int err = 0;
	foreach (bootstrap_files = main->bootstrap_files, string fn)
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
			"object poll = G->bootstrap(\"poll.pike\"); function req = poll->request;",
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
	bootstrap_all();
	foreach ("persist_config command send_message window" / " ", string vital)
		if (!all_constants()[vital])
			exit(1, "Vital core files failed to compile, cannot continue.\n");
	#ifndef __NT__
	//Windows has big problems with read callbacks on both stdin and one or more sockets.
	//(I suspect it's because the select() function works on sockets, not file descriptors.)
	//Since this is just for debug/emergency anyway, we just suppress it; worst case, you
	//have to restart StilleBot in a situation where an update would have been sufficient.
	Stdio.stdin->set_read_callback(console);
	#endif
	return -1;
}

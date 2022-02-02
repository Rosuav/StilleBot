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

int main(int argc,array(string) argv)
{
	add_constant("G", this);
	G->argv = argv;
	if (has_value(argv, "-i")) {
		add_constant("INTERACTIVE", 1);
		bootstrap("persist.pike");
		bootstrap("globals.pike");
		bootstrap("poll.pike");
		Tools.Hilfe.StdinHilfe(({"start backend"}));
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

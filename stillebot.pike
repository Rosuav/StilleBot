/* Chat bot for Twitch.tv
See API docs:
https://github.com/justintv/Twitch-API/blob/master/IRC.md

To make this work, get yourself an oauth key here:
http://twitchapps.com/tmi/
and change your user and realname accordingly.
*/

array(string) bootstrap_files = ({"persist.pike", "globals.pike", "poll.pike", "connection.pike", "console.pike", "window.pike", "modules"});
mapping G = ([]);
function(string:void) execcommand;

void console(object stdin, string buf)
{
	while (has_value(buf, "\n"))
	{
		sscanf(buf, "%s\n%s", string line, buf);
		execcommand(line);
	}
	if (buf!="") execcommand(buf);
}

object bootstrap(string c)
{
	program|object compiled;
	mixed ex=catch {compiled=compile_file(c);};
	if (ex) {werror("Exception in compile!\n"); werror(ex->describe()+"\n"); return 0;}
	if (!compiled) werror("Compilation failed for "+c+"\n");
	if (mixed ex=catch {compiled = compiled(c);}) werror(describe_backtrace(ex)+"\n");
	werror("Bootstrapped "+c+"\n");
	return compiled;
}

int bootstrap_all()
{
	object main = bootstrap(__FILE__);
	if (!main || !main->bootstrap_files) {werror("UNABLE TO RESET ALL\n"); return 1;}
	int err = 0;
	foreach (bootstrap_files = main->bootstrap_files, string fn)
		if (file_stat(fn)->isdir) foreach (sort(get_dir(fn)), string f) err += !bootstrap(fn+"/"+f);
		else err += !bootstrap(fn);
	return err;
}

int main(int argc,array(string) argv)
{
	add_constant("G", this);
	G->argv = argv;
	bootstrap_all();
	//Compat: Import settings from the old text config
	if (file_stat("twitchbot_config.txt"))
	{
		mapping config = ([]);
		foreach (Stdio.read_file("twitchbot_config.txt")/"\n", string l)
		{
			l = String.trim_all_whites(l); //Trim off carriage returns as needed
			if (l=="" || l[0]=='#') continue;
			sscanf(l, "%s:%s", string key, string val); if (!val) continue;
			config[key] = String.trim_all_whites(val); //Permit (but don't require) a space after the colon
		}
		if (config->pass[0] == '<') m_delete(config, "pass");
		object persist = all_constants()["persist"]; //Since we can't use the constant as such :)
		persist["ircsettings"] = config;
		persist->dosave(); //Save synchronously before destroying the config file
		if (!persist->saving) rm("twitchbot_config.txt");
	}
	Stdio.stdin->set_read_callback(console);
	return -1;
}

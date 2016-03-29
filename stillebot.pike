/* Chat bot for Twitch.tv
See API docs:
https://github.com/justintv/Twitch-API/blob/master/IRC.md

To make this work, get yourself an oauth key here:
http://twitchapps.com/tmi/
and change your user and realname accordingly.
*/

array(string) bootstrap_files = ({"globals.pike", "connection.pike", "console.pike", "poll.pike", "modules"});
mapping G = ([]);
mapping config = ([]);
array(string) channels = ({ });
function(string:void) execcommand;

void console(object stdin, Stdio.Buffer buf)
{
	while (string line=buf->match("%s\n")) //Will usually happen exactly once
		execcommand(line);
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

void bootstrap_all()
{
	object main = bootstrap(__FILE__);
	if (!main || !main->bootstrap_files) {werror("UNABLE TO RESET ALL\n"); return;}
	foreach (bootstrap_files = main->bootstrap_files, string fn)
		if (file_stat(fn)->isdir) foreach (sort(get_dir(fn)), string f) bootstrap(fn+"/"+f);
		else bootstrap(fn);
}

int main(int argc,array(string) argv)
{
	add_constant("G", this);
	if (!file_stat("twitchbot_config.txt"))
	{
		Stdio.write_file("twitchbot_config.txt",#"# twitchbot.pike config file
# Basic names
nick: <bot nickname here>
realname: <bot real name here>
# Get an OAuth2 key here: 
pass: <password>
# List the channels you want to monitor. Only these channels will
# be logged, and commands will be noticed only if they're in one
# of these channels. Any number of channels can be specified.
channels: rosuav ellalune lara_cr cookingfornoobs
");
	}
	foreach (Stdio.read_file("twitchbot_config.txt")/"\n", string l)
	{
		l = String.trim_all_whites(l);
		if (l=="" || l[0]=='#') continue;
		sscanf(l, "%s: %s", string key, string val); if (!val) continue;
		if (key=="channels") channels += "#" + (val/" ")[*];
		else config[key] = val;
	}
	if (config->pass[0] == '<') exit(1, "Edit twitchbot_config.txt to make this bot work!\n");
	bootstrap_all();
	Stdio.stdin->set_buffer_mode(Stdio.Buffer(),0);
	Stdio.stdin->set_read_callback(console);
	if (has_value(argv,"--gui"))
	{
		GTK2.setup_gtk(argv);
		object ef=GTK2.Entry()->set_width_chars(40)->set_activates_default(1);
		object btn=GTK2.Button()->set_size_request(0,0)->set_flags(GTK2.CAN_DEFAULT);
		btn->signal_connect("clicked",lambda() {execcommand(ef->get_text()); ef->set_text("");});
		GTK2.Window(0)->add(GTK2.Vbox(0,0)->add(ef)->pack_end(btn,0,0,0))->set_title("Twitch Bot")->show_all();
		btn->grab_default();
	}
	return -1;
}

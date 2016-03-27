/* Chat bot for Twitch.tv
See API docs:
https://github.com/justintv/Twitch-API/blob/master/IRC.md

To make this work, get yourself an oauth key here:
http://twitchapps.com/tmi/
and change your user and realname accordingly.
*/

mapping G = ([]);
mapping config = ([]);
array(string) channels = ({ });

mapping timezones;

string timezone_info(string tz)
{
	if (!tz || tz=="") return "Regions are: " + sort(indices(timezones))*", ";
	mapping|string region = timezones;
	foreach (lower_case(tz)/"/", string part) if (!mappingp(region=region[part])) break;
	if (undefinedp(region))
		return "Unknown region "+tz+" - use '!tz' to list";
	if (mappingp(region))
		return "Locations in region "+tz+": "+sort(indices(region))*", ";
	if (catch {return region+" - "+Calendar.Gregorian.Second()->set_timezone(region)->format_time();})
		return "Unable to figure out the time in that location, sorry.";
}

void console(object stdin, Stdio.Buffer buf)
{
	while (string line=buf->match("%s\n")) //Will usually happen exactly once, but if you type before lastchan is set, it might loop
		execcommand(line);
}

void execcommand(string line)
{
	if (sscanf(line, "/join %s", string chan))
	{
		write("%%% Joining #"+chan+"\n");
		G->irc->join_channel("#"+chan);
		channels += ({"#"+chan});
	}
	else if (sscanf(line, "/part %s", string chan))
	{
		write("%%% Parting #"+chan+"\n");
		G->irc->part_channel("#"+chan);
		channels -= ({"#"+chan});
	}
}

void bootstrap(string c)
{
	program compiled;
	mixed ex=catch {compiled=compile_file(c);};
	if (ex) {werror("Exception in compile!\n"); werror(ex->describe()+"\n"); return;}
	if (!compiled) werror("Compilation failed for "+c+"\n");
	if (mixed ex=catch {compiled(c);}) werror(describe_backtrace(ex)+"\n");
	werror("Bootstrapped "+c+"\n");
}

int main(int argc,array(string) argv)
{
	add_constant("G", this);
	timezones = ([]);
	foreach (sort(Calendar.TZnames.zonenames()), string zone)
	{
		array(string) parts = lower_case(zone)/"/";
		mapping tz = timezones;
		foreach (parts[..<1], string region)
			if (!tz[region]) tz = tz[region] = ([]);
			else tz = tz[region];
		tz[parts[-1]] = zone;
	}
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
	if (config->pass[0] == '<')
	{
		write("Edit twitchbot_config.txt to make this bot work!\n");
		return 0;
	}
	bootstrap("connection.pike");
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

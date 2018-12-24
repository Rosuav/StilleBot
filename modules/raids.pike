inherit command;
constant require_allcmds = 1;
constant hidden_command = 1;
inherit menu_item;
constant menu_label = "Recent raids";
constant active_channels = ({"!whisper"});

mapping(string:array(string)) get_raids()
{
	mapping(string:array(string)) ret = ([]);
	foreach (indices(persist["channels"] || ({ })), string chan)
		if (G->G->stream_online_since[chan])
			ret[chan] = ({ });
	foreach (Stdio.read_file("outgoing_raids.log") / "\n", string line)
	{
		sscanf(line, "[%s] %s => %s", string when, string who, string where);
		if (!when || !who || !where) continue;
		if (!ret[who]) continue; //Channel isn't online
		ret[who] = ret[who][<8..] + ({sprintf("[%s] Raided %s", when, where)});
	}
	return ret;
}

void menu_clicked()
{
	foreach (get_raids(); string chan; array(string) destinations)
	{
		write("Recent raids from %s:\n", chan);
		foreach (destinations, string dest)
			write("\t%s\n", dest);
	}
	if (string winid = getenv("WINDOWID")) //Copied from window.pike
		catch (Process.create_process(({"wmctrl", "-ia", winid}))->wait());
}

echoable_message process(object channel, object person, string param)
{
	//Special permissions check. If you are a mod in the bot's own channel
	//(the bot must be active in that channel for that to have meaning), you
	//may look up raids.
	if (!persist["ircsettings"]) return 0; //Bot not configured (but how are you triggering the command then??)
	string bot = persist["ircsettings"]->nick; if (!bot) return 0; //Bot not authenticated (ditto!)
	object botchan = G->G->irc->channels["#" + bot];
	if (!botchan) return 0; //Bot doesn't manage his own channel. Mod status is not granted.
	if (!botchan->mods[person->user]) return 0; //You're not a mod in the bot's channel. Permission denied.
	array response = ({ });
	foreach (get_raids(); string chan; array(string) destinations)
	{
		string msg = "Channel " + chan + ": ";
		foreach (destinations, string dest)
			msg += (dest / " Raided ")[1] + ", ";
		response += ({(["message": msg, "dest": "/w $$"])});
	}
	return response;
}

void create(string name) {::create(name);}

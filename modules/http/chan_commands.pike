inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

constant MAX_RESPONSES = 10; //Ridiculously large? Probably.

constant TEMPLATES = ({
	"!discord | Join my Discord server: https://discord.gg/YOUR_URL_HERE",
	"!shop | stephe21LOOT Get some phat lewt at https://www.redbubble.com/people/YOUR_REDBUBBLE_NAME/portfolio iimdprLoot",
	"!twitter | Follow my Twitter for updates, notifications, and other whatever-it-is-I-post: https://twitter.com/YOUR_TWITTER_NAME",

	"!love | rosuavLove maayaHeart fxnLove devicatLOVE devicatHUG laracrG noobsLove stephe21Heart ladydr1Teamluv ladydr1HoG ladydr1Rainbow",
	"!hype | maayaHype devicatHYPU noobsHype maayaHype devicatHYPU noobsHype maayaHype devicatHYPU noobsHype",
	"!hug | /me devicatHUG $$ warmly hugs %s maayaHug",
	"!lurk | $$ drops into the realm of lurkdom devicatLURK",
	"!unlurk | $$ returns from the realm of lurk devicatLURK",
	"!raid | Let's go raiding! Copy and paste this raid call: \"/me twitchRaid YOUR RAID CALL HERE twitchRaid \" and be ready when I host our target!",
});

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string c = req->misc->channel->name;
	array commands = ({ }), order = ({ }), messages = ({ });
	object user = user_text();
	int changes_made = 0;
	if (req->misc->is_mod && req->request_type == "POST")
	{
		string name = String.trim(lower_case(req->variables->newcmd_name || "") - "!");
		string resp = String.trim(req->variables->newcmd_resp || "");
		if (name != "" && resp != "")
		{
			changes_made = 1;
			G->G->echocommands[name + c] = resp;
			messages += ({"* Created !" + name});
		}
	}
	foreach (G->G->echocommands; string cmd; echoable_message response) if (!has_prefix(cmd, "!") && has_suffix(cmd, c))
	{
		cmd -= c;
		if (req->misc->is_mod)
		{
			//NOTE: If you attempt to save an edit for something that's been deleted
			//elsewhere, this will quietly ignore it. We have no way of knowing that
			//you changed anything, so it could just as easily be an untouched entry
			//which we should definitely not resurrect. Slightly unideal in a corner
			//case, but the wart is worth it for the simplicity of not having double
			//the form fields just for the sake of detecting differences.
			if (req->request_type == "POST")
			{
				response = Array.arrayify(response) + ({ });
				int edited = 0;
				for (int i = 0; i < MAX_RESPONSES; ++i)
				{
					string resp = req->variables[sprintf("%s!%d", cmd, i)];
					if (!resp) break;
					//TODO: Allow response flags to be set (making the resp into a
					//mapping). As of 20190205, the only flag that would be useful
					//is 'dest', which could be set to a variety of handy values -
					//"/w $$" to whisper to the person who sent the command, or an
					//explicit "/w somename" to send the whisper elsewhere. One
					//command might need to have multiple distinct responses, eg a
					//quick "got it" to the channel, and a more detailed whisper to
					//the person who's managing this (maybe for entering a contest).
					if (i >= sizeof(response)) response += ({""});
					if (respstr(response[i]) != resp)
					{
						edited = 1;
						response[i] = resp; //NOTE: This will currently lose any mapping flags.
					}
				}
				response -= ({""});
				if (edited)
				{
					changes_made = 1;
					if (!sizeof(response))
					{
						messages += ({"* Deleted !" + cmd});
						m_delete(G->G->echocommands, cmd + c);
						continue; //Don't put anything into the commands array
					}
					if (sizeof(response) == 1) response = response[0];
					messages += ({"* Updated !" + cmd});
					G->G->echocommands[cmd + c] = response;
				}
			}
			string usercmd = Parser.encode_html_entities(cmd);
			string inputs = "";
			foreach (Array.arrayify(response); int i; string|mapping resp)
				inputs += sprintf("<br><input name=\"%s!%d\" value=\"%s\" size=200>",
					usercmd, i, Parser.encode_html_entities(respstr(resp)));
			commands += ({sprintf("<code>!%s</code> | %s<button type=button name=\"%[0]s!%d\" title=\"Add another line\">+</button>",
				usercmd, inputs[4..], arrayp(response) ? sizeof(response) : 1)});
		}
		else
		{
			if (arrayp(response)) response = user(respstr(response[*])[*]) * "</code><br><code>";
			else response = user(respstr(response));
			commands += ({sprintf("<code>!%s</code> | <code>%s</code>", user(cmd), response)});
		}
		order += ({cmd});
	}
	sort(order, commands);
	if (!sizeof(commands)) commands = ({"(none) |"});
	if (req->misc->is_mod) commands += ({"Add: <input name=newcmd_name size=10 placeholder=\"!hype\"> | <input name=newcmd_resp size=200>"});
	if (changes_made)
	{
		//Once again, TODO: Dedup. Or migrate these into persist_config??
		string json = Standards.JSON.encode(G->G->echocommands, Standards.JSON.HUMAN_READABLE|Standards.JSON.PIKE_CANONICAL);
		Stdio.write_file("twitchbot_commands.json", string_to_utf8(json));
	}
	return render_template("chan_commands.md", ([
		"user text": user,
		"channel": req->misc->channel_name, "commands": commands * "\n",
		"messages": messages * "\n",
		"templates": TEMPLATES * "\n",
		"save_or_login": req->misc->is_mod ?
			"<p><a href=\"#examples\" id=examples>Example and template commands</a></p><input type=submit value=\"Save all\">" :
			"<a href=\"/twitchlogin?next=" + req->not_query + "\">Mods, login to make changes</a>",
	]));
}

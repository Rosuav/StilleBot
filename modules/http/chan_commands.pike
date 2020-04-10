inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

constant MAX_RESPONSES = 10; //Ridiculously large? Probably.

constant TEMPLATES = ({
	"!discord | Join my Discord server: https://discord.gg/YOUR_URL_HERE",
	"!shop | stephe21LOOT Get some phat lewt at https://www.redbubble.com/people/YOUR_REDBUBBLE_NAME/portfolio iimdprLoot",
	"!twitter | Follow my Twitter for updates, notifications, and other whatever-it-is-I-post: https://twitter.com/YOUR_TWITTER_NAME",
	"!love | rosuavLove maayaHeart fxnLove devicatLOVE devicatHUG noobsLove stephe21Heart beauatLOVE kattvHeart",
	"!hype | maayaHype devicatHYPU noobsHype maayaHype devicatHYPU noobsHype maayaHype devicatHYPU noobsHype",
	"!hug | /me devicatHUG $$ warmly hugs %s maayaHug",
	"!loot | HypeChest RPGPhatLoot Loot ALL THE THINGS!! stephe21LOOT iimdprLoot",
	"!lurk | $$ drops into the realm of lurkdom devicatLURK",
	"!unlurk | $$ returns from the realm of lurk devicatLURK",
	"!raid | Let's go raiding! Copy and paste this raid call and be ready when I host our target! >>> /me twitchRaid YOUR RAID CALL HERE twitchRaid",
	"!save | rosuavSave How long since you last saved? rosuavSave",
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
			//TODO: If this collides with an existing one, error out or something
			//Currently it's being overwritten by the old one.
			changes_made = 1;
			G->G->echocommands[name + c] = resp;
			messages += ({"* Created !" + name});
		}
	}
	foreach (G->G->echocommands; string cmd; echoable_message response) if (!has_prefix(cmd, "!") && has_suffix(cmd, c))
	{
		cmd -= c;
		mapping flags = ([]);
		if (mappingp(response) && arrayp(response->message))
		{
			flags = response | ([]);
			response = flags->message;
		}
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

				//Update the flags (be sure to m_delete any that state defaults)
				string resp = req->variables[cmd + "!mode"];
				if (resp == "random" && flags->mode != "random") {flags->mode = "random"; edited = 1;}
				else if (resp == "sequential" && flags->mode) {m_delete(flags, "mode"); edited = 1;}

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
					if (sizeof(indices(flags) - ({"message"})))
						G->G->echocommands[cmd + c] = flags | (["message": G->G->echocommands[cmd + c]]);
				}
			}
			string usercmd = Parser.encode_html_entities(cmd);
			string inputs = "";
			foreach (Array.arrayify(response); int i; string|mapping resp)
			{
				inputs += sprintf("<br><input name=\"%s!%d\" value=\"%s\" class=widetext>",
					usercmd, i, Parser.encode_html_entities(respstr(resp)));
			}
			string mode = "";
			if (arrayp(response) && sizeof(response) > 1)
				mode = sprintf("<select name=\"%s!mode\">"
						"<option value=sequential>Sequential</option>"
						"<option value=random%s>Random</option></select><br>",
					usercmd, flags->mode == "random" ? " selected" : "");
			commands += ({sprintf("<code>!%s</code> | %s | %s"
					//"<button type=button class=options data-cmd=\"%[0]s\" title=\"Set command options\">\u2699</button>"
					"<button type=button class=addline data-cmd=\"%[0]s\" data-idx=%d title=\"Add another line\">+</button>",
				usercmd, inputs[4..], mode, arrayp(response) ? sizeof(response) : 1)});
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
	if (req->misc->is_mod) commands += ({"Add: <input name=newcmd_name size=10 placeholder=\"!hype\"> | <input name=newcmd_resp class=widetext>"});
	if (changes_made) make_echocommand(0, 0); //Trigger a save
	return render_template("chan_commands.md", ([
		"user text": user,
		"channel": req->misc->channel_name, "commands": commands * "\n",
		"messages": messages * "\n",
		"templates": TEMPLATES * "\n",
		"save_or_login": req->misc->login_link || "<p><a href=\"#examples\" id=examples>Example and template commands</a></p><input type=submit value=\"Save all\">",
	]));
}

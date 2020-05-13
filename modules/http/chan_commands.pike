inherit http_endpoint;

//Simplified stringification. Good for comparisons (ignoring flags), simple text output, etc.
string respstr(echoable_message resp)
{
	if (stringp(resp)) return resp;
	if (arrayp(resp)) return respstr(resp[*]) * "\n";
	return respstr(resp->message);
}

constant MAX_RESPONSES = 10; //Ridiculously large? Probably.

constant TEMPLATES = ({
	"!discord | Join my Discord server: https://discord.gg/YOUR_URL_HERE",
	"!shop | stephe21LOOT Get some phat lewt at https://www.redbubble.com/people/YOUR_REDBUBBLE_NAME/portfolio iimdprLoot",
	"!twitter | Follow my Twitter for updates, notifications, and other whatever-it-is-I-post: https://twitter.com/YOUR_TWITTER_NAME",
	"!love | rosuavLove maayaHeart fxnLove devicatLove devicatHug noobsLove stephe21Heart beauatLOVE kattvHeart",
	"!hype | maayaHype devicatHypu noobsHype maayaHype devicatHypu noobsHype maayaHype devicatHypu noobsHype",
	"!hug | /me devicatHug $$ warmly hugs %s maayaHug",
	"!loot | HypeChest RPGPhatLoot Loot ALL THE THINGS!! stephe21LOOT iimdprLoot",
	"!lurk | $$ drops into the realm of lurkdom devicatLurk",
	"!unlurk | $$ returns from the realm of lurk devicatLurk",
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
			if (!G->G->echocommands[name + c])
			{
				changes_made = 1;
				G->G->echocommands[name + c] = resp;
				messages += ({"* Created !" + name});
			}
			else messages += ({"* Did not create !" + name + " - already exists"});
		}
	}
	mapping cmd_raw = ([]); //Only used if not is_mod
	foreach (G->G->echocommands; string cmd; echoable_message response) if (!has_prefix(cmd, "!") && has_suffix(cmd, c))
	{
		cmd -= c;
		mapping flags = ([]);
		cmd_raw[cmd] = mappingp(response) ? response : (["message": response]); //To save JS some type-checking trouble
		while (mappingp(response))
		{
			flags |= response ^ (["message": 1]);
			response = response->message;
		}
		if (req->misc->is_mod)
		{
			if (!arrayp(response)) response = ({response});
			//NOTE: If you attempt to save an edit for something that's been deleted
			//elsewhere, this will quietly ignore it. We have no way of knowing that
			//you changed anything, so it could just as easily be an untouched entry
			//which we should definitely not resurrect. Slightly unideal in a corner
			//case, but the wart is worth it for the simplicity of not having double
			//the form fields just for the sake of detecting differences.
			if (req->request_type == "POST")
			{
				response += ({ }); //anti-mutation for safety/simplicity
				int edited = 0;
				for (int i = 0; i < MAX_RESPONSES; ++i)
				{
					string resp = req->variables[sprintf("%s!%d", cmd, i)];
					if (!resp) break;
					if (i >= sizeof(response)) response += ({""});
					//Note that this won't correctly handle arrays-in-arrays, but
					//if you didn't edit it (it'll have had a newline), you should be
					//fine. Use the popup dialog to edit unusual commands like that.
					//This also loses any subresponse flags.
					if (respstr(response[i]) != resp)
					{
						edited = 1;
						if (has_value(resp, '\n')) response[i] = resp / "\n";
						else response[i] = resp;
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
					if (sizeof(flags)) G->G->echocommands[cmd + c] = flags | (["message": response]);
					else G->G->echocommands[cmd + c] = response;
				}
			}
			string usercmd = Parser.encode_html_entities(cmd);
			string inputs = "";
			foreach (Array.arrayify(response); int i; string|mapping resp)
			{
				inputs += sprintf("<br><input name=\"%s!%d\" value=\"%s\" class=widetext>",
					usercmd, i, Parser.encode_html_entities(respstr(resp)));
			}
			commands += ({sprintf("<code>!%s</code> | %s | "
					"<button type=button class=options data-cmd=\"%[0]s\" title=\"Set command options\">\u2699</button>"
					"<button type=button class=addline data-cmd=\"%[0]s\" data-idx=%d title=\"Add another line\">+</button>",
				usercmd, inputs[4..], arrayp(response) ? sizeof(response) : 1)});
		}
		else
		{
			if (flags->visibility == "hidden") continue; //Hide hidden messages, including from the order array below
			//Recursively convert a response into HTML. Ignores submessage flags.
			string htmlify(echoable_message response) {
				if (stringp(response)) return user(response);
				if (arrayp(response)) return htmlify(response[*]) * "</code><br><code>";
				if (mappingp(response)) return htmlify(response->message);
			}
			commands += ({sprintf("<code>!%s</code> | <code>%s</code> | %s",
				user(cmd), htmlify(response),
				//TODO: Show if a response would be whispered?
				flags->access == "mod" ? "Mod-only" : "",
			)});
		}
		order += ({cmd});
	}
	sort(order, commands);
	if (!sizeof(commands)) commands = ({"(none) |"});
	//TODO: Put an addline button on this too
	if (req->misc->is_mod) commands += ({"Add: <input name=newcmd_name size=10 placeholder=\"!hype\"> | <input name=newcmd_resp class=widetext>"});
	if (changes_made) make_echocommand(0, 0); //Trigger a save
	return render_template("chan_commands.md", ([
		"user text": user,
		"channel": req->misc->channel_name, "commands": commands * "\n",
		"messages": messages * "\n",
		"templates": TEMPLATES * "\n",
		"save_or_login": req->misc->login_link || ("<p><a href=\"#examples\" id=examples>Example and template commands</a></p>"
			"<input type=submit value=\"Save all\">"
			"\n<script>const commands = " + Standards.JSON.encode(cmd_raw) + "</script>" //newline forces it to be treated as HTML not text
			"<script type=module src=\"/static/commands.js\"></script>"
		),
	]));
}

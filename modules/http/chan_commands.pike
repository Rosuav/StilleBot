inherit http_endpoint;

//Simplistic stringification for read-only display.
string respstr(echoable_message resp)
{
	if (stringp(resp)) return resp;
	if (arrayp(resp)) return respstr(resp[*]) * "<br>";
	return respstr(resp->message);
}

constant MAX_RESPONSES = 10; //Max pieces of text per command, for simple view. Can be exceeded by advanced editing.

constant TEMPLATES = ({
	"!discord | Join my Discord server: https://discord.gg/YOUR_URL_HERE",
	"!shop | stephe21LOOT Get some phat lewt at https://www.redbubble.com/people/YOUR_REDBUBBLE_NAME/portfolio iimdprLoot",
	"!twitter | Follow my Twitter for updates, notifications, and other whatever-it-is-I-post: https://twitter.com/YOUR_TWITTER_NAME",
	"!love | rosuavLove maayaHeart fxnLove devicatLove devicatHug noobsLove stephe21Heart beauatLOVE hypeHeart",
	"!hype | maayaHype silent5HYPU noobsHype maayaHype silent5HYPU noobsHype maayaHype silent5HYPU noobsHype",
	"!hug | /me devicatHug $$ warmly hugs %s maayaHug",
	"!loot | HypeChest RPGPhatLoot Loot ALL THE THINGS!! stephe21LOOT iimdprLoot",
	"!lurk | $$ drops into the realm of lurkdom devicatLurk",
	"!unlurk | $$ returns from the realm of lurk devicatLurk",
	"!raid | Let's go raiding! Copy and paste this raid call and be ready when I host our target! >>> /me twitchRaid YOUR RAID CALL HERE twitchRaid",
	"!save | rosuavSave How long since you last saved? devicatSave",
	"!winner | Congratulations, %s! You have won The Thing, see this link for details...",
	"!join | Join us in Jackbox games! Type !play and go to https://sikorsky.rosuav.com/channels/##CHANNEL##/private",
	"!play | (Private message) We're over here: https://jackbox.tv/#ABCD",
	"!hydrate | Drink water! Do it! And then do it again in half an hour.",
});
//If a command is listed here, its description above is just the human-readable version, and
//this is what will actually be used for the command. Selecting such a template will also
//use the Advanced view in the front end.
constant COMPLEX_TEMPLATES = ([
	"!winner": ({
		//TODO: Populate the actual channel name in the template
		"Congratulations, %s! You have won The Thing! Details are waiting for you over here: https://sikorsky.rosuav.com/channels/##CHANNEL##/private",
		(["message": "Your secret code is 0TB54-I3YKG-CNDKV and you can go to https://some.url.example/look-here to redeem it!", "dest": "/web %s"]),
	}),
	"!play": (["message": "We're over here: https://jackbox.tv/#ABCD", "dest": "/web $$"]),
	"!hydrate": ({
		"devicatSip Don't forget to drink water! devicatSip",
		(["message": "devicatSip Drink more water! devicatSip", "delay": 1800]),
	}),
]);

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string c = req->misc->channel->name;
	array commands = ({ }), order = ({ }), messages = ({ });
	object user = user_text();
	int changes_made = 0;
	if (req->misc->is_mod && req->request_type == "POST")
	{
		string name = String.trim(lower_case(req->variables->newcmd_name || "") - "!" - "#");
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
		//A simple command is:
		//1) A string
		//2) A mapping whose response is a string
		//3) A mapping whose response is an array of strings
		//4) An array of strings
		//Anything else is a non-simple command and cannot be edited with this method - it
		//MUST use advanced editing and the JS popup.
		cmd_raw[cmd] = response = mappingp(response) ? response : (["message": response]); //To save JS some type-checking trouble
		//Now the only possible simple commands are #2 and #3.
		array(string) simple_messages;
		if (arrayp(response->message) && Array.all(response->message, stringp) && !response->conditional) simple_messages = response->message;
		else if (stringp(response->message) && !response->conditional) simple_messages = ({response->message});
		if (req->misc->is_mod)
		{
			//NOTE: If you attempt to save an edit for something that's been deleted
			//elsewhere, this will quietly ignore it. We have no way of knowing that
			//you changed anything, so it could just as easily be an untouched entry
			//which we should definitely not resurrect. Slightly unideal in a corner
			//case, but the wart is worth it for the simplicity of not having double
			//the form fields just for the sake of detecting differences. Note also:
			//If a command didn't exist when the page was loaded, we *must not* risk
			//deleting it, even if the user may have wanted to (because it is highly
			//unlikely, let's be honest). So if there are no form variables starting
			//with this command name, assume the user didn't want to edit it at all.
			if (req->request_type == "POST" && simple_messages)
			{
				array|mapping|string newresp = UNDEFINED;
				for (int i = 0; i < MAX_RESPONSES; ++i)
				{
					string resp = req->variables[sprintf("%s!%d", cmd, i)];
					if (!resp) break;
					resp = String.trim(resp);
					newresp += resp / "\n"; //If you paste in a newline, make multiple responses.
				}
				if (newresp) //See above note re new and deleted commands.
				{
					newresp -= ({""});
					if (newresp * "\n" != simple_messages * "\n")
					{
						changes_made = 1;
						if (!sizeof(newresp))
						{
							messages += ({"* Deleted !" + cmd});
							m_delete(G->G->echocommands, cmd + c);
							continue; //Don't put anything into the commands array
						}
						simple_messages = newresp; //Keep the arrayified version for the below
						if (sizeof(newresp) == 1) newresp = newresp[0];
						if (sizeof(response) > 1) newresp = response | (["message": newresp]); //Hang onto any top-level flags
						messages += ({"* Updated !" + cmd});
						G->G->echocommands[cmd + c] = response = newresp;
					}	
				}
			}
			string usercmd = Parser.encode_html_entities(cmd);
			string inputs = "";
			if (simple_messages) foreach (simple_messages; int i; string resp)
			{
				inputs += sprintf("<br><input name=\"%s!%d\" value=\"%s\" class=widetext>",
					usercmd, i, Parser.encode_html_entities(resp));
			}
			else inputs = "<br><code>" + respstr(response) + "</code>";
			commands += ({sprintf("<code>!%s</code> | %s | "
					"<button type=button class=advview data-cmd=\"%[0]s\" title=\"Advanced\">\u2699</button>"
					+ (simple_messages ? "<button type=button class=addline data-cmd=\"%[0]s\" data-idx=%d title=\"Add another line\">+</button>" : ""), 
				usercmd, inputs[4..], arrayp(response) ? sizeof(response) : 1)});
		}
		else
		{
			if (response->visibility == "hidden") continue; //Hide hidden messages, including from the order array below
			//Recursively convert a response into HTML. Ignores submessage flags.
			//TODO: Respect *some* flags, even if only to suppress a subbranch.
			string htmlify(echoable_message response) {
				if (stringp(response)) return user(response);
				if (arrayp(response)) return htmlify(response[*]) * "</code><br><code>";
				if (mappingp(response)) return htmlify(response->message);
			}
			commands += ({sprintf("<code>!%s</code> | <code>%s</code> | %s",
				user(cmd), htmlify(response),
				//TODO: Show if a response would be whispered?
				(["mod": "Mod-only", "none": "Disabled"])[response->access] || "",
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
		"commands": commands * "\n",
		"messages": messages * "\n",
		"templates": TEMPLATES * "\n",
		"save_or_login": ("<p><a href=\"#examples\" id=examples>Example and template commands</a></p>"
			"<input type=submit value=\"Save all\">"
			"\n<script>const commands = " + Standards.JSON.encode(cmd_raw) + //newline forces it to be treated as HTML not text
			", complex_templates = " + Standards.JSON.encode(COMPLEX_TEMPLATES) + "</script>"
			"<script type=module src=\"" + G->G->template_defaults["static"]("commands.js") + "\"></script>"
		),
	]) | req->misc->chaninfo);
}

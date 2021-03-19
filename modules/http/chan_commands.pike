inherit http_endpoint;
inherit websocket_handler;

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
	"!hug": ([
		"conditional": "string", "expr1": "%s",
		"message": "/me devicatHug $$ warmly hugs everyone maayaHug",
		"otherwise": "/me devicatHug $$ warmly hugs %s maayaHug",
	]),
]);

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (req->misc->is_mod) {
		return render_template("chan_commands.md", ([
			"vars": (["ws_type": "chan_commands", "ws_group": req->misc->channel->name, "complex_templates": COMPLEX_TEMPLATES]),
			"templates": TEMPLATES * "\n",
			"save_or_login": ("<p><a href=\"#examples\" id=examples>Example and template commands</a></p>"
				"<input type=submit value=\"Save all\">"
			),
		]) | req->misc->chaninfo);
	}
	string c = req->misc->channel->name;
	array commands = ({ }), order = ({ });
	object user = user_text();
	foreach (G->G->echocommands; string cmd; echoable_message response) if (!has_prefix(cmd, "!") && has_suffix(cmd, c))
	{
		if (mappingp(response) && response->visibility == "hidden") continue;
		//Recursively convert a response into HTML. Ignores submessage flags.
		//TODO: Respect *some* flags, even if only to suppress a subbranch.
		string htmlify(echoable_message response) {
			if (stringp(response)) return user(response);
			if (arrayp(response)) return htmlify(response[*]) * "</code><br><code>";
			if (mappingp(response)) return htmlify(response->message);
		}
		commands += ({sprintf("<code>!%s</code> | <code>%s</code> | %s",
			user(cmd - c), htmlify(response),
			//TODO: Show if a response would be whispered?
			(["mod": "Mod-only", "none": "Disabled"])[mappingp(response) && response->access] || "",
		)});
		order += ({cmd});
	}
	sort(order, commands);
	if (!sizeof(commands)) commands = ({"(none) |"});
	return render_template("chan_commands.md", ([
		"user text": user,
		"commands": commands * "\n",
		"templates": TEMPLATES * "\n",
	]) | req->misc->chaninfo);
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->session || !conn->session->user) return "Not logged in";
	sscanf(msg->group, "%s#%s", string command, string chan);
	object channel = G->G->irc->channels["#" + chan];
	if (!channel) return "Bad channel";
	if (!channel->mods[conn->session->user->login]) return "Not logged in"; //Most likely this will result from some other issue, but whatever
	if (command != "" && command != "!!") return "UNIMPL"; //TODO: Check that there actually is a command of that name
}

mapping _get_command(string cmd) {
	echoable_message response = G->G->echocommands[cmd];
	if (!response) return 0;
	if (mappingp(response)) return response | (["id": cmd]);
	return (["message": response, "id": cmd]);
}

mapping get_state(string group, string|void id) {
	sscanf(group, "%s#%s", string command, string chan);
	if (!G->G->irc->channels["#" + chan]) return 0;
	if (id) return _get_command(id); //Partial update of a single command. This will only happen if signalled from the back end.
	if (command != "" && command != "!!") return 0; //Single-command usage not yet implemented
	array commands = ({ });
	foreach (G->G->echocommands; string cmd; echoable_message response) if (has_suffix(cmd, "#" + chan))
	{
		if (command == "!!" && has_prefix(cmd, "!")) commands += ({_get_command(cmd)});
		else if (command == "" && !has_prefix(cmd, "!")) commands += ({_get_command(cmd)});
	}
	sort(commands->id, commands);
	return (["items": commands]);
}

array _validate_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//When CGI mode is deprecated, move the code into this module and have the
	//weird handler over in command_edit instead.
	function validate = function_object(G->G->http_endpoints->chan_command_edit)->validate;
	sscanf(conn->group, "%s#%s", string command, string chan);
	if (!G->G->irc->channels["#" + chan]) return 0;
	if (command == "" || command == "!!") {
		string pfx = command[..0]; //"!" for specials, "" for normals
		if (!stringp(msg->cmdname)) return 0;
		sscanf(msg->cmdname, "%*[!]%s%*[#]%s", command, string c);
		if (c != "" && c != chan) return 0; //If you specify the command name as "!demo#rosuav", that's fine if and only if you're working with channel "#rosuav".
		command = String.trim(lower_case(command));
		if (command == "") return 0;
		command = pfx + command;
	}
	command += "#" + chan; //Potentially getting us right back to conn->group, but more likely the group is just the channel
	//Validate the message. Note that there will be some things not caught by this
	//(eg trying to set access or visibility deep within the response), but they
	//will be merely useless, not problematic.
	return ({command, validate(msg->response)});
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array valid = _validate_update(conn, msg);
	if (!valid) return;
	if (valid[1] != "") make_echocommand(@valid);
	//Else message failed validation. TODO: Send a response on the socket.
}
void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array valid = _validate_update(conn, msg | (["response": ""]));
	if (!valid) return;
	if (valid[1] == "") make_echocommand(valid[0], 0);
	//Else something went wrong. Does it need a response?
}

protected void create(string name) {::create(name);}

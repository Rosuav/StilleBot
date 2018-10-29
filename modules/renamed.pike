inherit command;
constant all_channels = 1;
constant active_channels = ({"devicat"});
constant require_moderator = 1; //If 0, anyone can tag themselves. Mods can always tag anyone.
int last_used = 0;

string process(object channel, object person, string param)
{
	if (time() < last_used + 60) return 0;
	last_used = time();
	string user = person->user;
	if (param != "" && channel->mods[person->user]) user = param;
	//For some reason, Protocols.HTTP.get_url_data() is failing with a possibly emulated HTTP 502.
	//I can't be bothered figuring it out, so here's a shortcut: call on wget.
	Stdio.File stdout = Stdio.File();
	string response = "";
	Process.Process(({"wget", "-qO-", "https://twitch-tools.rootonline.de/username_changelogs_search.php?"
		+ Protocols.HTTP.http_encode_query((["q": user, "format": "json"]))}),
		(["stdout": stdout->pipe()])
	);
	stdout->set_read_callback(lambda(mixed i, string data) {response += data;});
	stdout->set_close_callback(lambda () {
		stdout->set_read_callback(0);
		catch {stdout->close();};
		mixed data; catch {data = Standards.JSON.decode_utf8(response);};
		if (arrayp(data) && sizeof(data))
		{
			sort(data->found_at, data);
			send_message(channel->name, sprintf("!renameuser %s %s", data[-1]->username_old, user));
		}
		else send_message(channel->name, sprintf("@%s: No name changes found.", user));
	});
}

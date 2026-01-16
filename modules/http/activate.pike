inherit http_endpoint;

//(Or if you don't have enough scopes yet)
constant not_logged_in = #"![\"Mustard Mine\" banner](/static/MustardMineBanner.png)

# Activate the bot for your channel

Welcome to the Mustard Mine family!

To activate this bot on your channel, you'll need to authenticate and confirm that you want
to do this. There is no cost, this just ensures that the bot is only where he is wanted :)

[Authenticate!](:.twitchlogin data-scopes=@$$scopes$$@)
";

constant logged_in = #"![\"Mustard Mine\" banner](/static/MustardMineBanner.png)

# Activate the bot for your channel

Welcome to the Mustard Mine family!

The bot is ready to activate for your channel! Just say the word, and the Mustard Mine will
be fully operational and available to be configured to your needs.

<form method=post>[Bot, Activate!](:#activate type=submit)</form>
";

constant bot_is_active = #"![\"Mustard Mine\" banner](/static/MustardMineBanner.png)

# Activate the bot for your channel

The Mustard Mine is currently serving your channel! You can [configure the bot here](/c/).
If you wish to remove the bot, the [Master Control Panel](/c/mastercontrol) has the option to do so.

What can the bot do for you? Check out the [help pages](/c/help) or dive right in with
[activating features](/c/features).

Still got questions? Reach out to [Rosuav](https://twitch.tv/rosuav) via Twitch, Discord, or GitHub.
";

__async__ string|mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	string|zero scopes = "chat:read channel:bot bits:read moderator:read:followers";
	if (int userid = (int)req->misc->session->user->?id) {
		object channel = G->G->irc->id[userid];
		if (channel) return render_template(bot_is_active, ([]));
		//Like ensure_bcaster_token but using the user ID
		array havescopes = G->G->user_credentials[userid]->?scopes || ({ });
		multiset wantscopes = (multiset)(scopes / " ");
		multiset needscopes = (multiset)havescopes | wantscopes;
		if (sizeof(needscopes) > sizeof(havescopes)) scopes = sort(indices(needscopes)) * " ";
		else if (req->request_type == "POST") {
			string login = req->misc->session->user->login;
			Stdio.append_file("activation.log", sprintf("[%d] Account activated by broadcaster request: uid %d login %O\n", time(), userid, login));
			//No scopes required, and you clicked the button to activate. Let's do this!
			await(connect_to_channel(userid));
			//Give the rest of the bot a chance to connect. TODO: Actually get notified somehow
			while (!G->G->irc->id[userid]) sleep(1);
			return redirect("/channels/" + login + "/");
		}
		else return render_template(logged_in, ([]));
	}
	return render_template(not_logged_in, (["scopes": scopes]));
}

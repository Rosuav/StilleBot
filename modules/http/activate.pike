inherit http_endpoint;

constant markdown = #"# Activate the bot for your channel

Welcome to the Mustard Mine family!

To activate this bot on your channel, you'll need to authenticate and confirm that you want
to do this.

$$logged_in$$
";

__async__ string|mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	string|zero scopes = "chat:read channel:bot"; //Do we need chat_login or user:read:chat?
	if (int userid = (int)req->misc->session->user->?id) {
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
		else scopes = 0; //Enable the Activate button
	}
	return render_template(markdown, ([
		"logged_in": !scopes ? "<form method=post>\n\n[Activate bot!](:#activate type=submit)\n</form>"
			: "[Authenticate!](:.twitchlogin data-scopes=@" + scopes + "@)",
	]));
}

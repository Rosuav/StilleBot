#charset utf-8
inherit http_endpoint;

constant markdown = #"# Twitch Login

Log in to StilleBot to grant the bot permission to do what it needs.

Grant the following permissions:
$$scopelist$$

[Grant permissions](:.twitchlogin #addscopes)
";

//Give additional explanatory notes for a few scopes
//Note that anything that enables slash commands (see twitch_apis.pike) will automatically
//have those listed, and does not need an explicit entry here.
mapping scope_reasons = ([
	"bits:read": "Enables the bits leaderboard",
	"channel:manage:raids": "Go raiding directly from the [Raid Finder](/raidfinder)",
	"channel:manage:redemptions": "Manage channel point rewards and redemptions",
	"channel:read:hype_train": "Enables the [Train Tracker](/hypetrain) for your channel",
	"moderation:read": "Prevent banned users from sharing art with your channel",
	"moderator:read:chatters": "Enables the 'For each active chatter' command element",
	"moderator:read:followers": "Enables follower alerts",
	"user:read:follows": "Enables the core Raid Finder mode",
]);

mapping(string:mixed) login_popup_done(Protocols.HTTP.Server.Request req, mapping user, multiset scopes, string token, string cookie) {
	req->misc->session->user = user;
	req->misc->session->scopes = (multiset)(req->variables->scope / " ");
	req->misc->session->token = token;
	req->misc->session->authcookie = cookie;
	return (["data": "<script>window.close(); window.opener.location.reload();</script>", "type": "text/html"]);
}

mapping(string:function) login_callback = ([]);
mapping(string:string) resend_redirect = ([]);
__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (req->variables->code)
	{
		//It's a positive response from Twitch
		if (string dest = resend_redirect[req->variables->code]) return redirect(dest);
		//write("Login response %O\n", req->variables);
		object auth = TwitchAuth(0, deduce_host(req->request_headers || ([])));
		//write("Requesting access token for %O...\n", req->variables->code); //This shows up twice when those crashes happen. Maybe caching the redirect will help?
		string cookie = await(auth->request_access_token_promise(req->variables->code));
		auth->set_from_cookie(cookie);
		mapping user = await(twitch_api_request("https://api.twitch.tv/helix/users",
			(["Authorization": "Bearer " + auth->access_token])))
				->data[0];
		//Check if these credentials are at least what we already had.
		mapping tok = G->G->user_credentials[(int)user->id] || ([]);
		array missing = (tok->scopes || ({ })) - (req->variables->scope / " ");
		if (sizeof(missing)) {
			//TODO: Send back a redirect with a new login request?
		} else G->G->DB->save_user_credentials(([
			"userid": (int)user->id,
			"login": user->login,
			"token": auth->access_token,
			"authcookie": cookie,
			"scopes": sort(req->variables->scope / " "),
			"validated": time(),
			"user_info": user,
		]));
		if (function f = login_callback[req->variables->state])
			return f(req, user, (multiset)(req->variables->scope / " "), auth->access_token, cookie);
		//Try to figure out a plausible place to send the person after login.
		//For streamers, redirect to the stream's landing page. Doesn't work
		//for mods, as there might be more than one (and we'd need permission
		//to do a sword hunt anyway).
		string dest = "/login_ok";
		object channel = G->G->irc->channels["#" + user->login];
		if (channel) dest = "/channels/" + user->login + "/";
		resend_redirect[req->variables->code] = dest;
		call_out(m_delete, 30, resend_redirect, req->variables->code);
		login_popup_done(req, user, (multiset)(req->variables->scope / " "), auth->access_token, cookie);
		return redirect(dest);
	}
	//Merge scopes, similarly to ensure_login()
	//NOTE: Some things are inconsistent on whether it's "scope" or "scopes". Currently
	//checking for either. TODO: Make them all consistent.
	multiset havescopes = req->misc->session->?scopes || (<>);
	string bcast_scopes = token_for_user_login(req->misc->session->user->?login)[1];
	if (bcast_scopes != "") havescopes |= (multiset)(bcast_scopes / " ");
	multiset wantscopes = (multiset)((req->variables->scopes || req->variables->scope || "") / " " - ({""}));
	multiset bad = wantscopes - TwitchAuth()->list_valid_scopes();
	if (sizeof(bad)) return (["error": 400, "type": "text/plain", //Note that this is a 400, as opposed to a 500 in ensure_login
		"data": sprintf("Unrecognized scope %O being requested", (array)bad * " ")]);
	multiset needscopes = havescopes | wantscopes; //Note that we'll keep any that we already have.
	if (req->variables->urlonly) return jsonify((["uri": get_redirect_url(needscopes, ([]), deduce_host(req->request_headers || ([])), login_popup_done)]));

	//Offer an interactive page for adding scopes. Can also be used with a handy URL
	//like https://sikorsky.rosuav.com/twitchlogin?scopes=channel:manage:redemptions
	//to add a specific permission.
	array order = ({ }), scopelist = ({ }), retain_scopes = ({ });
	foreach (all_twitch_scopes; string id; string desc) {
		if (has_prefix(desc, "Deprecated") || has_prefix(desc, "*Deprecated")) {
			if (needscopes[id]) retain_scopes += ({id});
			continue;
		}
		order += ({desc - "*"});
		scopelist += ({"* <label><input type=checkbox class=scope_cb" + " checked" * needscopes[id] + " value=\"" + id + "\">"
			//+ (desc[0] == '*' ? "<span class=warningicon>⚠️</span>" : "") //Do we need these here or are they just noise?
			+ (desc - "*")});
		if (scope_reasons[id]) scopelist[-1] += "\n  <br>*" + scope_reasons[id] + "*";
		if (array cmd = G->G->voice_scope_commands[id])
			scopelist[-1] += "\n  <br>*Enables the " + sort(cmd) * ", " + " special command" + ("s" * (sizeof(cmd) > 1)) + "*";
	}
	sort(order, scopelist);

	return render_template(markdown, ([
		"vars": (["retain_scopes": retain_scopes * " "]),
		"js": "twitchlogin",
		"scopelist": scopelist * "\n",
	]));
}

string get_redirect_url(multiset scopes, mapping extra, string|zero host, function callback) {
	string state = replace(MIME.encode_base64(random_string(15)), (["/": "1", "+": "0"]));
	login_callback[state] = callback;
	call_out(m_delete, 600, login_callback, state);
	return TwitchAuth(scopes, host)->get_auth_uri(extra | (["state": state]));
}

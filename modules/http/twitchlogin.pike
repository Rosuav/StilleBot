#charset utf-8
inherit http_endpoint;

constant markdown = #"# Twitch Login

Log in to Mustard Mine to grant the bot permission to do what it needs.

$$grantperms$$

Grant the following permissions:
$$scopelist$$

$$grantperms$$
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

mapping(string:mixed) login_popup_done(Protocols.HTTP.Server.Request req, mapping user, multiset scopes, string token) {
	req->misc->session->user = user;
	req->misc->session->scopes = scopes;
	req->misc->session->token = token;
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
		if (mixed ex = catch {
			string cookie = await(auth->request_access_token_promise(req->variables->code));
			auth->set_from_cookie(cookie);
		}) {
			werror("ERROR getting logged-in user status\n%O\n", ex);
			if (arrayp(ex)) werror(describe_backtrace(ex));
			return redirect("/login_ok");
		}
		mapping user = await(twitch_api_request("https://api.twitch.tv/helix/users",
			(["Authorization": "Bearer " + auth->access_token])))
				->data[0];

		//First, see if the current credentials are a superset of what we already had.
		//If they are, great! Expand the login scope and all is well.
		//If not, are the old credentials a superset of what we now have? Keep the old
		//login and move on. Replace what's in the user's session.
		//Otherwise, there's some sort of symmetric difference - each token has some
		//scope that the other doesn't. Keep the NEW token, but report a banner on all
		//pages showing that there is more to be seen.

		//Grab the old credentials (if any) and validate them...
		mapping tok = G->G->user_credentials[(int)user->id] || ([]);
		mapping oldtok = tok->token ? await(twitch_api_request("https://id.twitch.tv/oauth2/validate",
			(["Authorization": "Bearer " + tok->token]))) : ([]);
		//... and compare to what Twitch says we now have:
		mapping newtok = await(twitch_api_request("https://id.twitch.tv/oauth2/validate",
			(["Authorization": "Bearer " + auth->access_token])));
		array oldscopes = oldtok->scopes || ({ }), newscopes = newtok->scopes || ({ });
		array oldmissing = newscopes - oldscopes, newmissing = oldscopes - newscopes;
		multiset scopes; string token;
		if (!sizeof(newmissing)) {
			//The new token has at least the same scopes as the old one did. Use it.
			//This might actually fix (or partly fix) a previous "missing" state.
			array stillmissing = (tok->missing || ({ })) - newscopes;
			G->G->DB->save_user_credentials(([
				"userid": (int)user->id,
				"login": user->login,
				"token": auth->access_token,
				//"authcookie": cookie, //Not currently stored since it's not needed. Consider storing it encoded if it would help with anything.
				"scopes": sort(newscopes),
				"validated": time(),
				"user_info": user,
				"missing": sizeof(stillmissing) && stillmissing,
			]));
			scopes = (multiset)newscopes; token = auth->access_token;
			werror("Saving NEW token for %s\n", user->login);
		} else if (!sizeof(oldmissing)) {
			//The old token has all the scopes, the new one is missing some. (Most
			//likely, the new one has none whatsoever, because it's simply a relogin.)
			//Don't save the new credentials; the old ones are still good, and there's
			//nothing to be learned from the new ones other than that this is the same
			//user. Replace the session credentials with the saved ones.
			scopes = (multiset)oldscopes; token = tok->token;
			werror("Saving OLD token for %s\n", user->login);
		} else {
			//We have a symmetric difference. For example, you previously gave permission
			//to view hype train stats, but now you're independently giving permission to
			//check your emote list. Since the user is more likely to want to do the thing
			//they're NOW doing, retain the new token, but have a marker saying that there
			//is a problem.
			G->G->DB->save_user_credentials(([
				"userid": (int)user->id,
				"login": user->login,
				"token": auth->access_token,
				//"authcookie": cookie, //Not currently stored since it's not needed. Consider storing it encoded if it would help with anything.
				"scopes": sort(newscopes),
				"validated": time(),
				"user_info": user,
				"missing": (tok->missing || ({ })) | newmissing,
			]));
			scopes = (multiset)newscopes; token = auth->access_token;
			werror("WARNING: Saving NEW token for %s but missing %O + %O\n", user->login, tok->missing || ({ }), newmissing);
		}
		if (function f = login_callback[req->variables->state])
			return f(req, user, scopes, token);
		//Try to figure out a plausible place to send the person after login.
		//For streamers, redirect to the stream's landing page. Doesn't work
		//for mods, as there might be more than one (and we'd need permission
		//to do a sword hunt anyway).
		string dest = "/login_ok";
		object channel = G->G->irc->channels["#" + user->login];
		if (channel) dest = "/channels/" + user->login + "/";
		resend_redirect[req->variables->code] = dest;
		call_out(m_delete, 30, resend_redirect, req->variables->code);
		login_popup_done(req, user, scopes, token);
		return redirect(dest);
	}
	//Merge scopes, similarly to ensure_login()
	//NOTE: Some things are inconsistent on whether it's "scope" or "scopes". Currently
	//checking for either. TODO: Make them all consistent.
	multiset havescopes = req->misc->session->?scopes || (<>);
	mapping tok = G->G->user_credentials[(int)req->misc->session->?user->?id] || ([]);
	if (tok->scopes) havescopes |= (multiset)tok->scopes;
	if (tok->missing) havescopes |= (multiset)tok->missing; //These are actually ones we DON'T have, but include them in the request anyway.
	multiset wantscopes = (multiset)((req->variables->scopes || req->variables->scope || "") / " " - ({""}));
	multiset bad = wantscopes - TwitchAuth()->list_valid_scopes();
	if (sizeof(bad)) return (["error": 400, "type": "text/plain", //Note that this is a 400, as opposed to a 500 in ensure_login
		"data": sprintf("Unrecognized scope %O being requested", (array)bad * " ")]);
	multiset needscopes = havescopes | wantscopes; //Note that we'll keep any that we already have.
	if (req->variables->urlonly) return jsonify((["uri": get_redirect_url(
		needscopes,
		req->variables->force_verify ? (["force_verify": "true"]) : ([]),
		deduce_host(req->request_headers || ([])),
		login_popup_done,
	)]));

	//Offer an interactive page for adding scopes. Can also be used with a handy URL
	//like https://mustardmine.com/twitchlogin?scopes=channel:manage:redemptions
	//to add a specific permission.
	array order = ({ }), scopelist = ({ }), retain_scopes = ({ });
	//Have we been notified of any perms required for active features? If so, preselect them.
	mapping need_perms = (req->misc->session->user->?id && await(G->G->DB->load_config(req->misc->session->user->?id, "userprefs"))->notif_perms) || ([]);
	string grantperms = "[Grant permissions](:.twitchlogin .addscopes)";
	if (req->variables->share || req->variables->shareable) { //aliases; will make it easy to create a shareable link
		need_perms = ([]);
		needscopes = (<>);
		grantperms = "[Shareable link](/twitchlogin :.shareable)";
	}
	foreach (all_twitch_scopes; string id; string desc) {
		if (has_prefix(desc, "Deprecated") || has_prefix(desc, "*Deprecated")) {
			if (needscopes[id]) retain_scopes += ({id});
			continue;
		}
		order += ({desc - "*"});
		scopelist += ({"* <label><input type=checkbox class=scope_cb" + (needscopes[id] || need_perms[id] ? " checked" : "") + " value=\"" + id + "\">"
			//+ (desc[0] == '*' ? "<span class=warningicon>⚠️</span>" : "") //Do we need these here or are they just noise?
			+ (desc - "*")});
		if (scope_reasons[id]) scopelist[-1] += "\n  <br>*" + scope_reasons[id] + "*";
		if (array cmd = G->G->voice_scope_commands[id])
			scopelist[-1] += "\n  <br>*Enables the " + sort(cmd) * ", " + " special command" + ("s" * (sizeof(cmd) > 1)) + "*";
		foreach (need_perms[id] || ({ }), mapping reason)
			scopelist[-1] += sprintf("\n  <br>*Required for* <code>%s</code>", reason->desc);
	}
	sort(order, scopelist);

	return render_template(markdown, ([
		"vars": (["retain_scopes": retain_scopes * " "]),
		"js": "twitchlogin",
		"grantperms": grantperms,
		"scopelist": scopelist * "\n",
	]));
}

string get_redirect_url(multiset scopes, mapping extra, string|zero host, function callback) {
	string state = replace(MIME.encode_base64(random_string(15)), (["/": "1", "+": "0"]));
	login_callback[state] = callback;
	call_out(m_delete, 600, login_callback, state);
	return TwitchAuth(scopes, host)->get_auth_uri(extra | (["state": state]));
}

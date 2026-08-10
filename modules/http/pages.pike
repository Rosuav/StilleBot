//Manage a GitHub Pages site
//Possibly will be able to push to other forms of hosting, for those for whom
//GH Pages is ill-suited.
inherit http_websocket;
inherit annotated;

constant markdown = #"# Pages

Build simple web pages and host them on GitHub Pages. You retain full control at all times, and can take over the site, move it to other hosting, etc, as your site grows.

> ### Configure web site URL
> To select a nice URL for your web site, you will need to own a domain.
> (TODO: Link to one or more domain registrars.)
> In your domain registrar's DNS configuration, create a CNAME record pointing to
> mustardmine.github.io. Then type your web site's name in here:
>
> Site name: <input size=30 id=cname> <button type=button id=setcname>Update name</button>
>
> [Close](:.dialog_close)
{: tag=dialog #cnamedlg}

<div id=content>loading...</div>

> ### Edit file
> Name: <input id=filename></code> [\u{1F589}](:#filerename title=Rename) [\u{1f5d1}\ufe0e](:#filedelete title=Delete) <span id=filetype></span>
>
> <div id=fileeditor></div><img id=fileimage hidden>
>
> [Save](:#filesave) [Close without saving](:.dialog_close)
{: tag=dialog #editfiledlg}

<div id=banner></div>

> ### Rename file
> Old name: <input id=oldpath readonly></code><br>
> New name: <input id=newpath></code>
>
> Move or rename a file. Directories can be created simply by putting something in them.
>
> [Move/rename](:type=submit) [Cancel](:.dialog_close)
{: tag=formdialog #renamefiledlg}

<style>
#filedelete {background: red; color: white;}
#fileeditor {
	width: 900px; height: 300px;
	border: 1px solid black;
	padding: 4px;
}
#fileimage {max-width: 900px;}
#banner {
	position: fixed;
	top: 10px; right: 10px;
	opacity: 0;
	transition: opacity 60s;
	background: aliceblue;
	border: 1px solid rebeccapurple;
	padding: 0.5em 2em;
}
#banner.visible {
	transition: opacity 0.5s;
	opacity: 1;
}
#banner.error {
	background: #fee;
	border-color: red;
}
#banner.pending {
	background: #eef;
	border-color: darkblue;
}
#banner.done {
	background: #efe;
	border-color: darkgreen;
}
</style>

> ### Collaborators and ownership
> <div id=collaborators></div>
>
> [Close](:.dialog_close)
{: tag=dialog #collabsdlg}
";

@retain: mapping github_repo_details = ([]);
@retain: mapping yaml_decode_cache = ([]); //Map a SHA1 to the decoded version of it - can be purged at any time, just reduces duplicated work

//Cache the generated token until it's close to expiring
//Not retained across code reloads as it'll never have more than ten minutes of validity anyway
string|zero jwt; int jwt_expiration;
string github_jwt() {
	if (jwt_expiration > time() + 60) return jwt;
	mapping claims = ([
		"exp": jwt_expiration = time() + 540, //GitHub demands no more than 10 minutes of validity; give 9 for safety.
		"iss": G->G->instance_config->github_clientid,
		"alg": "RS256",
	]);
	string pk = Standards.PEM.Messages(Stdio.read_file("github-key.pem"))->get_private_key();
	object sign = Standards.PKCS.RSA.parse_private_key(pk);
	//If the public key is needed, Standards.JSON.encode(sign->jwk()) will provide it in the right format.
	return jwt = Web.encode_jwt(sign, claims);
}

string|zero install_token; int install_token_expiration;
__async__ mapping|array|string github_api_request(string endpoint, mapping|void options) {
	if (!options) options = ([]);
	//In API requests, send headers:
	mapping headers = ([
		"Accept": options->raw ? "application/vnd.github.raw+json" : "application/vnd.github+json",
		"X-GitHub-Api-Version": "2026-03-10",
		"User-Agent": "Mustard-Mine",
	]);
	switch (options->authtype || "token") {
		case "JWT": headers->Authorization = "Bearer " + github_jwt(); break;
		case "token": {
			//First get an access token for the installation. These expire in an hour.
			if (install_token_expiration < time() + 60) {
				//FIXME: How are we supposed to know the correct installation ID? Should that go into instance_config?
				mapping token = await(github_api_request("/app/installations/147687849/access_tokens", (["method": "POST", "authtype": "JWT"])));
				if (!token->token) return (["cmd": "error", "error": "Unable to get token", "raw": token]);
				install_token_expiration = Calendar.parse("%Y-%M-%DT%h:%m:%s%z", token->expires_at)->unix_time();
				install_token = token->token;
			}
			headers->Authorization = "Bearer " + install_token;
			break;
		}
		default: break; //Unauthenticated
	}
	string body = options->data;
	if (options->json) {
		headers["Content-Type"] = "application/json";
		body = Standards.JSON.encode(options->json, 1);
	}
	string method = options->method || (body ? "POST" : "GET");
	Protocols.HTTP.Promise.Result res = await(Protocols.HTTP.Promise.do_method(method, "https://api.github.com" + endpoint,
			Protocols.HTTP.Promise.Arguments((["headers": headers, "data": body]))));
	if (options->raw) return res->get();
	if (res->status == 204 && res->get() == "") return ([]);
	mixed data; catch {data = Standards.JSON.decode_utf8(res->get());};
	//TODO: error handling
	return data;
}

//Categorize files into a few end-user-meaningful groups.
//It'd be nice if GitHub gave us the file's detected MIME type, but short of actually fetching
//the *contents* of every file, we're stuck looking at filename extensions.
constant EXTENSION_CATEGORIES = ([
	"md": "pages",
	"yml": "layouts", "html": "layouts",
	"css": "layouts", "scss": "layouts",
	"js": "layouts", "ts": "layouts",
	"png": "media", "gif": "media", "jpg": "media", "jpeg": "media", "webp": "media",
]);

__async__ void load_repo_details(string userid, string which) {
	mapping repo = github_repo_details[userid];
	if (!repo) return await(query_github_repo(userid)); //If we don't have anything loaded, freshly load everything. This will come back to load_repo_details shortly.
	if (which == "*" || which == "contents") {
		//Load the contents asynchronously, and then atomically replace them into the main repo mapping.
		mapping tmp = ([]);
		mapping files = await(github_api_request("/repos/mustardmine/" + userid + "/git/trees/HEAD?recursive=1"));
		if (!mappingp(files) || !arrayp(files->tree)) return; //Probably an error. Not worth the hassle for now.
		//sort(files->tree->path, files->tree); //Do we need to enforce sort order?
		tmp->filemodes = ([]); //Doesn't need to be sent to the front end but it's fine
		foreach (files->tree, mapping file) {
			if (file->type != "blob") continue; //Ignore non-files; symlinks etc will be hard to edit, and trees are not inherently relevant.
			mapping f = file & (<"path", "size", "sha">); //The rest is uninteresting to the front end
			sscanf(basename(file->path), "%*s.%s", string ext); //If it has more than one extension, it's not going to match any of our checks anyway
			tmp[EXTENSION_CATEGORIES[ext] || "files"] += ({f});
			tmp->filemodes[file->path] = file->mode;
			if (f->path == "_config.yml") repo->config_hash = f->sha;
		}
		foreach (values(EXTENSION_CATEGORIES), string cat) m_delete(repo, cat); //Remove any categories that didn't get files added to them
		foreach (tmp; string cat; array files) repo[cat] = files;
		repo->sha = files->sha; //Commit hash as of the last query
		//Note that deleting or renaming _config.yml may cause a lot of confusion as I'll keep using the old config for a while.
		//Don't do that.
		if (!yaml_decode_cache[repo->config_hash]) { //Most of the time we won't need to re-fetch
			string config = await(github_api_request("/repos/mustardmine/" + userid + "/git/blobs/" + repo->config_hash,
				(["raw": 1])));
			//I don't have a Pike YAML parser. It's easier to cheat and ask Python to parse it for me.
			mapping proc = await(run_process(({"python3", "-c", "import sys, yaml, json; json.dump(yaml.safe_load(sys.stdin), sys.stdout)"}),
				(["stdin": config])));
			yaml_decode_cache[repo->config_hash] = Standards.JSON.decode_utf8(proc->stdout);
		}
		repo->_config = yaml_decode_cache[repo->config_hash];
	}
	if (which == "*" || which == "collaborators") {
		array collab = await(github_api_request("/repos/mustardmine/" + userid + "/collaborators"));
		array invite = await(github_api_request("/repos/mustardmine/" + userid + "/invitations"));
		repo->collab = ({ });
		foreach (collab, mapping user) {
			if (user->login == "Rosuav") continue; //?? I think I'm a collaborator everywhere despite not being added. Check if this is the case.
			repo->collab += ({([
				"username": user->login,
				"avatar": user->avatar_url,
			])});
		}
		foreach (invite, mapping inv) {
			if (inv->expired) continue; //Should expired invitations be shown at all, or just pretend they don't exist?
			repo->collab += ({([
				"username": inv->invitee->login,
				"avatar": inv->invitee->avatar_url,
				"pending": inv->created_at,
			])});
		}
	}
	send_updates_all("#" + userid);
}

__async__ void query_github_repo(string userid) {
	mapping repo = github_repo_details[userid];
	if (!repo) repo = github_repo_details[userid] = ([]);
	repo->_last_checked = time();
	mapping raw = await(github_api_request("/repos/mustardmine/" + userid));
	if (raw->status == "404") ; //No repo found; retain empty mapping to show that it has been checked.
	else if (raw->status) {repo->_error = "Unable to load repository"; repo->_raw = repo;}
	else {
		repo->default_branch = raw->default_branch;
		//Immediately set some URL here if we don't have one; but if we've replaced the basic
		//URL with a deployment URL, keep that (unless we find that it's no longer valid).
		if (!repo->html_url) repo->html_url = raw->html_url;
		//Do we have GH Pages? If so, replace the URL with the deployed version.
		mapping pages = await(github_api_request("/repos/mustardmine/" + userid + "/pages"));
		if (pages->html_url) repo->html_url = pages->html_url;
		else repo->html_url = raw->html_url;
		//Before loading everything else there is to know, push out what we have. There
		//is a chance that this will happen quickly, resulting in front end flicker;
		//but there's also a good chance it'll take too long to wait, and it would be
		//better to send what we know.
		send_updates_all("#" + userid);
		await(load_repo_details(userid, "*"));
		return; //load_repo_details will already send out updates, so we don't need to again.
	}
	send_updates_all("#" + userid);
}

//Handle automated editing of a file. Pass a mutator; it will be given the current contents
//as a string, or 0 if the file doesn't exist. If it returns non-zero, the file will be
//updated to that content.
__async__ void edit_file(string userid, string filename, string commitmsg, function mutator) {
	mapping user = await(get_user_info(userid));
	array|mapping file = await(github_api_request("/repos/mustardmine/" + userid + "/contents/" + filename));
	string content;
	if (!mappingp(file) || file->status == "404") content = mutator(0);
	else content = mutator(MIME.decode_base64(file->content));
	if (content) await(github_api_request("/repos/mustardmine/" + userid + "/contents/" + filename, ([
		"method": "PUT",
		"json": ([
			"sha": file->sha,
			"message": commitmsg,
			"committer": (["name": user->display_name, "email": userid + "@twitchuser.invalid"]),
			"content": MIME.encode_base64(content, 1),
		]),
	])));
}

//When a repo is created, the corresponding GH Pages site can't be made until the master branch
//exists. This happens automatically (from the template) but takes a moment. When we see the
//push notification, we can continue with creation.
mapping pending_site_creation = ([]);
__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (string other = req->request_type == "POST" && !is_active_bot() && get_active_bot()) {
		//POST requests are likely to be webhooks. Forward them to the active bot, including whichever
		//of the relevant headers we spot. Add headers to this as needed.
		constant headers = (<"x-hub-signature-256", "x-github-event", "x-github-delivery", "content-type">);
		//Possibly also of interest: x-github-hook-{id,installation-target-id,installation-target-type}
		//werror("Forwarding GitHub webhook...\n");
		Concurrent.Future fwd = Protocols.HTTP.Promise.post_url("https://" + other + req->not_query,
			Protocols.HTTP.Promise.Arguments((["headers": req->request_headers & headers, "data": req->body_raw])));
		//As in chan_integrations, not currently awaiting the promise. Should we?
		return "Passing it along.";
	}
	if (string sig = req->request_type == "POST" && req->request_headers["x-hub-signature-256"]) {
		string hmac_key = G->G->instance_config->github_hmac || "It's a Secret to Everybody"; //Test key as per https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries
		object signer = Crypto.SHA256.HMAC(hmac_key);
		if (sig != "sha256=" + String.string2hex(signer(req->body_raw))) {
			werror("GitHub webhook - Failed HMAC check\n");
			return (["error": 418, "data": "My teapot thinks your signature is wrong."]);
		}
		mapping data = Standards.JSON.decode_utf8(req->body_raw);
		if (!mappingp(data)) return (["error": 400, "data": "No data in body"]);
		//Useful hooks:
		switch (req->request_headers["x-github-event"]) {
			case "push": {
				//Someone just pushed code. Send out updates on the websocket. If someone is viewing that file
				//and hasn't changed it, replace it in their screen. If edited, pop up immediate prompt. Offer
				//diffs as available.
				string userid = data->repository->name;
				werror("GITHUB PUSH %O\n", userid);

				//So, what actually changed?
				/*
				mapping changes = await(github_api_request("/repos/mustardmine/" + userid + "/compare/" + data->before + "..." + data->after));
				//werror("CHANGES %O\n", changes->files);
				foreach (changes->files, mapping file) {
					//TODO.
					//file->filename, file->sha
				}
				*/
				//For now unconditionally reload contents. It may be worth checking the commits to see if the
				//list of files has changed (since the vast majority of edits won't create or delete files),
				//but it's simpler just to reload.
				load_repo_details(userid, "contents");

				if (m_delete(pending_site_creation, userid)) {
					mapping user = await(get_user_info(userid));
					edit_file(userid, "_layouts/default.html", "Set Twitch username") {
						return replace(__ARGS__[0], ([
							"$$login$$": user->login,
							"$$displayname$$": user->display_name,
						]));
					};
					mapping pg = await(github_api_request("/repos/mustardmine/" + userid + "/pages", (["json": (["source": (["branch": "master"])])])));
					werror("Created Pages: %O\n", pg);
					//TODO: Error checking. What happens if Pages can't be set up?
					query_github_repo(userid);
				}
				break;
			}
			case "member":
				//Someone just pushed code. Send out updates on the websocket. If someone is viewing that file
				//and hasn't changed it, replace it in their screen. If edited, pop up immediate prompt. Offer
				//diffs as available.
				werror("GITHUB COLLABORATOR %O\n", data->repository->name);
				load_repo_details(data->repository->name, "collaborators");
				break;
			case "workflow_run": {
				//Most likely, it's the GH Pages build. If data->action == "in_progress", mark that there's a
				//build in progress. If it is "completed", show that your most recent edit is live. Recognize
				//the user by data->repository->name.
				//Maybe check if data->workflow->name == "dynamic/pages/pages-build-deployment"?
				mapping repo = github_repo_details[data->repository->name];
				if (!repo) break; //If we haven't loaded the info, clearly nobody's waiting on us
				repo->build_status = data->action;
				send_updates_all("#" + data->repository->name);
				break;
			}
			case "installation_repositories":
				//Repositories have changed. Force a refresh of each. Note that we're not currently
				//serializing these; it's unlikely there'll be lots all at once.
				foreach (data->repositories_added + data->repositories_removed, mapping repo) {
					m_delete(github_repo_details, repo->name);
					query_github_repo(repo->name);
				}
				break;
			default:
				werror("GITHUB HOOK %O %O\n", req->request_headers["x-github-event"], data);
		}
		return "Okay";
	}
	//Delete a repository:
	//mixed repos = await(github_api_request("/repos/mustardmine/49497888", (["method": "DELETE"])));
	return render(req, (["vars": (["ws_group": "#" + (req->variables->demo ? "3141592653589793" : req->misc->session->user->?id)])]));
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->group)) return "String group only";
	sscanf(msg->group, "%s#%s", string subgroup, string userid);
	if (userid == "3141592653589793") {
		if (!is_localhost_mod(conn->session->user->?login, conn->remote_ip)) conn->session = ([
			"fake": 1,
			"user": (["id": "3141592653589793", "login": "!demo"]),
		]);
	}
	else if (userid != (string)conn->session->user->?id) return "That's not you";
	conn->siteid = userid;
	if (subgroup != "") return "Bad subgroup"; //Currently no subgroups are supported
}

__async__ mapping get_state(string group) {
	sscanf(group, "%s#%s", string subgroup, string userid);
	if (userid == "0") return (["self": Val.null]); //Signal the front end that you're not logged in
	//If you're the demo user, provide demo user data
	mapping user = userid == "3141592653589793" ? ([
		"fake": 1, "display_name": "Demo User",
		//Use Mustard Mine's avatar
		"profile_image_url": "https://static-cdn.jtvnw.net/jtv_user_pictures/fcfde5d1-f150-4d6b-a56b-78337762fddc-profile_image-300x300.png",
	]) : await(get_user_info(userid));
	mapping site = github_repo_details[userid] || ([]);
	if (site->_last_checked < time() - 3600) query_github_repo(userid);
	return ([
		"self": user,
		"site": site,
	]);
}

__async__ mapping websocket_cmd_create_site(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Cor, what a site...
	string userid = conn->siteid;
	if (conn->session->fake) return (["cmd": "demo"]);
	mapping repo = await(github_api_request("/repos/mustardmine/template/generate", (["json": ([
		"owner": "mustardmine",
		"name": userid,
		"description": conn->session->user->display_name + "'s web site",
	])])));
	if (repo->status) {
		werror("REPO CREATION FAILED %O\n", repo);
		m_delete(github_repo_details, userid);
		query_github_repo(userid);
		return (["cmd": "error", "error": "Unable to create site (see log)"]);
	}
	pending_site_creation[userid] = 1;
	return (["cmd": "status", "message": "Creating web site, please wait..."]);
}

__async__ mapping websocket_cmd_fetch_file(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string userid = conn->siteid;
	array|mapping file = await(github_api_request("/repos/mustardmine/" + userid + "/contents/" + msg->path));
	if (arrayp(file)) {
		//It's a directory. We should have expanded these out BEFORE sending to the front end,
		//so that it can show the full tree interactively; this endpoint shouldn't get these requests.
		return (["cmd": "error", "error": "Only fetch files, not directories"]);
	}
	if (file->status == "404") return (["cmd": "file_loaded", "path": msg->path]); //Without the "type" it indicates that the file isn't present.
	//Is file->encoding ever *not* going to be "base64"?
	return file & (<"content", "path", "name", "sha", "type">) | (["cmd": "file_loaded"]);
}

__async__ mapping|zero websocket_cmd_save_file(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string userid = conn->siteid;
	if (conn->session->fake) return (["cmd": "demo"]);
	mapping resp = await(github_api_request("/repos/mustardmine/" + userid + "/contents/" + msg->path, ([
		"method": "PUT",
		"json": ([
			"sha": msg->sha,
			"message": "Update web site",
			"committer": (["name": conn->session->user->display_name, "email": userid + "@twitchuser.invalid"]),
			"content": msg->content,
		]),
	])));
	if (resp->status == "409") return (["cmd": "error", "error": "File was edited while you were looking at it"]);
	mapping repo = github_repo_details[userid];
	if (!repo->?_config) await(query_github_repo(userid));
	//Look to see if the file just saved was being uploaded into an autogallery directory.
	if (msg->sha) return 0; //Only newly-created files get auto-added.
	string autogallery;
	foreach (repo->?_config->?autogallery || ([]); string gallery; string paths) {
		//TODO maybe: If multiple matches, pick the longest? Would allow subdirectory
		//segregation but with a top-level catch-all.
		foreach (paths / " ", string path)
			if (has_prefix(msg->path, path)) autogallery = gallery;
	}
	if (autogallery) edit_file(userid, autogallery + ".md", "Add image to gallery") {
		if (!__ARGS__[0]) {send_msg(conn, (["error": "File uploaded, autogallery not found"])); return 0;}
		string content = __ARGS__[0];
		sscanf(content, "%s<div%spaginated-gallery%s</div>%s", string initial, string tag, string body, string trailer);
		//Try to make a reasonably plausible default title. Obviously the user can
		//edit this afterwards.
		sscanf(basename(msg->path), "%[^.]", string title);
		title = replace(title, "_", " ");
		body += sprintf("![%s](%s)\n", title, msg->path);
		return sprintf("%s<div%spaginated-gallery%s</div>%s", initial, tag, body, trailer);
	};
}

__async__ mapping websocket_cmd_rename_file(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string userid = conn->siteid;
	if (conn->session->fake) return (["cmd": "demo"]);
	mapping repo = github_repo_details[userid];
	if (!repo) {
		werror("Querying repository...\n");
		await(query_github_repo(userid));
		repo = github_repo_details[userid];
		if (!repo) return (["cmd": "error", "error": "Bad repository"]); //Maybe the repo doesn't actually exist
	}
	string mode = repo->filemodes[msg->oldpath];
	if (!mode) return (["cmd": "error", "error": "File " + msg->oldpath + " not found for rename"]);
	mapping tree = await(github_api_request("/repos/mustardmine/" + userid + "/git/trees", (["json": ([
		"base_tree": repo->sha,
		"tree": ({
			(["path": msg->oldpath, "sha": Val.null, "mode": mode]),
			(["path": msg->newpath, "sha": msg->sha, "mode": mode]),
		}),
	])])));
	//TODO: If (!tree->sha), report error
	mapping commit = await(github_api_request("/repos/mustardmine/" + userid + "/git/commits", (["json": ([
		"message": "Rename " + msg->oldpath + " to " + msg->newpath,
		"tree": tree->sha,
		"parents": ({repo->sha}),
		//NOTE: When using the repository contents API, set the committer and the author will default to it.
		//But when using the git commits API, set the author and the committer will default to it instead.
		"author": (["name": conn->session->user->display_name, "email": userid + "@twitchuser.invalid"]),
	])])));
	//Ditto if (!commit->sha)
	mapping ref = await(github_api_request("/repos/mustardmine/" + userid + "/git/refs/heads/" + repo->default_branch, (["json": ([
		"sha": commit->sha,
	])])));
	//Ditto if not successful
	//Note: This should be followed shortly by a PUSH that will update the front end
}

__async__ mapping websocket_cmd_delete_file(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string userid = conn->siteid;
	if (conn->session->fake) return (["cmd": "demo"]);
	//Unusually, this is a DELETE with a body.
	mapping resp = await(github_api_request("/repos/mustardmine/" + userid + "/contents/" + msg->path, ([
		"method": "DELETE",
		"json": ([
			"sha": msg->sha,
			"message": "Remove page from web site",
			"committer": (["name": conn->session->user->display_name, "email": userid + "@twitchuser.invalid"]),
		]),
	])));
	if (resp->status == "409") return (["cmd": "error", "error": "File was edited while you were looking at it"]);
}

__async__ mapping websocket_cmd_set_cname(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string userid = conn->siteid;
	if (conn->session->fake) return (["cmd": "demo"]);
	mapping ret = await(github_api_request("/repos/mustardmine/" + userid + "/pages", (["method": "PUT", "json": (["cname": msg->cname])])));
	//TODO: Error checking
	//TODO: Health check: https://docs.github.com/en/rest/pages/pages?apiVersion=2026-03-10#get-a-dns-health-check-for-github-pages
	query_github_repo(userid);
}

__async__ mapping websocket_cmd_add_collaborator(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string userid = conn->siteid;
	if (conn->session->fake) return (["cmd": "demo"]);
	mapping ret = await(github_api_request("/repos/mustardmine/" + userid + "/collaborators/" + msg->username, (["method": "PUT", "json": (["permission": "admin"])])));
	load_repo_details(userid, "collaborators");
}

__async__ mapping websocket_cmd_remove_collaborator(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string userid = conn->siteid;
	if (conn->session->fake) return (["cmd": "demo"]);
	mapping ret = await(github_api_request("/repos/mustardmine/" + userid + "/collaborators/" + msg->username, (["method": "DELETE"])));
	load_repo_details(userid, "collaborators");
}

__async__ mapping websocket_cmd_transfer_repository(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string userid = conn->siteid;
	if (conn->session->fake) return (["cmd": "demo"]);
	mapping repo = github_repo_details[userid];
	if (!repo) {await(query_github_repo(userid)); repo = github_repo_details[userid];}
	//Ensure that the chosen user has been added as a collaborator
	if (!repo->collab || !has_value(repo->collab->username, msg->username)) return (["cmd": "error", "error": "Can only transfer to an existing collaborator"]);
	//Does the site have GH Pages?
	string reponame = "mm-web-site";
	if (!has_prefix(repo->html_url, "https://github.com/") && !has_prefix(repo->html_url, "https://mustardmine.github.io/")) {
		//If you have a GH Pages and an associated CNAME, use the name of the site itself
		//as the new repository name. It'll be better than the generic default.
		sscanf(repo->html_url, "http%*[s]://%[^/]", reponame);
	}
	mapping ret = await(github_api_request("/repos/mustardmine/" + userid + "/transfer", (["json": ([
		"new_owner": msg->username,
		"new_name": reponame,
	])])));
	werror("GITHUB REPO TRANSFERRED: %O\n", userid);
	Stdio.append_file("ghpages-transfers.log", sprintf("------\n%sGH Pages site transferred: Twitch %O GH %O\n%O\n", ctime(time()), userid, msg->username, ret));
}

//whatever hackery I need at any given time
__async__ void hack() {
	string userid = "935215207";
	//m_delete(github_repo_details, userid); //Force a full load on next page refresh
	//await(query_github_repo(userid));
}

protected void create(string name) {::create(name); hack();}

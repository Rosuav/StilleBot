inherit http_websocket;
inherit annotated;

constant markdown = #"# Mockups

<canvas></canvas>

> ### Edit element
> Name: <input id=name>
> <textarea></textarea>
>
> [Save](:type=submit) [Cancel](:.dialog_close)
{: tag=formdialog #editelementdlg}

<style>
</style>
";

constant markdown_landing = #"# Mockups

You have the following mockups:

* loading...
{:#allmockups}

[Create new](:#create_mockup)
";

constant markdown_guest = #"# Mockups

You are not currently logged in. If someone has sent you a direct link to a
mockup to view or edit, check the URL to make sure it's correct; if you wish
to create a new mockup, you will need to [log in with a Twitch account](:.twitchlogin)

";

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (string id = req->variables->view) {
		//Ensure that the requested ID actually exists. This is not checked inside
		//websocket_validate as it doesn't allow asynchronicity, so if we didn't
		//check here, you'd get a successful connection with no useful data - not
		//very user-friendly. Note that this does not require authentication, even
		//for read-write functionality.
		mapping mock = await(G->G->DB->load_config(0, "mockup"))[id];
		if (mock) return render(req, (["vars": (["ws_group": id])]));
		//Otherwise fall through and show the landing page
	}
	if (string uid = req->misc->session->user->?id) {
		//If you're logged in, show your owned mockups.
		//mapping mocks = await(G->G->DB->load_config(uid, "mockup"));
		return render(req, markdown_landing, (["vars": (["ws_group": "uid-" + uid])]));
	}
	return render_template(markdown_guest, ([]));
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->group)) return "String group only";
	if (sscanf(msg->group, "uid-%d", int uid) && uid) {
		if (uid != (int)conn->session->user->?id) return "That's not you";
		conn->landing = 1; //Mark that it's a user page, not a mockup
	}
}

mapping describe_mock(mapping mocks, string id) {
	mapping mock = mocks[id];
	if (!mock) mock = (["title": "<DELETED>"]); //Shouldn't happen, data has become inconsistent
	return (["id": id]) | (mock & (<"title", "created_at">));
}

__async__ mapping get_state(string group) {
	mapping mocks = await(G->G->DB->load_config(0, "mockup"));
	if (sscanf(group, "uid-%d", int uid) && uid) {
		mapping yourmocks = await(G->G->DB->load_config(uid, "mockup"));
		return (["allmocks": describe_mock(mocks, (yourmocks->allmocks || ({ }))[*])]);
	}
	return mocks[group] || ([]);
}

__async__ mapping websocket_cmd_create_mockup(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->landing) return (["error": "Only create mockups from your landing page"]);
	string id;
	await(G->G->DB->mutate_config(0, "mockup") {mapping mocks = __ARGS__[0];
		do {id = MIME.encode_base64(random_string(12));} while (mocks[id]);
		mocks[id] = ([
			"created_at": time(),
			"created_by": conn->session->user->id,
			"title": "New Mockup",
			"description": "Describe the purpose of your mockup here.",
			"mutate": "",
			"scenes": (["default": (["title": "New Scene"])]),
		]);
	});
	await(G->G->DB->mutate_config(conn->session->user->id, "mockup") {mapping mocks = __ARGS__[0];
		mocks->allmocks += ({id});
	});
	send_updates_all(conn->group);
	return (["cmd": "mockup_created", "id": id]);
}

//Handle all mutators generically; they all need very similar handling.
//Note that the mutator itself must be synchronous; if it requires asynchronicity,
//don't use this shorthand (and probably don't use DB->mutate_config)
__async__ void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	::websocket_msg(conn, msg);
	function f = this["wsedit_" + msg->?cmd]; if (!f) return;
	if (conn->landing || !conn->mutate) return;
	mapping|zero resp;
	await(G->G->DB->mutate_config(0, "mockup") {mapping mock = __ARGS__[0][conn->group];
		if (!mock || conn->mutate != mock->mutate) return;
		resp = f(mock, conn, msg);
	});
	send_updates_all(conn->group);
	if (resp) send_msg(conn, resp);
}

//Will handle (["cmd": "example"]) as a mutator.
//Must NOT be asynchronous. Is allowed to return a response.
mapping wsedit_example(mapping mock, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mock->counter += (int)msg->increment || 1;
}

protected void create(string name) {::create(name);}

inherit http_websocket;
inherit annotated;

constant markdown = #"# Mockups

<p id=status></p>

Scene: <select id=sceneselector><option disabled>loading...</select> <span id=scenebuttons></span>

<div id=sidebyside><div id=canvasscroll><canvas width=2700 height=1500></canvas></div><div id=elementlist></div></div>

> ### Edit element
> <p id=typeselect>Type: <select id=typeselector><option value=minecart>Minecart</select></p>
> Name: <input id=elementtitle>
> <textarea id=elementdesc rows=5 cols=80></textarea>
>
> [Save](:type=submit) [Close](:.dialog_close) [Delete](:#deleteelement)
{: tag=formdialog #editelementdlg}

<style>
#deleteelement {
	background: red;
	color: yellow;
	margin-left: 1em;
}
#sidebyside {
	display: flex;
	gap: 0.5em;
	max-height: 800px; /* Or should main be made flex so this gets all remaining space? */
}
#canvasscroll {
	flex-grow: 1;
	overflow: auto;
}
#elementlist li {text-wrap: nowrap;}
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
	mapping mock = mocks[group] || ([]);
	if (mock->deleted) return (["deleted": 1]); //When it's deleted, you can't see anything else about it. It's secretly maintained though.
	return mock;
}

__async__ mapping websocket_cmd_create_mockup(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->landing) return (["error": "Only create mockups from your landing page"]);
	string id;
	await(G->G->DB->mutate_config(0, "mockup") {mapping mocks = __ARGS__[0];
		do {id = replace(MIME.encode_base64(random_string(12)), (["/": "q", "+": "X"]));} while (mocks[id]);
		mocks[id] = ([
			"created_at": time(),
			"created_by": conn->session->user->id,
			"title": "New Mockup",
			"description": "Describe the purpose of your mockup here.",
			"mutate": "",
			"scenes": (["default": (["title": "New Scene"])]),
			"elements": ([]),
		]);
	});
	await(G->G->DB->mutate_config(conn->session->user->id, "mockup") {mapping mocks = __ARGS__[0];
		mocks->allmocks += ({id});
	});
	send_updates_all(conn->group);
	return (["cmd": "mockup_created", "id": id]);
}

__async__ mapping websocket_cmd_mutate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping mock = await(G->G->DB->load_config(0, "mockup"))[conn->group];
	if (msg->mutate != mock->mutate) return (["cmd": "error", "error": "Incorrect password"]);
	conn->mutate = msg->mutate;
	return (["cmd": "mutation", "allowed": 1]);
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
mapping|zero wsedit_example(mapping mock, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mock->counter += (int)msg->increment || 1;
}

mapping|zero wsedit_update_element(mapping mock, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!(<"mockup", "scenes", "elements">)[msg->cat]) return (["error": "Bad cat"]); //I would say "shouldn't happen", but everyone who lives with a cat knows that they can be bad. But we love 'em anyway.
	if (msg->_delete) {
		if (msg->cat == "mockup") {
			if (conn->session->user->?id != mock->created_by) return (["error": "Only the owner can delete a mockup"]);
			//Technically I lie on the front end when I say that it's irreversible.
			//But I'm a smidge paranoid... so I'm leaving a 404 marker behind.
			mock->deleted = time();
			//Remove it from the user's list. This happens AFTER the current mutate_config is done.
			G->G->DB->mutate_config(mock->created_by, "mockup") {
				__ARGS__[0]->allmocks -= ({conn->group});
			}->then() {send_updates_all("uid-" + mock->created_by);};
		}
		//For everything other than the mockup, it _is_ irreversible though.
		else m_delete(mock[msg->cat], msg->id);
		//Ensure that there's always at least one scene
		if (msg->cat == "scenes" && !sizeof(mock->scenes))
			mock->scenes["default"] = (["title": "New Scene"]);
		return 0;
	}
	if (msg->id == "" && msg->cat == "elements") {
		//Blank ID means create; maybe this should subsume wsedit_new_scene?
		int i; for (i = 2; mock[msg->cat]["e" + i]; ++i);
		string type = msg->type;
		mock[msg->cat][msg->id = "e" + i] = ([]);
	}
	mapping target = msg->cat == "mockup" ? mock : mock[msg->cat][msg->id];
	if (!target) return 0;
	foreach ("title description" / " ", string key)
		if (!undefinedp(msg[key])) target[key] = msg[key];
	if (msg->cat == "elements") {
		//TODO: Validate the type, if not, set some sort of default
		if (msg->type) target->type = msg->type;
	}
}

mapping|zero wsedit_new_scene(mapping mock, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	int i; for (i = 2; mock->scenes["s" + i]; ++i);
	mock->scenes["s" + i] = (["title": "Scene " + i]);
	return (["cmd": "select_scene", "id": "s" + i]);
}

//Not run through wsedit_* as we do a cut-down update message - these will be common messages
__async__ void websocket_cmd_move_element(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->landing || !conn->mutate) return;
	mapping|zero update;
	await(G->G->DB->mutate_config(0, "mockup") {mapping mock = __ARGS__[0][conn->group];
		if (!mock || conn->mutate != mock->mutate) return;
		mapping scene = mock->scenes[msg->scene]; if (!scene) return;
		if (!mock->elements[msg->id]) return;
		if (!scene->elements) scene->elements = ([]);
		if (!scene->elements[msg->id]) scene->elements[msg->id] = ([]);
		scene->elements[msg->id] |= (["x": (float)msg->x, "y": (float)msg->y]);
		update = (["scene": msg->scene, "id": msg->id, "move_element": scene->elements[msg->id], "cause": msg->clientid]);
	});
	if (update) send_updates_all(conn->group, update);
}


//TODO: Have a way for the owner to set the password. This should send to all connected clients
//a message saying (["cmd": "mutation", "allowed": 0]) so they reset to read-only display; if
//a hacked-on client ignores this message, mutators will fail (since the password is rechecked
//inside websocket_msg(), but the UI elements will still all be there, which would be confusing.

protected void create(string name) {::create(name);}

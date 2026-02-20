inherit http_websocket;
inherit annotated;
inherit builtin_command;

constant markdown = #{# Respawn Technician

A great hero roams the world, destroying evil, saving princesses, rescuing the needy, and becoming wealthy in the process. His story is told
by kings and peasants alike, for his deeds are many and his accomplishments great.

You are not that hero. You are the technician who operates his respawn chamber.

When the hero dies, he comes back to life at the nearest respawn chamber, ready to try again. In the interests of the
realm at large, you must respawn him, again, and again, and again!
	
$$viewlink||$$

> ### Stats and Traits
> The Hero has **stats** and **traits**. His stats affect his in-game combat ability, and his traits affect how he chooses his battles.
> - STR: Melee damage dealt. Efficient DPS.
> - DEX: Ranged damage dealt. Less efficient but less risky.
> - CON: Health. More health means less respawning... hopefully.
> - INT: Observation. Higher intelligence lets the hero evaluate enemies better.
> - WIS: Mental fortitude. Reduces the negative effects of running from battle.
> - CHA: Charisma. Has no effect whatsoever. (Maybe it can upgrade his sprite eventually??)
>
> Traits are your way to influence the battle. When you respawn the hero, you can select from all the myriad versions of this hero throughout
> the multiverse, choosing one with the traits you desire. Each trait has two contradictory directions, each with its preferred combat style and
> preferred stats. Whenever the Hero makes a decision, his traits affect how he chooses.
> - Aggressive [STR]/Passive [INT]: An aggressive hero is more likely to take every fight he can, even if they are not worth much XP.
> - Headstrong [CON]/Prudent [WIS]: Headstrong heroes will take fights even when they look unwinnable; prudent heroes prefer to back off and level
>   up some more first.
> - Brave [CHA]/Cowardly [DEX]: Of course the hero is brave. At least in his own eyes! A brave hero will not shy away from battle, a cowardly one
>   will tend to retreat at the first sign of danger.
> - Other traits will have to be discovered as you defeat bosses!
>
{: tag=details}

<div id=display></div>
<style>
details {border: 1px solid black; margin: 5px; padding: 5px;}
$$styles$$
</style>
#};

constant dev_notes = #{
## Dev notes

Two modes: 2D and Linear
- In 2D mode, the hero's path branches periodically. He looks down each path, and makes a choice. But he mostly still moves left to right.
- In Linear mode, the branches are shown as doorways. He peeks into the door, and makes a choice. He moves exclusively left to right.

Next steps:
1. More bosses to unlock more content - Brave/Cowardly (easy), Bow (once implemented) - and then some more bosses just to be bosses
2. More effects of stats. Borrow idea from Murkon and have better chance to get first strike based on DEX vs WIS?
3. 2D mode maybe
#};

constant styles = #"
#pathway {
	display: flex;
	flex-direction: row-reverse;
	overflow: hidden;
	transition: all 30s;
}
#pathway.flashed {
	filter: contrast(0.1) brightness(200);
	transition: all 0.25s;
}
#pathway div {
	flex: 0 0 100px;
	height: 30px;
	border: 1px solid rebeccapurple;
	margin: 2px;
	padding: 3px;
}
#stats {display: flex; gap: 2em;}
#stats ul {
	list-style-type: none;
	padding: 0.25em;
	border: 1px solid black;
}
.twocol {
	padding: 0.25em;
	border: 1px solid black;
}
.twocol td, .twocol th {
	padding: 0 0.5em;
	text-align: center;
}
#messages {
	border: 1px solid grey;
	padding: 0 8px;
	height: 8em;
	flex: 0 0 300px;
	overflow-y: hidden;
}
.boosted {
	font-weight: bold;
	color: #292;
}
.reduced {
	font-weight: bold;
	color: #c33;
}
";
constant gamestyles = #"
/* Override the usual main styles, giving a transparent background */
html main {
	max-width: unset;
	margin: 0;
	background: none;
	padding: 0;
}
";

//rtr[channelid][userid] = "trait"
@retain: mapping respawn_traitrequests = ([]);

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	mapping cfg = await(G->G->DB->load_config(req->misc->channel->userid, "respawn"));
	if (req->variables->view) {
		if (cfg->nonce != req->variables->view) return 0; //404 if you get the nonce wrong
		return render_template("monitor.html", ([
			"vars": (["ws_type": ws_type, "ws_group": req->variables->view + "#" + req->misc->channel->userid, "display_mode": "active"]),
			"title": "Respawn Technician",
			"css": "stillebot.css",
			"styles": styles + gamestyles,
		]));
	}
	mapping repl = (["vars": (["ws_group": "", "allow_trait_requests": 0, "display_mode": "status"]), "styles": styles]) | req->misc->chaninfo;
	if ((int)req->misc->session->user->?id == req->misc->channel->userid) {
		//Create a nonce if one doesn't exist.
		if (!cfg->nonce) {
			//Deliberately not the same length as a chan_monitors nonce, just in case it gets confusing
			cfg->nonce = replace(MIME.encode_base64(random_string(30)), (["/": "1", "+": "0"]));
			await(G->G->DB->save_config(req->misc->channel->userid, "respawn", cfg));
		}
		repl->viewlink = sprintf(
			"To have this game play on your stream, add [this browser source](rt?view=%s :#browsersource) to OBS, eg by dragging it to the canvas.",
			cfg->nonce);
	}
	if (!req->misc->channel->userid) repl->vars->display_mode = "active+status"; //Gameplay inlined into the status page for the demo
	if (req->misc->session->user) repl->vars->allow_trait_requests = 1;
	if (req->misc->is_mod) repl->vars->allow_trait_requests = 2;
	return render(req, repl);
}

__async__ mapping get_chan_state(object channel, string grp, string|void id, string|void type) {
	mapping gamestate = await(G->G->DB->load_config(channel->userid, "respawn"));
	mapping tr = respawn_traitrequests[channel->userid];
	if (tr) {
		mapping count = ([]);
		foreach (values(tr), string t) count[t] += 1;
		gamestate->requests = count;
	}
	string nonce = m_delete(gamestate, "nonce");
	if (grp == "" || grp == nonce) return (["gamestate": gamestate]);
	return ([]);
}

__async__ void wscmd_save_game(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!mappingp(msg->gamestate)) return;
	string|void nonce;
	await(G->G->DB->mutate_config(channel->userid, "respawn") {
		if (__ARGS__[0]->nonce != conn->subgroup) return 0;
		nonce = __ARGS__[0]->nonce; //Set only if we actually accept the save
		return msg->gamestate | (["nonce": __ARGS__[0]->nonce]);
	});
	if (nonce) {
		send_updates_all(channel, "");
		send_updates_all(channel, nonce);
	}
}

//Send a signal to both the user group and the game group
__async__ void notify(object channel, mapping msg) {
	mapping gamestate = await(G->G->DB->load_config(channel->userid, "respawn"));
	send_updates_all(channel, "", msg);
	send_updates_all(channel, gamestate->nonce, msg);
}
void traitrequest(object channel, string uid, string trait) {
	//Note that this does not save to the database; if the game is active, it will be saved at
	//some point, and if the game isn't active, it won't matter anyway.
	mapping tr = respawn_traitrequests[channel->userid];
	if (!tr) respawn_traitrequests[channel->userid] = tr = ([]);
	tr[uid] = trait;
	mapping count = ([]);
	foreach (values(tr), string t) count[t] += 1;
	notify(channel, (["requests": count]));
}
void wscmd_traitrequest(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	traitrequest(channel, conn->session->user->id, (string)msg->trait);
}
void wscmd_cleartraitreqs(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	m_delete(respawn_traitrequests, channel->userid);
	notify(channel, (["requests": ([])]));
}
__async__ void wscmd_msg(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping gamestate = await(G->G->DB->load_config(channel->userid, "respawn"));
	//If we're the game group, send to the control group, nothing else
	if (conn->subgroup == gamestate->nonce) send_updates_all(channel, "", (["msg": msg->msg]));
}

constant command_description = "Respawn Technician";
constant builtin_name = "Respawn Tech";
constant builtin_param = ({"/Action/item/trait", "Extra info"});
constant MOCKUP_builtin_param = ({
	"/Action",
	([
		"item": ({"/Item/flash/stat/STR/DEX/INT/WIS/CON"}),
		"trait": ({"Trait"}),
	]),
});
constant vars_provided = ([]);
__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	switch (param[0]) {
		case "item": {
			mapping gamestate = await(G->G->DB->load_config(channel->userid, "respawn"));
			send_updates_all(channel, gamestate->nonce, (["gift": param[1]]));
			break;
		}
		case "trait": traitrequest(channel, (string)person->uid, param[1]); break;
	}
	return ([]);
}

protected void create(string name) {::create(name);}

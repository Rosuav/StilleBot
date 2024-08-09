inherit http_websocket;
constant markdown = #"# Minigames for $$channel$$

Want to add some fun minigames to your channel? These are all built using Twitch
channel points and other related bot features. Note that these will require that
the channel be affiliated/partnered in order to use channel points.

Bit Boss
--------

Not yet implemented.

Seize the Crown
---------------

There is only one crown, and everyone wants it. The cost to claim the crown goes
up every time the crown moves!

loading...
{:#seizecrown}

First!
------

This might be the last thing I implement.
";

/*
Bit Boss
- Alternate display mode for a goal bar: "Hitpoints".
- As the value advances toward the goal, the display reduces, ie it is inverted
- Use the "level up command" to advance to a new person
- Have an enableable feature that gives:
  - Goal bar, with variable "bitbosshp" and goal "bitbossmaxhp"
  - Level up command that sets "bitbossuser" to $$, resets bitbosshp to bitbossmaxhp,
    and maybe changes bitbossmaxhp in some way
    - Note that "overkill" mode can be done by querying the goal bar before making changes
  - Stream online special that initializes everything
  - Secondary monitor that shows the user's name and avatar??? Or should there be two
    effective monitors in the same page?

First, and optionally Second, Third, and Last
- Second/Third/Last are enabled by First/Second/Third
- Last can be had w/o Second/Third, so you can have anywhere from 1 to 4 redemptions
- Each one puts the person's name into the description and puts a message in chat
- You're not allowed to claim more than one. If you do, the message shames you.
*/

//Valid sections, valid attributes, and their default values
//Note that the default value also governs the stored data type.
constant sections = ([
	"crown": ([
		"enabled": 0,
		"initialprice": 5000,
		"increase": 1000,
		"gracetime": 60,
		"perpersonperstream": 0,
	]),
]);

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo); //Should there be non-privileged info shown?
	return render(req, (["vars": (["ws_group": "", "sections": sections])]) | req->misc->chaninfo);
}

Concurrent.Future get_chan_state(object channel, string grp, string|void id) {
	return G->G->DB->load_config(channel->userid, "minigames");
}

__async__ void wscmd_configure(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping sec = sections[msg->section]; if (!sec) return;
	mapping params = msg->params; if (!mappingp(params)) return;
	mapping game;
	await(G->G->DB->mutate_config(channel->userid, "minigames") {
		game = __ARGS__[0][msg->section];
		if (!game) game = __ARGS__[0][msg->section] = ([]);
		foreach (sec; string key; mixed dflt) {
			mixed val = params[key]; if (undefinedp(val)) continue;
			if (intp(dflt)) val = (int)val;
			else if (floatp(dflt)) val = (float)val;
			else val = (string)val;
			game[key] = val;
		}
	});
	send_updates_all(channel, "");
	//Now to perform the updates at Twitch's end and in other bot features.
	//Note that, if anything gets desynchronized, just make any trivial edit and this will update everything.
	this["update_" + msg->section](channel, game);
}

//Boolify for JSON purposes
object bool(mixed val) {return val ? Val.true : Val.false;}

__async__ void update_crown(object channel, mapping game) {
	if (!game->enabled && game->rewardid) {
		await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid + "&id=" + game->rewardid,
			(["Authorization": channel->userid]),
			(["method": "DELETE"])));
		m_delete(game, "rewardid");
		await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->crown = game;});
		//No other config changes are done. The deletion of the reward will (asynchronously)
		//result in other info getting cleaned up, but we broadly don't need to take action.
		return;
	}
	if (!game->enabled) return;
	mapping cfg = sections->crown | game;
	if (!game->rewardid) {
		//TODO: Should this disambiguation be in pointsrewards more generally?
		string basetitle = "Seize the Crown";
		array rewards = G->G->pointsrewards[channel->userid] || ({ });
		multiset have_titles = (multiset)rewards->title;
		string title = basetitle; int idx = 1; //First one doesn't get the number appended
		while (have_titles[title]) title = sprintf("%s #%d", basetitle, ++idx);
		mapping resp = await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid,
			(["Authorization": channel->userid]),
			(["json": ([
				"title": title,
				"cost": cfg->initialprice,
			])])));
		game->rewardid = resp->data[0]->id;
		await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->crown = game;});
	}
	mapping changes = ([
		"is_global_cooldown_enabled": bool(cfg->gracetime), "global_cooldown_seconds": cfg->gracetime,
		"is_max_per_stream_enabled": bool(!cfg->gracetime), "max_per_stream": !cfg->gracetime,
		"is_max_per_user_per_stream_enabled": bool(cfg->perpersonperstream), "max_per_user_per_stream": cfg->perpersonperstream,
	]);
	await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid + "&id=" + game->rewardid,
		(["Authorization": channel->userid]),
		(["method": "PATCH", "json": changes])));
	await(G->G->DB->mutate_config(channel->userid, "dynamic_rewards") {
		mapping rwd = __ARGS__[0][game->rewardid];
		if (!rwd) rwd = __ARGS__[0][game->rewardid] = ([
			"basecost": 0, "availability": "{online}",
			"prompt": "Seize the crown for yourself! The crown is currently held by $crownholder$, who was the last person to take it.",
		]);
		rwd->formula = "PREV + " + game->increase;
	});
}

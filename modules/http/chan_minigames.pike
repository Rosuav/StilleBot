inherit http_websocket;
constant markdown = #"# Minigames for $$channel$$

Want to add some fun minigames to your channel? These are all built using Twitch
channel points and other related bot features. Note that these will require that
the channel be affiliated/partnered in order to use channel points.

Bit Boss
--------

Not yet implemented - coming soon!

Seize the Crown
---------------

There is only one crown, and everyone wants it. The cost to claim the crown goes
up every time the crown moves!

loading...
{:#crown .game}

First!
------

Let your viewers compete to see who's first! The rewards are not available until the
stream goes online, and if you have Second/Third/Last, they will not become available
until the preceding reward(s) get claimed.

Whoever claims the reward will be celebrated in the reward's description until the end
of the stream.

loading...
{:#first .game}
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
- TODO: On channel offline (dedicated hook, don't do it in the special trigger), update all the
  descriptions and clear the variables with userids. How do we let the user customize the rewards?
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
	"first": ([
		"first": 0,
		"second": 0,
		"third": 0,
		"last": 0,
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
	if (!game->enabled) {
		if (game->rewardid) {
			await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid + "&id=" + game->rewardid,
				(["Authorization": channel->userid]),
				(["method": "DELETE"])));
			m_delete(game, "rewardid");
			await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->crown = game;});
		}
		if (channel->commands->seizecrown) G->G->cmdmgr->update_command(channel, "", "seizecrown", "");
		//No other config changes are done. The deletion of the reward will (asynchronously)
		//result in other info getting cleaned up, but we broadly don't need to take action.
		return;
	}
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
	if (!channel->commands->seizecrown) G->G->cmdmgr->update_command(channel, "", "seizecrown", #"
		#access \"none\"
		#visibility \"hidden\"
		#redemption \"" + game->rewardid + #"\"
		try {
			chan_pointsrewards(\"{rewardid}\", \"fulfil\", \"{redemptionid}\") \"\"
		}
		catch \"\"
		if (\"{username}\" == \"$crownholder$\") {
			\"You already hold the crown, {username} - good job wasting your points.\"
		}
		else {
			\"Congratulations to {username} for successfully claiming the crown from $crownholder$! You will retain this title until someone else seizes it from you...\"
			$crownholder$ = \"{username}\"
		}
		", (["language": "mustard"]));
}

constant firsts = ([
	"first": ([
		"title": "First!", "cost": 1,
		"unclaimed": "Claim this reward to let everyone know that you are the first one here!",
		"claimed": "Congratulations to {username} for being first to claim the reward this stream! Will it be you next time?",
		"response": "Congrats to @{username} for being first!",
	]),
	"second": ([
		"title": "Second!", "cost": 2,
		"unclaimed": "Missed out on being first? Claim this reward to let everyone know that you came second!",
		"claimed": "Congratulations to {username} for managing to claim the reward this stream! Will it be you next time?",
		"response": "And congrats to @{username} for being second!",
	]),
	"third": ([
		"title": "Third...", "cost": 3,
		"unclaimed": "Look, we know it's hard to be the best. But you can at least come in third...",
		"claimed": "Well done, well done. It was {username} who managed to be the oh so amazing third place winner.",
		"response": "Good job, @{username}. Third place. We are proud of you.",
	]),
	"last": ([
		"title": "Last?", "cost": 10,
		"unclaimed": "You're not first, but maybe you can be last?",
		"claimed": "Congratulations to {username} for being last (???) to claim the reward this stream!",
		"response": "Congrats to @{username} for being ... last??",
	]),
]);

constant first_code = #"
	#access \"none\"
	#visibility \"hidden\"
	#redemption \"%s\"
	try {
		chan_pointsrewards(\"{rewardid}\", \"fulfil\", \"{redemptionid}\") \"\"
	}
	catch \"Unexpected error: {error}\"
	//TODO: If you have claimed any prior reward, give the shame response.
	//TODO: Update this block if more rewards get added or some get removed,
	//without breaking if the streamer has customized the wording.
	%q
	try {
		chan_pointsrewards(\"{rewardid}\", \"desc\", %q) \"\"
	}
	catch \"Unexpected error: {error}\"
";

__async__ void update_first(object channel, mapping game) {
	//First (pun intended), some validation. Sequential rewards depend on each other.
	int changed = 0;
	if (!game->first && (game->second || game->last)) {
		game->second = game->last = 0;
		changed = 1;
	}
	if (!game->second && game->third) {
		game->third = 0;
		changed = 1;
	}
	//Okay. Now let's see which rewards need to be created or destroyed.
	//Fortunately the universe doesn't have a Law of Conservation of Channel Point Rewards,
	//or I'd be breaking the law right now!
	foreach (firsts; string which; mapping desc) {
		if (game[which]) {
			if (!game[which + "rwd"]) {
				mapping resp = await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid,
					(["Authorization": channel->userid]),
					(["json": ([
						"title": desc->title,
						"cost": desc->cost,
						"prompt": desc->unclaimed,
						"is_max_per_stream_enabled": Val.true, "max_per_stream": 1,
					]), "return_errors": 1])));
				if (resp->data && sizeof(resp->data)) game[which + "rwd"] = resp->data[0]->id; //Otherwise what? Try again next time?
				changed = 1;
			}
			if (!channel->commands["rwd" + which]) {
				string code = sprintf(first_code, game[which + "rwd"], desc->response, desc->claimed);
				string|zero nextid; //TODO: Locate the next active reward (ID), or 0 if there's none. Gotta get all reward IDs before fixing up the commands. Or? Use variables?
				if (nextid) code += "chan_pointsrewards(\"" + nextid + "\", \"enable\") \"\"";
				G->G->cmdmgr->update_command(channel, "", "rwd" + which, code, (["language": "mustard"]));
			}
		} else {
			if (string id = m_delete(game, which + "rwd")) {
				await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid + "&id=" + id,
					(["Authorization": channel->userid]),
					(["method": "DELETE"])));
				changed = 1;
			}
			if (channel->commands["rwd" + which]) G->G->cmdmgr->update_command(channel, "", "rwd" + which, "");
		}
		//If duplicate claim:
		//In chat: "Hey, hey, no fair! You already claimed a reward this stream. Shame is yours...",
		//In reward prompt: "Shame is upon {username} for being greedy and claiming more than one reward. Let's play nicely next time.",
	}
	if (changed) {
		await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->first = game;});
		send_updates_all(channel, "");
	}
}

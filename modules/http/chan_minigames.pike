inherit annotated;
inherit hook;
inherit http_websocket;
inherit builtin_command;
constant markdown = #"# Minigames for $$channel$$

Want to add some fun minigames to your channel? These are all built using Twitch
channel points and other related bot features. Note that these will require that
the channel be affiliated/partnered in order to use channel points.

Rock-Paper-Scissors
-------------------

Great for a BRB screen or a special party time, let your users battle it out in an
epic winner-takes-all rock/paper/scissors competition! Can be played in ongoing mode
or as a tournament. Viewers can use commands to add themselves, and then the results
are determined by physics, luck, and the rules of rock-paper-scissors.

loading...
{:#rps .game}

Bit Boss
--------

Win the boss battle, become the new boss. Deal damage with all forms of financial
support (configurable); whoever deals the final blow becomes the new boss.

loading...
{:#boss .game}

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
  - Autoreset on stream offline (implemented, untested)

First, and optionally Second, Third, and Last
- Count how many times a user has claimed a reward? ("You have been first N times")
  - What if you have multiple? Independently count? Count how many times you got ANY reward?
*/

//Valid sections, valid attributes, and their default values
//Note that the default value also governs the stored data type.
constant sections = ([
	"rps": ([
		"enabled": 0,
		"theme": "cute", //Change the default to "default" if a non-cutesy one is added
		"style": "bordered",
		"size": "medium",
		"commands": ({ }),
	]),
	"boss": ([
		"enabled": 0,
		"initialhp": 1000,
		"initialboss": 279141671, //Mustard Mine himself. Note that if this ID isn't an available voice (see http_request), it'll actually be rejected as invalid.
		"hpgrowth": 0, //0 for stable, positive numbers for fixed growth, -1/-2/-3 for overkill/static
		"autoreset": 1, //Reset at end of stream automatically. There'll be a mod command to reset regardless.
		"giftrecipient": 0,
		"selfheal": 1, //0 lets current boss damage themselves (phoenix mode), 1 self-heal up to current max HP, 2 self-heal unlimited
	]),
	"crown": ([
		"enabled": 0,
		"initialprice": 5000,
		"initialholder": 279141671, //As above, default to Mustard Mine
		"increase": 1000,
		"gracetime": 60,
		"perpersonperstream": 0,
		"wantmonitor": 0,
	]),
	"first": ([
		"first": 0,
		"second": 0,
		"third": 0,
		"last": 0,
		"firstdesc": "Claim this reward to let everyone know that you are the first one here!",
		"seconddesc": "Missed out on being first? Claim this reward to let everyone know that you came second!",
		"thirddesc": "Look, we know it's hard to be the best. But you can at least come in third...",
		"lastdesc": "You're not first, but maybe you can be last?",
		"checkin": 0,
	]),
]);

constant rps_commands = ([
	"default": ([
		"rock": "{username} throws a closed fist - ROCK!",
		"paper": "{username} opens a flat palm - PAPER!",
		"scissors": "{username} shows two fingers - SCISSORS!",
	]),
	"halloween": ([
		"knife": "Enjoy the stabbing, {username}!",
		"pumpkin": "{username} is now wearing a pumpkin like a suit of armor!",
		"ghost": "Rest in peace, {username}, you are now a ghost.",
	]),
	"cute": ([
		"rock": "Omnomnom! Rock candy is the best lithography, {username}!",
		"paper": "{username} starts folding paper for maximum cuteness.",
		"scissors": "Ready to open a bag of candy, {username} takes up the scissors!",
	]),
]);
constant rps_extra_commands = ([
	"mergeparty": #{
		#access "mod"
		chan_monitors("%monitorid%", "merge", "off", "", "") {
			"Add yourselves to the competition with %commands%"
			$rpsactive$ = "1"
			$%vargroup%:avatar$ = "0"
			setvar("*rpsparty", "clear", "") ""
		}
		{
			#delay 60
			"The fight is on!"
			$rpsactive$ = "0"
			chan_monitors("%monitorid%", "merge", "contest", "", "") {
				{#delay 5 "And the winner is..... {winner}!"}
				{
					#delay 10
					//And back to BRB screen mode where everyone can play as much as they like.
					$rpsactive$ = "2"
					$%vargroup%:avatar$ = "0"
					setvar("*rpsparty", "clear", "") ""
				}
			}
		}
	#},
	"mergeshake": #{
		#access "mod"
		#visibility "hidden"
		chan_monitors("%monitorid%", "shake", "", "", "") "Time to shake things up a bit!"
	#},
]);

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo); //Should there be non-privileged info shown?
	//TODO: If broadcaster hasn't granted channel:manage:redemptions, have an auth button
	mapping vox = G->G->DB->load_cached_config(req->misc->channel->userid, "voices");
	mapping voices = mkmapping(indices(vox), values(vox)->name); //Don't need all the other info, id/name is enough
	//Loading the voices page ensures that the bot's default voice is available. Even if
	//this streamer hasn't, that voice is available as a default boss.
	string defvoice = G->G->irc->id[0]->?config->?defvoice;
	if (defvoice && !voices[defvoice]) {
		mapping bv = G->G->DB->load_cached_config(0, "voices");
		if (bv[defvoice]) voices[defvoice] = bv[defvoice]->name;
	}
	string scopes = !req->misc->session->fake && ensure_bcaster_token(req, "channel:manage:redemptions");
	if (scopes && (int)req->misc->session->user->id != req->misc->channel->userid) scopes = "bcaster";
	return render(req, (["vars": ([
		"ws_group": "", "sections": sections, "voices": voices,
		"rewardscopes": scopes || "",
		"rps_extra_commands": indices(rps_extra_commands),
	])]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;} //Is this redundant with anything else?
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
object boolify(mixed val) {return val ? Val.true : Val.false;}

__async__ void rpsrebuild(object channel) {
	mapping game = await(G->G->DB->load_config(channel->userid, "minigames"))->rps;
	mapping cfg = sections->rps | game;
	array|zero orig = game->commands + ({ });
	//If any command has actually been deleted elsewhere, discard the fact that we have it
	foreach (cfg->commands, string cmdname) if (!channel->commands[cmdname]) game->commands -= ({cmdname});
	mapping commands = rps_commands[cfg->theme] || ([]);
	array unwanted = cfg->commands - indices(commands) - indices(rps_extra_commands);
	foreach (unwanted, string cmdname) {
		G->G->cmdmgr->update_command(channel, "", cmdname, "");
		game->commands -= ({cmdname});
	}
	foreach (commands; string cmdname; string response) {
		if (channel->commands[cmdname]) continue; //If you already have the command, even if unrelated, ignore it.
		G->G->cmdmgr->update_command(channel, "", cmdname, sprintf(#{
			test ("$rpsactive$") {
				if ("$*rpsparty$" == "1") ""
				else {
					chan_monitors(%q, "add", "avatar", "{username}", "avatar:{uid}/%s/vip{@vip}/mod{@mod}") %q
					if ("$rpsactive$" == "2") ""
					else $*rpsparty$ = "1"
				}
			}
		#}, cfg->monitorid, cmdname, response), (["language": "mustard"]));
		if (!has_value(game->commands || ({ }), cmdname)) game->commands += ({cmdname});
	}
	if (channel->expand_variables("$rpsactive$") == "") channel->set_variable("rpsactive", "2", "set");
	if (game->commands != orig) {
		await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->rps = game;});
		send_updates_all(channel, "");
	}
}

void wscmd_rpsrebuild(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {rpsrebuild(channel);}

__async__ void wscmd_rpsaddcmd(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string cmdname = msg->command;
	string mustard = rps_extra_commands[cmdname];
	if (!mustard) return;
	mapping game = await(G->G->DB->load_config(channel->userid, "minigames"))->rps;
	mapping cfg = sections->rps | game;
	mapping monitors = G->G->DB->load_cached_config(channel->userid, "monitors");
	mapping info = monitors[game->monitorid] || ([]);
	array commands = sort(indices(rps_commands[cfg->theme] || ([])));
	string cmdnames = sizeof(commands) ? sprintf("!%s, !%s, or !%s", @commands) : "the appropriate commands";
	G->G->cmdmgr->update_command(channel, "", cmdname, replace(mustard, ([
		"%monitorid%": game->monitorid,
		"%vargroup%": info->varname || "pileA",
		"%commands%": cmdnames,
	])), (["language": "mustard"]));
	if (!has_value(game->commands || ({ }), cmdname)) game->commands += ({cmdname});
	await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->rps = game;});
	send_updates_all(channel, "");
}

__async__ void update_rps(object channel, mapping game) {
	if (!game->enabled) {
		foreach (m_delete(game, "commands") || ({ }), string cmdname) G->G->cmdmgr->update_command(channel, "", cmdname, "");
		if (string nonce = m_delete(game, "monitorid")) {
			G->G->websocket_types->chan_monitors->delete_monitor(channel, nonce);
		}
		await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->rps = game;});
		send_updates_all(channel, "");
		return;
	}
	mapping cfg = sections->rps | game;
	mapping monitors = G->G->DB->load_cached_config(channel->userid, "monitors");
	mapping info = monitors[game->monitorid];
	int xsize = (["small": 50, "medium": 75, "large": 150])[cfg->size] || 75;
	string wantalpha = cfg->style == "overlay" ? "0" : "100"; //In overlay mode, walls and bg are transparent
	if (!info) { //Most likely this will be because game->monitorid is absent, but if you go delete the monitor, it can get recreated here
		[game->monitorid, info] = G->G->websocket_types->chan_monitors->create_monitor(channel, ([
			"type": "pile",
			"label": "Rock-Paper-Scissors",
			"behaviour": "Floating",
			"bouncemode": "Merge",
			"addmode": "Explicit only",
			"bgcolor": "#BEFEFA", "bgalpha": wantalpha,
			"wallcolor": "#0051a8", "wallalpha": wantalpha,
			"wall_top": "100",
			"wall_left": "100",
			"wall_right": "100",
			"wall_floor": "100",
			"things": ({([
				"id": "avatar",
				"images": ({ }),
				"shape": "",
				"xsize": xsize,
			])}),
                ]));
		await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->rps = game;});
	} else {
		int changed = 0;
		int idx = search(info->things->id, "avatar");
		if (idx == -1) {
			changed = 1;
			info->things += ({([
				"id": "avatar",
				"images": ({ }),
				"shape": "",
				"xsize": xsize,
			])});
		} else {
			mapping thing = info->things[idx];
			if (thing->xsize != xsize) {changed = 1; thing->xsize = xsize;}
		}
		if (info->bgalpha != wantalpha) {info->bgalpha = wantalpha; changed = 1;}
		if (info->wallalpha != wantalpha) {info->wallalpha = wantalpha; changed = 1;}
		if (changed) {
			await(G->G->DB->save_config(channel->userid, "monitors", monitors));
			G->G->websocket_types->chan_monitors->send_updates_all(channel, game->monitorid);
			G->G->websocket_types->chan_monitors->update_one(channel, "", game->monitorid);
		}
	}
	rpsrebuild(channel);
}

__async__ void reset_boss(object channel, mapping|void cfg) {
	if (!cfg) cfg = sections->boss | await(G->G->DB->load_config(channel->userid, "minigames"))->boss;
	channel->set_variable("bossdmg", "0", "set");
	channel->set_variable("bossmaxhp", (string)cfg->initialhp, "set");
	mapping user = await(get_user_info(cfg->initialboss));
	channel->set_variable("bossname", user->display_name, "set");
	channel->set_variable("bossavatar", user->profile_image_url, "set");
}

__async__ void update_boss(object channel, mapping game) {
	if (!game->enabled) {
		if (string nonce = m_delete(game, "monitorid")) {
			G->G->websocket_types->chan_monitors->delete_monitor(channel, nonce);
			await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->boss = game;});
		}
		if (channel->commands->slayboss) G->G->cmdmgr->update_command(channel, "", "slayboss", "");
		return;
	}
	mapping cfg = sections->boss | game;
	mapping vox = G->G->DB->load_cached_config(channel->userid, "voices");
	if (!vox[(string)game->initialboss]) {
		string defvoice = G->G->irc->id[0]->?config->?defvoice;
		werror("Invalid initial boss %O resetting to %O\n", game->initialboss, defvoice);
		game->initialboss = (int)defvoice;
		await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->boss = game;});
	}
	mapping mon = G->G->DB->load_cached_config(channel->userid, "monitors");
	if (!mon[game->monitorid]) { //Most likely, it either exists and is valid or doesn't exist (game->monitorid is null), but if the monitor is deleted, recreate it on next poke
		//Note that the boss's current HP is max HP minus damage, and is not directly tracked.
		await(reset_boss(channel, cfg));
		[game->monitorid, mapping info] = G->G->websocket_types->chan_monitors->create_monitor(channel, ([
			"type": "goalbar", "varname": "bossdmg",
			"label": "Bit Boss",
			"format": "hitpoints",
			"lvlupcmd": "slayboss",
			"bit": 1, "tip": 1,
			"sub_t1": 500, "sub_t2": 1000, "sub_t3": 2500,
			"kofi_dono": 1, "kofi_member": 1, "kofi_shop": 1,
			"fw_dono": 1, "fw_member": 1, "fw_shop": 1, "fw_gift": 1,
			"thresholds": "$bossmaxhp$ 1",
			"text": "$bossavatar$ $bossname$",
			"font": "Lexend", "fontsize": "30",
			"fillcolor": "#ff0000", "barcolor": "#ffffdd", "color": "#000000", "altcolor": "#000000",
			"borderwidth": "4", "bordercolor": "#00ffff",
			"boss_selfheal": game->selfheal, "boss_giftrecipient": game->giftrecipient,
		]));
		await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->boss = game;});
	}
	await(G->G->DB->mutate_config(channel->userid, "monitors") { //TODO: Only do this if one of these two fields changed
		mapping mon = __ARGS__[0][game->monitorid]; if (!mon) return;
		mon->boss_selfheal = game->selfheal; mon->boss_giftrecipient = game->giftrecipient;
	});
	if (!channel->commands->slayboss) G->G->cmdmgr->update_command(channel, "", "slayboss", #"
		#access \"none\"
		#visibility \"hidden\"
		\"Congratulations to {from_name} for defeating Boss $bossname$!!\"
		chan_minigames(\"boss\", \"slay\") $bossmaxhp$ = \"{newhp}\"
		$bossdmg$ = \"0\"
		uservars(\"\", \"{from_name}\") {
			$bossavatar$ = \"{avatar}\"
			$bossname$ = \"{name}\"
			if (\"{uid}\" == \"0\") $bossname$ = \"{from_name}\"
			else $bossname$ = \"{name}\"
		}
		", (["language": "mustard"]));
	//Or should this be flipped on its head - the reset command does all the work, and other
	//ways to reset just trigger the command?
	if (!channel->commands->resetboss) G->G->cmdmgr->update_command(channel, "", "resetboss", #"
		#access \"mod\"
		#visibility \"hidden\"
		chan_minigames(\"boss\", \"reset\") \"Boss has been reset.\"
		", (["language": "mustard"]));
}

void wscmd_resetboss(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	reset_boss(channel);
}

__async__ void wscmd_dealdamage(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = sections->boss | await(G->G->DB->load_config(channel->userid, "minigames"))->boss;
	if (!cfg->monitorid) return;
	string username = random("Rosuav MustardMine LoudLotus AnAnonymousCheerer AnAnonymousGifter" / " ");
	werror("[%O] Dealing 100 bit boss damage as %O\n", channel, username);
	G->G->goal_bar_advance(channel, cfg->monitorid, (["user": username]), 100);
}

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
		if (channel->commands->retrievecrown) G->G->cmdmgr->update_command(channel, "", "retrievecrown", "");
		if (string nonce = m_delete(game, "monitorid")) {
			G->G->websocket_types->chan_monitors->delete_monitor(channel, nonce);
			await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->crown = game;});
		}
		//No other config changes are done. The deletion of the reward will (asynchronously)
		//result in other info getting cleaned up, but we broadly don't need to take action.
		return;
	}
	mapping cfg = sections->crown | game;
	mapping vox = G->G->DB->load_cached_config(channel->userid, "voices");
	if (!vox[(string)game->initialholder]) {
		string defvoice = G->G->irc->id[0]->?config->?defvoice;
		werror("Invalid initial crown holder %O resetting to %O\n", game->initialholder, defvoice);
		game->initialholder = (int)defvoice;
		await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->crown = game;});
	}
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
		"is_global_cooldown_enabled": boolify(cfg->gracetime), "global_cooldown_seconds": cfg->gracetime,
		"is_max_per_stream_enabled": boolify(!cfg->gracetime), "max_per_stream": !cfg->gracetime,
		"is_max_per_user_per_stream_enabled": boolify(cfg->perpersonperstream), "max_per_user_per_stream": cfg->perpersonperstream,
	]);
	await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid + "&id=" + game->rewardid,
		(["Authorization": channel->userid]),
		(["method": "PATCH", "json": changes])));
	await(G->G->DB->mutate_config(channel->userid, "dynamic_rewards") {
		mapping rwd = __ARGS__[0][game->rewardid];
		if (!rwd) rwd = __ARGS__[0][game->rewardid] = ([
			"basecost": 0, "availability": "{online}",
			"prompt": "Seize the crown for yourself! The crown is currently held by $crownholder:name$, who was the last person to take it.",
		]);
		//The formula magically captures the resultant cost in a variable.
		//This might be a bit backwards; maybe it'd be better to not change the cost with the formula,
		//but instead bind the cost to $crownholder:cost$, and have the !seizecrown command change that
		//variable. For now, sticking to the dynrewards system.
		rwd->formula = "@=\"crownholder:cost\" = (PREV + " + game->increase + ")";
	});
	if (!channel->commands->seizecrown) G->G->cmdmgr->update_command(channel, "", "seizecrown", #"
		#access \"none\"
		#visibility \"hidden\"
		#redemption \"" + game->rewardid + #"\"
		try chan_pointsrewards(\"{rewardid}\", \"fulfil\", \"{redemptionid}\") \"\"
		catch \"\"
		if (\"{uid}\" == \"$crownholder:uid$\") \"You already hold the crown, {username} - good job wasting your points.\"
		else \"Congratulations to {username} for successfully claiming the crown from $crownholder:name$! You will retain this title until someone else seizes it from you...\"
		//In case the person has renamed/changed avatar, update these even if you already held the crown.
		$crownholder:uid$ = \"{uid}\"
		$crownholder:name$ = \"{username}\"
		uservars(\"\", \"{uid}\") $crownholder:avatar$ = \"{avatar}\"
		", (["language": "mustard"]));
	G->G->cmdmgr->update_command(channel, "", "retrievecrown", #"
		#access \"mod\"
		#visibility \"hidden\"
		uservars(\"crownholder\", \"" + game->initialholder + #"\") {
			$crownholder:name$ = \"{name}\"
			$crownholder:uid$ = \"{uid}\"
			$crownholder:avatar$ = \"{avatar}\"
		}
		try {
			chan_pointsrewards(\"" + game->rewardid + #"\", \"cost\", \"" + cfg->initialprice + #"\") \"\"
		}
		catch \"\"
		\"Crown has been retrieved.\"
		", (["language": "mustard"]));
	if (game->wantmonitor && !game->monitorid) {
		[game->monitorid, mapping info] = G->G->websocket_types->chan_monitors->create_monitor(channel, ([
			"type": "goalbar", "varname": "",
			"label": "Crown Holder",
			"format": "hitpoints", "format_style": "nomaxhp",
			"thresholds": "$crownholder:cost$ 1",
			"text": "0:$crownholder:avatar$ $crownholder:name$",
			"font": "Lexend", "fontsize": "30",
			"fillcolor": "#ff0000", "barcolor": "#ffffdd", "color": "#000000", "altcolor": "#000000",
			"borderwidth": "4", "bordercolor": "#00ffff",
		]));
		await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->crown = game;});
		send_updates_all(channel, "");
	}
	else if (string nonce = !game->wantmonitor && m_delete(game, "monitorid")) {
		G->G->websocket_types->chan_monitors->delete_monitor(channel, nonce);
		await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->crown = game;});
		send_updates_all(channel, "");
	}
}

void wscmd_retrievecrown(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	channel->send((["{username}": channel->display_name]), channel->commands->retrievecrown || "");
}

constant firsts = ([
	"first": ([
		"title": "First!", "cost": 1,
		"claimed": "Congratulations to {username} for being first to claim the reward this stream! Will it be you next time?",
		"response": "Congrats to @{username} for being first!",
	]),
	"second": ([
		"title": "Second!", "cost": 2,
		"claimed": "Congratulations to {username} for managing to claim the reward this stream! Will it be you next time?",
		"response": "And congrats to @{username} for being second!",
	]),
	"third": ([
		"title": "Third...", "cost": 3,
		"claimed": "Well done, well done. It was {username} who managed to be the oh so amazing third place winner.",
		"response": "Good job, @{username}. Third place. We are proud of you.",
	]),
	"last": ([
		"title": "Last?", "cost": 10,
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
	chan_minigames(\"first\", %q) {
		if (\"{shame}\" == \"1\") {
			%q
			chan_pointsrewards(\"{rewardid}\", \"desc\", %q) \"\"
		} else {
			%q
			chan_pointsrewards(\"{rewardid}\", \"desc\", %q) \"\"
		}
	}
";
constant checkin_code = #"
	#access \"none\"
	#visibility \"hidden\"
	#redemption \"%s\"
	try {
		chan_pointsrewards(\"{rewardid}\", \"fulfil\", \"{redemptionid}\") \"\"
	}
	catch \"Unexpected error: {error}\"
	$*checkins$ += \"1\"
	\"Thank you for signing the guest book for today, {username}! You have signed it $*checkins$ times.\"
";

__async__ void update_first(object channel, mapping game) {
	//First (pun intended), some validation. Sequential rewards depend on each other.
	//(Note that "checkin" doesn't require "first" or any others.)
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
						//Note that you can't actually create a paused reward; instead, we create
						//the reward and then immediately pause it.
						//"is_paused": which == "first" ? Val.false : Val.true,
					]), "return_errors": 1])));
				if (resp->data && sizeof(resp->data)) game[which + "rwd"] = resp->data[0]->id; //Otherwise what? Try again next time?
				if (which != "first") await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
					+ channel->userid + "&id=" + game[which + "rwd"],
					(["Authorization": channel->userid]),
					(["method": "PATCH", "json": (["is_paused": Val.true]), "return_errors": 1])));
				changed = 1;
			}
			if (!channel->commands["rwd" + which]) {
				string code = sprintf(first_code, game[which + "rwd"] || "", which,
					"Hey, hey, no fair, {username}! You already claimed a reward this stream. Shame is yours...",
					"Shame is upon {username} for being greedy and claiming more than one reward. Let's play nicely next time.",
					desc->response, desc->claimed);
				G->G->cmdmgr->update_command(channel, "", "rwd" + which, code, (["language": "mustard"]));
			}
		} else {
			if (string id = m_delete(game, which + "rwd")) {
				await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid + "&id=" + id,
					(["Authorization": channel->userid]),
					(["method": "DELETE", "return_errors": 1]))); //If the reward's been manually deleted, ignore the failure
				changed = 1;
			}
			if (channel->commands["rwd" + which]) G->G->cmdmgr->update_command(channel, "", "rwd" + which, "");
		}
	}
	if (game->checkin) {
		if (!game->checkinrwd) {
			mapping resp = await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid,
				(["Authorization": channel->userid]),
				(["json": ([
					"title": "Check-in!",
					"cost": 1,
					"prompt": "Daily check-in! Non-competitive.",
					"is_max_per_user_per_stream_enabled": Val.true, "max_per_user_per_stream": 1,
				]), "return_errors": 1])));
			if (resp->data && sizeof(resp->data)) game->checkinrwd = resp->data[0]->id; //As above, otherwise what?
			changed = 1;
		}
		if (!channel->commands->rwdcheckin) {
			string code = sprintf(checkin_code, game->checkinrwd || "");
			G->G->cmdmgr->update_command(channel, "", "rwdcheckin", code, (["language": "mustard"]));
		}
	} else {
		if (string id = m_delete(game, "checkinrwd")) {
			await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid + "&id=" + id,
				(["Authorization": channel->userid]),
				(["method": "DELETE", "return_errors": 1])));
			changed = 1;
		}
		if (channel->commands["rwdcheckin"]) G->G->cmdmgr->update_command(channel, "", "rwdcheckin", "");
	}
	if (changed) {
		await(G->G->DB->mutate_config(channel->userid, "minigames") {__ARGS__[0]->first = game;});
		send_updates_all(channel, "");
	}
}

constant command_description = "Manage stream minigames";
constant builtin_name = "Minigame";
constant builtin_param = ({"/Game/first/boss", "Extra info"});
constant MOCKUP_builtin_param = ({
	"/Game",
	([
		"first": ({"/Reward/first/second/third/last"}),
		"boss": ({"/Action/reset/slay"}),
	]),
});
constant vars_provided = ([
	"{shame}": "1 if user should be shamed for duplicate claiming",
	"{count}": "Number of times the user has checked in (once per stream)",
	"{newhp}": "New boss HP if one just got slain",
]);

//Should this be stored somewhere other than ephemeral memory? If the bot hops, this gets lost, with the (tragic) result
//that people can claim an additional reward that stream without getting shamed for it.
@retain: mapping already_claimed = ([]);
__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	if (cfg->simulate) return ([]); //This doesn't really simulate well. There are better ways of testing.
	mapping game = await(G->G->DB->load_config(channel->userid, "minigames"))[param[0]];
	if (!game) return ([]); //Including if you mess up the keyword
	if (param[0] == "first") {
		int seen = 0;
		foreach ("first second third last" / " ", string which) {
			if (which == param[1]) seen = 1;
			else if (string id = seen && game[which + "rwd"]) {
				//Okay. We've found the next active reward. Enable it!
				await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
					+ channel->userid + "&id=" + id,
					(["Authorization": channel->userid]),
					(["method": "PATCH", "json": (["is_paused": Val.false]), "return_errors": 1])));
				break;
			}
		}
		if (!already_claimed[channel->userid]) already_claimed[channel->userid] = ([]);
		if (already_claimed[channel->userid][(int)person->uid]) return (["{shame}": "1"]);
		already_claimed[channel->userid][(int)person->uid] = time();
		return (["{shame}": "0"]);
	} else if (param[0] == "boss") {
		mapping cfg = sections->boss | game;
		if (param[1] == "reset") {
			await(reset_boss(channel, cfg));
			return ([]);
		} else if (param[1] == "slay") {
			int hpgrowth = cfg->hpgrowth;
			switch (hpgrowth) {
				case -1:
					//Overkill. The growth is the excess damage. Due to asynchronicity,
					//multiple damage events in very quick succession may cause weird
					//issues. CHECK ME.
					return (["{newhp}": (string)(
						(int)channel->expand_variables("$bossmaxhp$")
						+ (int)channel->expand_variables("$bossdmg$")
						- (int)channel->expand_variables("$bossmaxhp$")
					)]);
					break;
				case -2:
					//Static. Reset the boss to original HP.
					return (["{newhp}": (string)cfg->initialhp]);
				case -3:
					//Static + overkill. Reset to original, then apply overkill damage.
					//As in regular overkill mode, asynchronicity may cause issues.
					return (["{newhp}": (string)(
						cfg->initialhp
						+ (int)channel->expand_variables("$bossdmg$")
						- (int)channel->expand_variables("$bossmaxhp$")
					)]);
				default:
					//Stable or simple increase. Add a fixed value (maybe zero) to the existing HP.
					return (["{newhp}": (string)((int)channel->expand_variables("$bossmaxhp$") + hpgrowth)]);
			}
		}
	}
	return ([]);
}

@hook_channel_offline: __async__ void disconnected(string channel, int uptime, int userid) {
	m_delete(already_claimed, userid);
	mapping games = await(G->G->DB->load_config(userid, "minigames"));
	//Disable the second and subsequent rewards until First gets claimed
	if (mapping game = games->first) foreach ("first second third last" / " ", string which) {
		if (string id = game[which + "rwd"]) {
			await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
				+ userid + "&id=" + id,
				(["Authorization": userid]),
				(["method": "PATCH", "json": ([
					"prompt": game[which + "desc"] || sections->first[which + "desc"],
					"is_paused": which == "first" ? Val.false : Val.true,
				]), "return_errors": 1])));
		}
	}
	if (mapping game = games->boss) {
		if (game->autoreset) reset_boss(G->G->irc->id[userid], sections->boss | game);
	}
}

protected void create(string name) {::create(name);}

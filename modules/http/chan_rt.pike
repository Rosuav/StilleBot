inherit http_websocket;

constant markdown = #{# Respawn Technician

A great hero roams the world, destroying evil, saving princesses, rescuing the needy, and becoming wealthy in the process. His story is told
by kings and peasants alike, for his deeds are many and his accomplishments great.

You are not that hero. You are the technician who operates his respawn chamber.

When the hero dies, he comes back to life at the nearest respawn chamber, slightly weakened but ready to try again. In the interests of the
realm at large, you must respawn him, again, and again, and again!

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

* Unlocking a new trait starts it at random()/2-0.25 for a very weak initial impact. It's nearly impossible to completely remove a trait once
  it's been unlocked, though you can certainly overpower it with others.

Two modes: 2D and Linear
- In 2D mode, the hero's path branches periodically. He looks down each path, and makes a choice. But he mostly still moves left to right.
- In Linear mode, the branches are shown as doorways. He peeks into the door, and makes a choice. He moves exclusively left to right.

Encounters get spawned in at the RHS and there'll be a few of them visible ahead of the hero's current location.
- Boss. You can't walk past this, though you can back away and take the opposite choice from the most recent branch. You'll find the boss
  again at some point, and new content is only unlocked by defeating bosses. Regular enemies have a soft level cap until boss defeated.
  - NOTE: Block boss spawn if (a) there's a boss visible on screen, either defeated or undefeated; or (b) when the hero has retreated, until a
    branch gets spawned.
- Item. Could be any one of these. The effectiveness given is for an item that spawns at exactly the current base level. For items spawned by
  viewer generosity, they will be spawned at max level instead.
  - Flash of Inspiration. It's a flashbang grenade, and it gives 1000 XP.
  - Healing. Restore 50% of HP.
  - Courage. If there are any retreating penalties, they are removed; otherwise, the hero gets a courage bonus for the next 10 squares.
  - Stat. A potion of STR gives +5 STR for the next 10 squares. Any stat can spawn, except CHA (because it's useless) and CON (because it's weird to gain and lose HP).
  - Stoneskin. 25% damage reduction for 10 squares. Should feel like getting a CON potion.
#};

constant styles = #"
#pathway {
	display: flex;
	flex-direction: row-reverse;
	overflow: hidden;
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
	/* TODO: Give new messages (divs inside #messages) a background that fades? */
	border: 1px solid grey;
	padding: 0 8px;
}
";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = await(G->G->DB->load_config(req->misc->channel->userid, "respawn"));
	if (req->variables->view) {
		if (cfg->nonce != req->variables->view) return 0; //404 if you get the nonce wrong
		return render_template("monitor.html", ([
			"vars": (["ws_type": ws_type, "ws_group": req->variables->view + "#" + req->misc->channel->userid]),
			"styles": styles,
		]));
	}
	//TODO: Non-mod page with stats, and maybe voting (but only if logged in)
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	return render(req, (["vars": (["ws_group": ""]), "styles": styles]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "";}
__async__ mapping get_chan_state(object channel, string grp, string|void id, string|void type) {
	return (["gamestate": await(G->G->DB->load_config(channel->userid, "respawn"))]);
}

@"is_mod": __async__ void wscmd_save_game(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!mappingp(msg->gamestate)) return;
	await(G->G->DB->save_config(channel->userid, "respawn", msg->gamestate));
}

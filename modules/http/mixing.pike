/* Pseudo-game concept.

I'm writing this up as if it's a game to be played, but the purpose isn't primarily to be a fun game,
it's to be a demonstration. The principles on which this works are the same as the principles which
underpin a lot of internet security, and I'm hoping this can be a fun visualization.


Player roles:
* Spymaster - knows the secret message, must transmit it safely
* Contact - doesn't know who anyone is, must select the correct message
* Agents of Chaos - trying to deceive the contact into selecting a false message
* Spectators - not participating in the game, unable to interfere

Game phases:
0) recruit - players start as spectators and can assign themselves to roles. Whoever created the game will
   be shown as host, and can advance to the next phase. Anyone joining the game in this phase is an Agent of
   Chaos by default, can choose to be Spymaster or Contact if the roles are available, can choose to become
   Spectator. On phase advancement, if no Spymaster/Contact is assigned, one will be randomly selected from
   the Agents. (And if there's only one person involved, error out.) NOTE: After the recruitment phase, role
   selection is locked in, and anyone freshly joining the game is a spectator.
1) mixpaint - all players (spectators included) may mix paints, save them to their personal collections, and
   (non-spectators only) publish one pot.
2) writenote - players may see their saved paints but not edit them. Spymaster is shown one message and may
   choose a paint to mark it with. Contact sits tight and gets some suitably nerve-wracking flavour text.
   Chaos Agents are shown one message each and may choose a paint to mark it with. The game synthesizes some
   fake notes to pad to a predetermined number, guaranteeing to not collide with hex color of any published
   note. (It's entirely possible for two Chaos Agents to post identical note colours.)
3) readnote - everything is now read-only. Contact browses the notes. Click note to view larger. Click paint
   to compare, or click "Follow instructions" (w/ confirmation) to conclude the game, successfully or not.
   Everyone else just watches; the Contact's state is all now global to the game.
4) gameover - report whether the Contact picked the Spymaster's note.


Crucial: Paint mixing. Every paint pot is identified on the server by a unique ID that is *not* defined
by its composition. (For convenience, published pots use one namespace, and personal pots are namespaced
to the owner.) When you attempt a mix, you get back a new paint pot, and you (but only you) can see
that it's "this base plus these pigments". Everyone else just sees the publisher and hex color (if it's
published, otherwise they don't see it at all). Any existing paint pot can be used as a base, or you can
use the standard beige base any time.
- TODO: Show "base plus pigments" for personal pots, prob not for your published one though

Essential: Find a mathematical operation which takes a base and a modifier.
* Must be transitive: f(f(b, m1), m2) == f(f(b, m2), m1)
* Must be repeatable: f(f(b, m1), m1) != f(b, m1) up to 3-6 times (it's okay if x*5 and x*6 are visually similar)
* Must "feel" like it's becoming more like that colour (subjective)
* Must not overly darken the result.
The current algorithm works, but probably won't scale to 3-5 pigments without going ugly brown.
Ideally I would like each key to be able to be 3-5 pigments at 1-3 strength each, totalling anywhere from
6 to 30 pigment additions. Maybe add a little bit to the colour each time it's modified, to compensate
for the darkening effect of the pigmentation?

Note: If both sides choose 3-5 pigments at random, and strengths 1-3 each, this gives about 41 bits of key length.
Not a lot by computing standards, but 3e12 possibilities isn't bad for a (pseudo-)game.

Current algorithm uses fractions, which allows efficient and 100% reproducible colour creation (assuming
arbitrary precision rational support - see fractions.Fraction in Python, Gmp.mpq in Pike). Do not ever
reveal the actual rational numbers that form the resultant colour, as factors may leak information, but it
would be possible to retain them in that form internally.

(Note that real DHKE uses modulo arithmetic to keep storage requirements sane, so it doesn't have to worry about
rounding or inaccuracies.)
*/
inherit http_websocket;

constant markdown = #"# Diffie Hellman Paint Mixing

<style>
.swatch {display: inline-block; width: 80px; height: 60px; border: 1px solid black;}
.large {width: 200px; height: 150px;}
.label {display: inline-block; height: 90px;}
.design {display: flex; flex-wrap: wrap; margin: 8px 0; gap: 5px;}
$$swatch_colors$$
.colorpicker {
	display: flex;
	margin: 8px;
	gap: 8px;
	flex-wrap: wrap;
}
.colorpicker div {cursor: pointer;}
dialog {max-width: 1100px;}
section {border: 1px solid black; margin: 4px; padding: 4px;}
dialog section {border: none; margin: 0; padding: 0;} /* Don't touch sections in dialogs */
h4 {margin: 0;}
#loginbox {width: 40em; border: 2px solid yellow; background: #fff8ee; padding: 5px;}
.hidden {display: none;}
#savepaint {
	margin: 10px;
	border: 1px solid blue;
	padding: 5px;
	background: #eeeeff;
	max-width: 400px;
}
article {display: none;}
</style>
<style id=phase>article#paintmix {display: block;}</style>

## Situation Report
Coded messages are no longer safe. Your enemies have discovered your code, and can both read your messages
and write fake messages of their own. You need a way to send your contact one crucial instruction which
will allow you to share a new code. How? There is a public message board on which anyone may leave a note,
so you must leave a message there, with some proof that it is truly from you.

[Mission Briefing](:.infobtn data-dlg=sitrep) [The Secret Trick](:.infobtn data-dlg=secret) [How it really works](:.infobtn data-dlg=dhke)

To participate in games, you'll need to confirm your Twitch account name. Otherwise, feel free to play with the paint mixer,
though you can't save or publish your paints.<br>
[Twitch login](:.twitchlogin)
{: #loginbox .hidden}

<span id=gamedesc></span>
[Start new game](:#newgame .hidden .infobtn data-dlg=newgamedlg)

> ## Recruitment
>
> Declare your allegiance!
>
> Game host: <span id=gamehost><!-- name --></span>
>
> * Spymaster: <span id=spymaster><!-- name or 'claim role' button --></span>
> * Contact: <span id=contact><!-- name or 'claim role' button --></span>
> * Agents of Chaos: [Join](:#joinchaos) <span id=chaos><!-- list of names --></span>
> * Spectators: [Join](:#joinspec) <span id=spectators><!-- list of names --></span>
> <!-- #joinchaos and #joinspec get disabled if you're in that role -->
>
{: tag=article #recruit}

<!-- -->
> ## Paint mixing
>
> Welcome to the paint studio. Pick any pigment to mix it into your paint. To start fresh, pick a base color from any available.
>
> > #### Available base colors
> > Choose one of these to start a fresh paint mix with this as the base.
> > <div id=basepots class=colorpicker><div class=swatch style=\"background: #F5F5DC\" data-id=0>Standard Beige</div></div>
> {: tag=section}
> 
> <!-- -->
> > #### Pigments (click to add)
> > <div id=swatches class=colorpicker></div>
> {: tag=section}
> 
> <!-- -->
> > #### Current paint
> > <div id=curpaint class=design><div class=swatch style=\"background: #F5F5DC\">Base: Standard Beige</div></div>
> > <div id=curcolor class=\"swatch large\" style=\"background: #F5F5DC\">Resulting color</div>
> > > Save this paint to your personal collection?<br>
> > > <label>Name: <input name=paintid></label> (must be unique)<br>
> > > <button type=submit>Save</button>
> > {: tag=form #savepaint autocomplete=off}
> >
> > <!-- -->
> > <button type=button id=publishpaint>Publish this paint</button>
> {: tag=section}
>
> <!-- -->
{: tag=article #paintmix}

<!-- -->
> ## Notes!
>
> Oh, I see you've got one too.
{: tag=article #writenote}

<!-- -->
> ## The Message Board
>
> Far too many notes for my taste, but one of them is for you.
{: tag=article #readnote}

<!-- -->
> ## Game Over
>
> Did you win? Did you lose? Did you learn anything?
{: tag=article #gameover}

<!-- -->
> ### Start new game
> Leave this mayhem and go to a brand new show?
>
> [Do it. We shall prevail.](:#startnewgame) [On second thoughts...](:.dialog_close)
{: tag=dialog #newgamedlg}

<!-- -->
> ### Situation report
> Your mission: Share a message with your contact, such that no enemy can forge a similar message.
>
> The Diffie Hellman Paint Company has a public mixing facility. Starting with an ugly beige, you can add
> any pigments you like, selected from seventeen options (various secondary or tertiary colours), in any of
> three strengths (a spot, a spoonful, or a splash).
>
> You can leave a paint pot (with your name on it and the colour daubed on the label) at the mixer; your
> contact will see it, but so will everyone else.
>
> Notes on the board can have painted mastheads. It's easy to compare masthead colours to any pot you
> have - \"identical\", \"similar\", \"different\".
>
> With zero private communication, communicate safely.
>
> [Got it! Let's get to work.](:.dialog_close)
{: tag=dialog #sitrep}

<!-- -->
> ### The Secret Trick
>
> As with everything involving secrecy, there's a trick to it. If you add the same pigments to the base
> color, you will always get the same result - even if you add them in a different order.
>
> So with that in mind, here's what you can do: Choose *and remember*
> any combination of pigments. Mix this and leave it under your name. Your contact does likewise.
> 
> Then you pick up your contact's paint pot, and mix in the same pigments that you put into your own; contact
> does likewise with yours. You may not know what anyone else's pigment choices are, but you know your own.
>
> You and your contact are now in possession of identically coloured pots of paint (which you will not share),
> and can use them to communicate reliably. Mark your message with this paint, and your contact can compare;
> but nobody can forge a message like this without knowing your pigment choices.
>
> [Ah ha! So it IS possible!](:.dialog_close)
{: tag=dialog #secret}

<!-- -->
> ### Diffie-Hellman Key Exchange
>
> Unsurprisingly, this entire \"game\" is based on a real-world security technique. It was invented by Diffie,
> Hellman, and Merkle (sorry Merkle, your name deserves to be on this, but everyone calls it DH), and the way
> it's used in computing security involves numbers rather than paint, but the principle is very similar.
>
> Starting with a standard (and well-known) base, each party makes a specific change to it, and publishes the
> result. You swap these results, and apply your own change to the other person's result. Just like with the
> paint, this is guaranteed to give the same final value for both of you, but for an eavesdropper to reconstruct
> this value would be highly impractical.
>
> [More information can be found on Wikipedia](https://en.wikipedia.org/wiki/Diffie%E2%80%93Hellman_key_exchange)
> or on various computing security blogs.
>
> [And that's how HTTPS works.](:.dialog_close)
{: tag=dialog #dhke}

<!-- -->
> ### Start new paint mix
>
> Confirm that you want to discard your current paint mix and start a new one using this base color:
>
> <div id=bigsample class=\"swatch large\" style=\"background: #F5F5DC\">Standard Beige</div></div>
>
> [Yes, start mixing!](:#startpaint) [Cancel](:.dialog_close)
{: tag=dialog #freshpaint}

<!-- -->
> ### Add color to paint
> Chosen color: <span id=colorname></span><br>
> <span id=colordesc></span>
> <div id=colorpicker class=colorpicker></div>
> [Cancel](:.dialog_close)
{: tag=dialog #colordlg}

<!-- -->
> ### Publish your paint
> NOTE: You can only publish one paint. Is this the paint you want to share?
> {: #publishonce}
>
> <div id=publishme class=\"swatch large\" style=\"background: #F5F5DC\"></div></div>
>
> [Publish or perish!](:#publishconfirm) [Wait, I'm not ready...](:.dialog_close #publishcancel)
{: tag=dialog #publishdlg}
";

mapping game_state = ([]);
mapping swatch_colors = ([]);
string swatch_color_style = "";
array swatches = ({ });

constant STANDARD_BASE = ({0xF5, 0xF5, 0xDC});

constant PIGMENTS = ([
	//Primary colors
	"Crimson": ({0xDC, 0x14, 0x3C}), //Red
	"Jade": ({0x37, 0xFD, 0x12}), //Green
	"Cobalt": ({0x1F, 0x45, 0xFC}), //Blue
	//Secondary colors
	"Hot Pink": ({0xFF, 0x14, 0x93}), //Rb
	"Orange": ({0xFF, 0x8C, 0x0A}), //Rg
	"Lawn Green": ({0x9C, 0xFC, 0x0D}), //Gr
	"Spring Green": ({0x03, 0xFA, 0x9A}), //Gb
	"Sky Blue": ({0x57, 0xCE, 0xFA}), //Bg
	"Orchid": ({0xDA, 0x40, 0xE6}), //Br
	//Special colors, not part of the primary/secondary pattern
	"Rebecca Purple": ({0x66, 0x33, 0x99}),
	"Chocolate": ({0x7B, 0x3F, 0x11}),
	"Alice Blue": ({0xF0, 0xF8, 0xFE}),
	"Mint Mus": ({0x99, 0xFD, 0x97}),
	"Bulker": STANDARD_BASE[*] * 2,
	"Charcoal": ({0x44, 0x45, 0x4f}),
	"Beige": STANDARD_BASE,
	"Blood": ({0x7E, 0x35, 0x17}),
]);
constant SWATCHES = ({
	({"Crimson", "It's red. What did you expect?"}),
	({"Jade", "Derived from pulverised ancient artifacts. Probably not cursed."}),
	({"Cobalt", "Like balt, but the other way around"}),
	({"Hot Pink", "Use it quickly before it cools down!"}),
	({"Orange", "For when security absolutely depends on not being able to rhyme"}),
	({"Lawn Green", "Not to be confused with Australian Lawn Green, which is brown"}),
	({"Spring Green", "It's a lie; most of my springs are unpainted"}),
	({"Sky Blue", "Paint your ceiling in this colour and pretend you're outside!"}),
	({"Orchid", "'And Kid' didn't want to participate, so I got his brother instead"}),
	({"Rebecca Purple", "A tribute to Eric Meyer's daughter. #663399"}),
	({"Chocolate", "Everything's better with chocolate."}),
	({"Alice Blue", "Who is more famous - the president or his wife?"}),
	({"Mint Mus", "Definitely not a frozen dessert."}),
	({"Bulker", "Add some more base colour to pale out your paint", 0}),
	({"Charcoal", "Dirty grey for when vibrant colours just aren't your thing"}),
	({"Beige", "In case the default beige just isn't beigey enough for you"}),
	//Special case. Swatched as a vibrant crimson (fresh blood), but for mixing, the actual "Blood" value is used (old blood).
	({"Blood", "This pigment is made from real blood. Use it wisely.", ({0xAA, 0, 0})}),
});
constant STRENGTHS = ({"spot", "spoonful", "splash"});

//Craft some spy-speak instructions. The game is not about hiding information in the
//text, so we provide the text as a fully-randomized Mad Libs system.
constant CODENAMES = "Angel Ape Archer Badger Bat Bear Bird Boar Camel Caribou Cat Chimera Cleric Crab Crocodile"
	" Dinosaur Dog Dragon Druid Dwarf Elephant Elk Ferret Fish Fox Frog Giant Goblin Griffin Hamster Hippo"
	" Horse Hyena Insect Jellyfish Knight Kraken Leech Lizard Minotaur Mole Monkey Mouse Ninja Octopus Ogre"
	" Oyster Pangolin Phoenix Pirate Plant Prism Rabbit Ranger Rat Rhino Rogue Salamander Scarecrow Scorpion"
	" Shark Sheep Skeleton Snake Soldier Sphinx Spider Spirit Squirrel Turtle Unicorn Werewolf Whale Worm Yeti" / " ";
constant ACTIONS = ({
	"proceed as planned",
	"ask what the time in London is",
	"complain that the record was scratched",
	"report the theft of your passport",
	"knock six thousand times",
	"whistle the Blue Danube Waltz",
	"wave your sword like a feather duster",
	"apply for the job",
	"enter the code 7355608",
	"take the red pill",
	"dance",
	"sit down",
	"roll for initiative",
});
constant _MESSAGES = ({
	"Go to {codename} Office and {action}.",
	"Speak with Agent {codename} for further instructions.",
	"At 11:23 precisely, knock fifty-eight times on Mr Fibonacci's door.",
	"Return to HQ at once.",
	"Mrs {codename}'s bakery serves the best beef and onion pies in the city.",
	"Under the clocks, speak with Authorized Officer {codename}.",
	"When daylight is fading, softly serenade Agent {codename}.",
	"Ride the elevator to the 51st floor and {action}. Beware of vertigo.",
	"Join Agent {codename} in Discord. After five minutes, {action}.",
	"Locate the nearest fire station and {action}.",
	"Connect to 203.0.113.34 on port 80.",
	"Proceed to the {codename} theatre in the Arts Centre. At the box office, {action}.", //TODO: Abbreviate (too long, esp w/ action)
	"At the stone circle, find the {codename} and read its inscription.",
	"Tell {codename} the dancing stones are restless. They will give you a van.",
	"Go to Teufort. Find {codename} in RED sewers and {action}.",
	"Meet me in the coffee shop. I will be wearing a {codename} T-shirt.",
	"In a garden full of posies, gather flowers. You will be offered an apple. Refuse it.",
	"Tune in to the classical music station. DJ {codename} will instruct you.",
	"Buy a Mars Bar and eat it on Venus.",
	"Borrow Mr {codename}'s camera. If it takes more than one shot, it wasn't a Jakobs.",
});
constant MESSAGES = _MESSAGES + filter(_MESSAGES, has_value, '{'); //If this doesn't work, just drop the weight increase

Gmp.mpq _mix_part(int|Gmp.mpq base, int modifier) {
	Gmp.mpq effect = 1 - (1 - Gmp.mpq(modifier, 256)) / 5;
	return base * effect;
}

array(Gmp.mpq) mix(array(Gmp.mpq) base, array(int) modifier) {
	return _mix_part(base[*], modifier[*]);
}

string hexcolor(array(Gmp.mpq) color) {
	return sprintf("%02X%02X%02X", @min(((array(int))color)[*], STANDARD_BASE[*]));
}

multiset _messages_used = (<>);
string devise_message() {
	while (1) {
		string msg = replace(random(MESSAGES), ([
			"{codename}": random(CODENAMES),
			"{action}": random(ACTIONS),
		]));
		if (_messages_used[msg]) continue;
		_messages_used[msg] = 1;
		return msg;
	}
}

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	string group = "0";
	string uid = req->misc->session->user->?id;
	mapping state = game_state[req->variables->game];
	if (state && uid) group = uid + "#" + state->gameid;
	else if (uid) group = (string)uid;
	return render(req, ([
		"vars": (["ws_group": group, "swatches": swatches]),
		"swatch_colors": swatch_color_style,
	]));
}

mapping fresh_paint(string basis, array basecolor) {
	return ([
		"definition": basecolor,
		"blobs": ({(["label": "Base: " + basis, "color": hexcolor(basecolor)])}),
		"color": hexcolor(basecolor),
	]);
}

//Websocket groups:
//0 --> Guest account, cannot share, will not see any base other than standard, always on mixer screen
//Other integer --> Logged in, not part of game
//int#str: Logged in, part of game, can share paints, will use mode from game
string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	conn->curpaint = fresh_paint("Standard Beige", STANDARD_BASE);
	if (!stringp(msg->group)) return "Invalid group ID";
	if (msg->group == "0") return 0; //Always okay to be guest
	if (msg->group == (string)conn->session->user->?id) return 0; //Logged in as you, no game
	sscanf(msg->group, "%d#%s", int uid, string game);
	if (uid && uid == (int)conn->session->user->?id && game_state[game]) return 0;
	return "Not logged in";
}

mapping|Concurrent.Future get_state(string|int group, string|void id) {
	mapping state = (["loginbtn": -1, "paints": ({({0, "Standard Beige", hexcolor(STANDARD_BASE)})})]);
	sscanf(group, "%d#%s", int uid, string game);
	if (!uid) state->loginbtn = 1;
	if (!game) return state; //If you're not connected to a game, there are no saved paints.
	mapping gs = game_state[game];
	state->gameid = gs->gameid;
	state->phase = gs->phase;
	state->paints = map(sort(indices(gs->published_paints))) {[int id] = __ARGS__;
		return ({id, gs->published_paints[id][0], hexcolor(gs->published_paints[id][1])});
	};
	mapping saved = gs->saved_paints[uid] || ([]);
	state->paints += map(sort(indices(saved))) {[string key] = __ARGS__;
		return ({key, saved[key]->label, hexcolor(saved[key]->color)});
	};
	if (array selfpub = gs->published_paints[uid]) state->selfpublished = hexcolor(selfpub[1]);
	return state;
}
void websocket_cmd_newgame(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%d#%s", int uid, string game);
	if (!uid) return; //Guests can't start new games. Log in first.
	//TODO: If the game exists and is completed, flush it?
	while (1) {
		string newid = random(CODENAMES) + "-" + random(CODENAMES) + "-" + random(CODENAMES);
		if (game_state[newid]) continue;
		game_state[newid] = ([
			"gameid": newid, "host": uid,
			"phase": "recruit",
			"published_paints": ([0: ({"Standard Beige", STANDARD_BASE})]),
			"saved_paints": ([]),
		]);
		conn->sock->send_text(Standards.JSON.encode((["cmd": "redirect", "game": newid])));
		return;
	}
}

void websocket_cmd_publish(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%d#%s", int uid, string game);
	if (!uid) return;
	mapping gs = game_state[game];
	if (!gs) return;
	if (gs->published_paints[uid]) return; //Already published one. No shenanigans.
	gs->published_paints[uid] = ({conn->session->user->display_name + "'s paint", conn->curpaint->definition});
	//Publish this to everyone in the same game - potentially many groups
	foreach (indices(websocket_groups), string grp)
		if (has_suffix(grp, "#" + game)) send_updates_all(grp);
}

void websocket_cmd_savepaint(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->id)) return;
	sscanf(conn->group, "%d#%s", int uid, string game);
	if (!uid) return;
	//Save the user's current paint and reset to beige
	mapping gs = game_state[game];
	if (!gs) return;
	if (!gs->saved_paints[uid]) gs->saved_paints[uid] = ([]);
	if (gs->saved_paints[uid][msg->id]) return; //Duplicate ID
	gs->saved_paints[uid][msg->id] = (["label": "Saved paint: " + msg->id, "color": conn->curpaint->definition]);
	websocket_cmd_freshpaint(conn, (["base": "0"]));
	send_updates_all(conn->group);
}

void websocket_cmd_addcolor(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!PIGMENTS[msg->color] || !has_value(({1, 2, 3}), msg->strength)) return;
	for (int i = 0; i < msg->strength; ++i)
		conn->curpaint->definition = mix(conn->curpaint->definition, PIGMENTS[msg->color]);
	conn->curpaint->blobs += ({([
		"label": msg->color + " (" + STRENGTHS[msg->strength - 1] + ")",
		"color": conn->curpaint->color = hexcolor(conn->curpaint->definition),
	])});
	send_update(conn, (["curpaint": (["blobs": conn->curpaint->blobs, "color": conn->curpaint->color])]));
}

void websocket_cmd_freshpaint(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%d#%s", int uid, string game);
	mapping gs = game_state[game];
	array request;
	//If you're not logged in, the only option is 0, the standard base.
	if (!uid || !game) request = msg->base == "0" && ({"Standard Beige", STANDARD_BASE});
	//If it's all digits, you're asking for a user ID.
	else if (msg->base == (string)(int)msg->base) request = gs->published_paints[(int)msg->base];
	//Otherwise, you're asking for one of your own saved paints.
	else if (mapping saved = gs->saved_paints[uid][?msg->base]) request = ({msg->base, saved->color});
	if (!request) return; //TODO: Send back an error message
	conn->curpaint = fresh_paint(@request);
	send_update(conn, (["curpaint": (["blobs": conn->curpaint->blobs, "color": conn->curpaint->color])]));
}

protected void create(string name) {
	::create(name);
	if (!G->G->diffie_hellman) G->G->diffie_hellman = ([]);
	game_state = G->G->diffie_hellman;
	foreach (SWATCHES, array info) {
		string name = info[0];
		if (sizeof(info) < 3) info += ({PIGMENTS[name]});
		name -= " ";
		if (array modifier = info[2]) {
			array color = STANDARD_BASE;
			swatch_colors[name] = hexcolor(modifier);
			if (modifier[0] * .2126 + modifier[1] * .7152 + modifier[2] * .0722 < 128)
				swatch_colors[name] += "; color: white"; //Hack: White text for dark colour swatches
			foreach (STRENGTHS, string strength) {
				color = mix(color, modifier);
				swatch_colors[name + "-" + strength] = hexcolor(color);
			}
		}
		else {
			//Hack: For bulker, just show lots of beige.
			swatch_colors[name] = hexcolor(STANDARD_BASE);
			foreach (STRENGTHS, string strength)
				swatch_colors[name + "-" + strength] = swatch_colors[name];
		}
		swatches += ({(["color": name, "desc": info[1], "label": info[0]])});
	}
	swatch_color_style = sprintf("%{.%s {background: #%s;}\n%}", sort((array)swatch_colors));
}

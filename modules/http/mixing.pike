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
.inline {width: 3em; height: 1.2em; vertical-align: text-top; margin: 0 0.5em;}
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
.role {
	display: none;
	margin: 10px;
	border: 1px solid green;
	padding: 5px;
	background: #eeffee;
	max-width: 400px;
}
.role.warning {
	border: 1px solid yellow;
	background: #ffcc77;
}
#gamedesc {
	margin: 20px;
	border: 3px solid blue;
	padding: 10px;
	background: #eeeeff;
	max-width: 600px;
}
#comparison {
	display: flex;
}
#midbtn {
	display: flex;
	flex-direction: column;
	justify-content: center;
	text-align: center;
	transition: width 1s, opacity 0s 1s; /* Make it reappear only when the transition is complete */
	width: 150px;
}
#comparison .swatch {transition: border-color, width 1s;}
#comparison.comparing .swatch {
	border-color: transparent;
	width: 250px;
}
#comparison.comparing #midbtn {
	transition: width 1s, opacity 0s 0s; /* Make it disappear immediately before shrinking the gap */
	opacity: 0;
	width: 0;
}

#paintcolor {
	/* When nothing's selected - notably, this is always the case for those other than
	the Contact - cover the comparison box with 'nope' stripes. */
	background: repeating-linear-gradient(
		-45deg,
		white,
		white 10px,
		black 10px,
		black 12px
	);
}
#all_notes li {cursor: pointer;}
#instrdescribe {max-width: 500px;}

.gameoverbox {
	font-size: 110%;
	max-width: 300px;
	margin: 10px;
	border: 2px solid black;
	padding: 8px;
}
.victory {
	background: #eeffee;
	border-color: green;
}
.defeat {
	background: #ffeeee;
	border-color: red;
}
</style>
<style id=phase>article#mixpaint {display: block;}</style>
<style id=rolestyle></style>

## Situation Report
Coded messages are no longer safe. Your enemies have discovered your code, and can both read your messages
and write fake messages of their own. You need a way to send your contact one crucial instruction which
will allow you to share a new code. How? There is a public message board on which anyone may leave a note,
so you must leave a message there, with some proof that it is truly from you.

[Mission Briefing](:.infobtn data-dlg=sitrep) [The Secret Trick](:.infobtn data-dlg=secret) [How it really works](:.infobtn data-dlg=dhke)

To participate in games, you'll need to confirm your Twitch account name. Otherwise, feel free to
<span id=specview>play with the paint mixer, though you can't save or publish your paints</span>.<br>
[Twitch login](:.twitchlogin)
{: #loginbox .hidden}

To join an operation in progress, ask the host for a link. Alternatively,
[start a new game](:#newgame .infobtn data-dlg=newgamedlg) and
share the link with others!
{: #gamedesc .hidden}

> ## Recruitment
>
> Declare your allegiance!
>
> Game host: <span id=gamehost><!-- name --></span>
>
> * Spymaster: <span id=spymaster>searching...</span>
> * Contact: <span id=contact>scanning...</span>
> * Agents of Chaos: [Join](:.setrole data-role=chaos) <span id=chaos>recruiting...</span>
> * Everyone else is a Spectator. [Spectate](:.setrole data-role=spectator)
>
{: tag=article #recruit}

<!-- -->
> ## Paint mixing
>
> CAUTION: Don't let anyone else see what's on your screen! To livestream the game, open an additional window
> (possibly using a different browser, or Incognito Mode) with the same game link; this will be spectator view.
> {: .warning .role .spymaster .contact .chaos}
>
> Welcome to the paint studio. Pick any pigment to mix it into your paint. To start fresh, pick a base color from any available.
>
> Outside of properly-started Operations, paints cannot be saved, so the only base color is the standard beige.
> {: .hidden #onlybeige}
>
> As the **Spymaster**, prepare and save the paint you will use on your note, and publish whatever your contact will need.
> {: .role .spymaster}
>
> As the **Contact**, predict and save the paint the Spymaster will use, and publish whatever you need to.
> {: .role .contact}
>
> As a **Chaos Agent**, try to predict what the Spymaster will use, so you can deceive the Contact.
> {: .role .chaos}
>
> As a **Spectator**, observe what the Spymaster and Contact do.
> {: .role .spectator}
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
> > [Publish this paint](:#publishpaint)
> {: tag=section}
>
> <!-- -->
{: tag=article #mixpaint}

<!-- -->
> ## Notes!
>
> Each player may submit up to one note for inclusion on the message board. You may choose any
> of your saved paints or anyone's published paints to mark it with.
>
> As the **Spymaster**, you must submit your note in such a way that your Contact will
> know that it is from you. Choose your paint color wisely!
> {: .role .spymaster}
>
> As the **Contact**, you may submit a note if you wish, but this is optional.
> {: .role .contact}
>
> As a **Chaos Agent**, try to deceive the Contact with a fake note.
> {: .role .chaos}
>
> You will be sending these instructions: <code class=note_to_send>Refresh the page for further instructions.</code>
>
> <div id=paintradio class=colorpicker><div class=swatch style=\"background: #F5F5DC\" data-id=0>Standard Beige</div></div>
>
> [Post It!](: #postnote)
>
> Once everyone's notes have been posted, the host can advance time.
{: tag=article #writenote}

<!-- -->
> ## The Message Board
>
> Far too many notes for my taste, but one of them is meant for you.
> Choose the right note to win the game!
> {: .role .contact}
>
> It's all out of your hands now. The only thing that matters is whether the Contact chooses
> the correct note.
> {: .role .spymaster .chaos .spectator}
>
> The instructions you sent were: <code class=note_to_send>Refresh the page for further instructions.</code>
>
> <div id=comparepaint class=hidden>
> Select a paint to compare against. Others will not see your selection.
> <div class=colorpicker></div></div>
>
> Notes on the board: <ol id=all_notes></ol>
>
> <div id=comparison><div id=notecolor class=\"swatch large\"></div><div id=midbtn><div>Waiting for comparison...</div></div><div id=paintcolor class=\"swatch large\"></div></div>
> [Use these instructions!](: .infobtn data-dlg=useinstrs)
>
> <ol reversed id=comparison_log></ol>
{: tag=article #readnote}

<!-- -->
> ## Game Over
>
> Did you win? Did you lose? Did you learn anything?
> {: #gamesummary}
>
> [Start new game](: .infobtn data-dlg=newgamedlg)
{: tag=article #gameover}

<!-- -->
> ### Start new game
> Leave this mayhem and go to a brand new show?
>
> [Do it. We shall prevail.](:#startnewgame) [On second thoughts...](:.dialog_close)
{: tag=dialog #newgamedlg}

<!-- -->
> ### Advance time
> Time and tide, they say, wait for no one. In fairness, you shouldn't have to wait<br>
> either. Are you ready to advance time to (TODO: name the next phase here)?
>
> [Activate time travel powers!](:#nextphase) [Wait, not yet.](:.dialog_close)
{: tag=dialog #nextphasedlg}

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
> <span id=annotateme>Base + Jade + Crimson is exactly the same as Base + Crimson + Jade.</span>
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
> [And that's how HTTPS works. Partly.](:.dialog_close)
{: tag=dialog #dhke}

<!-- -->
> ### Start new paint mix
>
> Confirm that you want to discard your current paint mix and start a new one using this base color.
>
> This paint color is...
> {: #paintorigin}
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

<!-- -->
> ### Post link in chat
> The channel bot that hosts this game can announce the link in your chat channel.
>
> > What should I say? Put <code>{link}</code> for the game page link.<br>
> > <input name=msg size=80> [Suggest](: #suggestmsg)
> >
> > [Yes! Cast 'Summon More Players'!](: type=submit) [It's fine, I can share it myself](:.dialog_close)
> {: tag=form #chatlinkform}
>
{: tag=dialog #chatlink}

<!-- -->
> ### Adopt instructions
> Hmm, start by picking something to follow...
> {: #instrdescribe}
>
> [My Spymaster's words, without a doubt.](: #followinstrs) [Hmm, actually, I'm not sure.](:.dialog_close)
>
{: tag=dialog #useinstrs}
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
	"Maize": ({0xFB, 0xEC, 0x5D}), //Rg
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
	"Orange": ({0xFF, 0x8C, 0x0A}),
	"Blood": ({0x7E, 0x35, 0x17}),
]);
constant SWATCHES = ({
	({"Crimson", "It's red. What did you expect?"}),
	({"Jade", "Derived from pulverised ancient artifacts. Probably not cursed."}),
	({"Cobalt", "Like balt, but the other way around"}),
	({"Hot Pink", "Use it quickly before it cools down!"}),
	({"Maize", "Astonish your friends! Amaize your enemies! Die of bad puns!"}),
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
	({"Orange", "For when security absolutely depends on not being able to rhyme"}),
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

constant WIN_STORIES = ({
	({
		({
			"Against unimaginable odds, the ", ({"role", "spymaster"}),
			" was able to deliver this message to the ", ({"role", "contact"}), ":",
		}), ({
			({"msg", "truth"}),
		}), ({
			"Thanks to this success, fresh codebooks could be exchanged securely, "
			"allowing future communication to be both private and secure. Agents "
			"of Chaos watch in frustration, unable to defeat the beautiful paint "
			"and mathematics of Diffie Hellman Key Exchange, no matter how they try. "
			"The Spymaster and Contact power-walk into the sunset, and the credits roll."
		}), ({
			({"box", "victory", "The forces of virtue have triumped over the forces of rottenness!"}),
		}),
	}), ({
		({
			"It takes mathematical precision to be this perfect. Nobody would fault "
			"you for not being absolutely spot-on. And yet... that's what happened. "
			"Spot on. Perfect. Nailed it. The ", ({"role", "spymaster"}), " hid a "
			"message in plain sight on the message board:",
		}), ({
			({"msg", "truth"}),
		}), ({
			"And the ", ({"role", "contact"}), ", out of all the notes on the board, "
			"picked out the right one. Through this public medium, they communicated "
			"private information, and from there, were able to reestablish secret "
			"channels for the future.",
		}), ({
			({"box", "victory", "Secrecy and privacy from mathematics. It's the best."}),
		}),
	}),
});
constant LOSE_STORIES = ({
	({
		({
			"In their moment of desperation, the ", ({"role", "spymaster"}),
			" and ", ({"role", "contact"}), " clutched at straws, hoping that ",
			"a public message board could be used for secure communications. "
			"They were sadly mistaken; Agents of Chaos used the codes they'd "
			"cracked, forged a plausible-sounding message, and deceived the "
			"Contact into following these instructions:",
		}), ({
			({"msg", "following"}),
		}), ({
			"Unfortunately, that message led to disaster: the Contact was caught, "
			"made an offer that he didn't want to refuse, and succumbed to Chaos. "
			"Meanwhile, the real instructions went completely unnoticed: ",
		}), ({
			({"msg", "truth"}),
		}), ({
			"You can't win 'em all. Don't worry. There will be other opportunities "
			"to try to safely communicate - in fact, this (or something like it) "
			"happens every time your web browser goes to an HTTPS web site.",
		}), ({
			({"box", "defeat", "Missed it by... that much."}),
		}),
	}), ({
		({
			"Ah, the old \"cover the message board with notes\" trick. That's the "
			"third time they've fallen for it this month... If only there were some "
			"way for the ", ({"role", "spymaster"}), " to sign the message so that "
			"the ", ({"role", "contact"}), " could be sure who it was from. If only "
			"some trick of the universe could provide a magical way to share secrets "
			"without them being seen by anyone else. If only.",
		}), ({
			"It seems that the Agents of Chaos have won. This time. But there will be "
			"another time, there will be a rematch! And next time, it will be different.",
		}), ({
			({"box", "defeat", "Sorry about that, Chief."}),
		}),
	}),
});

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

array(string) devise_messages(array(string) avoid, int n, multiset|void bootstrap) {
	multiset messages_used = bootstrap || (<>);
	array codenames = CODENAMES - avoid;
	if (!sizeof(codenames)) codenames = CODENAMES; //shouldn't happen
	while (1) {
		string msg = replace(random(MESSAGES), ([
			"{codename}": random(codenames),
			"{action}": random(ACTIONS),
		]));
		if (messages_used[msg]) continue;
		messages_used[msg] = 1;
		if (sizeof(messages_used) >= n) return indices(messages_used);
	}
}

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	string group = "0";
	string uid = req->misc->session->user->?id;
	mapping state = game_state[req->variables->game];
	if (state) group = uid + "#" + state->gameid;
	else group = (string)uid;
	return render(req, ([
		"vars": (["ws_group": group, "swatches": swatches]),
		"swatch_colors": swatch_color_style,
	]));
}

mapping fresh_paint(string basis, array basecolor, string|void basisdesc) {
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
//0#str: Guest, spectating game
string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	conn->curpaint = fresh_paint("Standard Beige", STANDARD_BASE);
	if (!stringp(msg->group)) return "Invalid group ID";
	if (msg->group == "0") return 0; //Always okay to be guest
	if (msg->group == (string)conn->session->user->?id) return 0; //Logged in as you, no game
	sscanf(msg->group, "%d#%s", int uid, string game);
	if (uid && uid != (int)conn->session->user->?id) return "Not logged in";
	if (mapping gs = game_state[game]) {
		if (!uid) return 0; //Spectate a game w/o logging in
		//Joining a game? Record your username and the role you're assigned.
		//(If we're past the recruitment phase, you get Spectator role by default.)
		gs->usernames[uid] = conn->session->user->display_name;
		if (!gs->roles[uid] && gs->phase == "recruit") {
			gs->roles[uid] = "chaos";
			update_game(game);
		}
		return 0;
	}
	return "Bad game ID";
}

mapping|Concurrent.Future get_state(string|int group, string|void id) {
	mapping state = (["loginbtn": -1, "paints": ({({0, "Standard Beige", hexcolor(STANDARD_BASE)})})]);
	sscanf(group, "%d#%s", int uid, string game);
	if (!uid || !game) state->no_save = 1;
	if (!uid) state->loginbtn = 1;
	if (!game) return state; //If you're not connected to a game, there are no saved paints.
	mapping gs = game_state[game];
	foreach ("gameid phase nophaseshift msg_order msg_color_order selected_note comparison_log game_summary" / " ", string passthru)
		if (gs[passthru]) state[passthru] = gs[passthru];
	state->host = gs->usernames[gs->host];
	if (gs->host == uid) state->is_host = 1; //Enable the phase advancement button(s)
	state->chaos = ({ });
	if (string note = gs->notes[?uid]) state->note_to_send = note;
	if (array color = gs->messageboard[?uid]) state->note_send_color = hexcolor(color);
	foreach (gs->roles; int uid; string role)
		if (role == "chaos") state[role] += ({gs->usernames[uid]});
		else state[role] = gs->usernames[uid];
	state->role = gs->roles[uid] || "spectator";
	state->paints = map(sort(indices(gs->published_paints))) {[int id] = __ARGS__;
		return ({id, gs->published_paints[id][0], hexcolor(gs->published_paints[id][1]), gs->published_paints[id][2]});
	};
	mapping saved = gs->saved_paints[uid] || ([]);
	state->paints += map(sort(indices(saved))) {[string key] = __ARGS__;
		return ({key, saved[key]->label, hexcolor(saved[key]->color), saved[key]->description});
	};
	if (array selfpub = gs->published_paints[uid]) state->selfpublished = hexcolor(selfpub[1]);
	if (gs->comparing) state->comparing = 1; //Don't give any details, just "we're comparing, do the animation"
	if (state->role == "contact" && gs->comparison_paints) state->comparison_paints = gs->comparison_paints;
	return state;
}

void update_game(string game) {
	//Publish a change to everyone in the same game - potentially many groups
	foreach (indices(websocket_groups), string grp)
		if (has_suffix(grp, "#" + game)) send_updates_all(grp);
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
			"usernames": ([uid: conn->session->user->display_name]),
			"roles": ([]),
			"phase": "recruit",
			"published_paints": ([0: ({"Standard Beige", STANDARD_BASE, "The Diffie Hellman Standardized Beige"})]),
			"saved_paints": ([]),
		]);
		conn->sock->send_text(Standards.JSON.encode((["cmd": "redirect", "game": newid])));
		return;
	}
}

void websocket_cmd_nextphase(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%d#%s", int uid, string game); if (!uid) return;
	mapping gs = game_state[game]; if (!gs) return;
	if (gs->host != uid) return;
	m_delete(gs, "nophaseshift");
	switch (gs->phase) {
		case "recruit": {
			if (sizeof(gs->roles) < 2) {gs->nophaseshift = "Need a minimum of two non-spectating players."; break;}
			foreach (({"spymaster", "contact"}), string needrole) if (!has_value(gs->roles, needrole)) {
				//Pick a random chaos agent to promote
				array agents = filter(indices(gs->roles)) {return gs->roles[__ARGS__[0]] == "chaos";};
				//assert sizeof(agents) > 0 //we already made sure there were enough total roles
				gs->roles[random(agents)] = needrole;
			}
			gs->phase = "mixpaint";
			break;
		}
		case "mixpaint": {
			if (sizeof(gs->published_paints) <= 1) {gs->nophaseshift = "Nobody's published any paints!"; break;}
			gs->phase = "writenote";
			//Assign a random message to each player.
			gs->notes = mkmapping(indices(gs->roles), devise_messages(game / "-", sizeof(gs->roles)));
			gs->messageboard = ([]);
			break;
		}
		case "writenote": {
			int spymaster = search(gs->roles, "spymaster");
			if (!gs->messageboard[spymaster]) {gs->nophaseshift = "The spymaster hasn't posted a note yet. This would end rather badly."; break;}
			//Remap the message board in message-keyed form
			int size = max(sizeof(gs->messageboard) * 2, 15); //May need to adjust the size in more ways
			gs->msg_order = Array.shuffle(devise_messages(game / "-", size, (multiset)values(gs->notes)));
			gs->msg_color = ([]);
			multiset seenhex = (<>);
			foreach (gs->messageboard; int uid; array color) {
				gs->msg_color[gs->notes[uid]] = color;
				seenhex[hexcolor(color)] = 1;
			}
			//Fill in random colors for the messages that don't have any set.
			//This includes any that were allocated to players who didn't submit.
			//We avoid duplication of hex color with any of the player ones, so if
			//any two messages have the same color, they must either both be from
			//players, or both be random. However, even though this information is
			//a bit unfair, it isn't devastating.
			//Possible interesting analysis: If 10 pigments at a depth of 1-3 each
			//are mixed (parallelling the recommended 3-5 pigments per half-key),
			//what is the distribution of hexcolor components? I'm doing simple
			//linear unweighted random selection, so 0, 60, 120, 180, 240 are all
			//equally likely to show up. Is that actually plausible? Of course,
			//what we can't be sure of is what happens when actual humans pick, as
			//it's near-impossible to define what a "pretty" colour will be.
			foreach (gs->msg_order, string msg) {
				if (gs->msg_color[msg]) continue;
				while (1) {
					array color = random(STANDARD_BASE[*]);
					string hex = hexcolor(color);
					if (seenhex[hex]) continue;
					gs->msg_color[msg] = color;
					break;
				}
			}
			gs->msg_color_order = map(gs->msg_order) {return hexcolor(gs->msg_color[__ARGS__[0]]);};
			gs->comparison_log = ({ }); gs->comparison_paints = ({ });
			gs->phase = "readnote";
			break;
		}
		case "readnote": {
			gs->nophaseshift = "The Contact hasn't selected which instructions to follow.";
			//Note that setting phase to gameover actually happens as a direct consequence of
			//selecting instructions. Host privileges do not apply.
			break;
		}
		case "gameover": break;
		default: gs->nophaseshift = "Unknown phase " + gs->phase;
	}
	update_game(game);
}

void websocket_cmd_setrole(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%d#%s", int uid, string game); if (!uid) return;
	mapping gs = game_state[game]; if (!gs) return;
	if (gs->phase != "recruit") return; //Role assignments are locked in after recruitment phase
	int valid = (["spymaster": 1, "contact": 1, "chaos": 999, "spectator": 999])[msg->role];
	if (!valid) return;
	if (valid == 1) {
		//Only one person can have that role. If someone else has it, they have
		//to step down before you can take it. (If you already have it, we should
		//give a different message, but still block it.)
		if (has_value(gs->roles, msg->role)) return;
	}
	if (msg->role == "spectator") m_delete(gs->roles, uid); //No need to record spectators (and it's convenient for player counting to omit them)
	else gs->roles[uid] = msg->role;
	update_game(game);
}

void websocket_cmd_publish(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%d#%s", int uid, string game); if (!uid) return;
	mapping gs = game_state[game]; if (!gs) return;
	if (gs->published_paints[uid]) return; //Already published one. No shenanigans.
	gs->published_paints[uid] = ({
		conn->session->user->display_name + "'s paint",
		conn->curpaint->definition,
		"The color published by " + conn->session->user->display_name,
	});
	update_game(game);
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
	if (msg->id == (string)(int)msg->id) return; //Numeric ID. Disallow as it would look like a published paint.
	gs->saved_paints[uid][msg->id] = ([
		"label": "Saved paint: " + msg->id,
		"color": conn->curpaint->definition,
		"description": conn->curpaint->blobs->label * ", ",
	]);
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
	else if (mapping saved = gs->saved_paints[uid][?msg->base]) request = ({msg->base, saved->color, saved->description});
	if (!request) return; //TODO: Send back an error message
	conn->curpaint = fresh_paint(@request);
	send_update(conn, (["curpaint": (["blobs": conn->curpaint->blobs, "color": conn->curpaint->color])]));
}

void websocket_cmd_chatlink(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->msg)) return;
	sscanf(conn->group, "%d#%s", int uid, string game); if (!uid) return;
	mapping gs = game_state[game]; if (!gs) return;
	if (gs->host != uid) return;
	string url = persist_config["ircsettings"]->http_address + "/mixing?game=" + game;
	send_message("#" + conn->session->user->login, replace(msg->msg, "{link}", url));
}

void websocket_cmd_postnote(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%d#%s", int uid, string game); if (!uid) return;
	mapping gs = game_state[game]; if (!gs) return;
	if (gs->phase != "writenote") return;
	array color;
	if (msg->paint == (string)(int)msg->paint) color = gs->published_paints[(int)msg->paint][?1];
	else if (mapping saved = gs->saved_paints[uid][?msg->paint]) color = saved->color;
	if (!color) return;
	gs->messageboard[uid] = color;
	send_updates_all(conn->group);
}

void websocket_cmd_selectnote(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%d#%s", int uid, string game); if (!uid) return;
	mapping gs = game_state[game]; if (!gs) return;
	if (gs->phase != "readnote") return;
	if (gs->roles[uid] != "contact") return;
	//Note IDs are 1-based.
	if (!intp(msg->note) || msg->note < 1 || msg->note > sizeof(gs->msg_order)) return;
	gs->selected_note = msg->note;
	gs->comparison_log += ({(["action": "select", "noteid": msg->note])});
	update_game(game);
}

void complete_comparison(mapping gs) {
	[array note, array paint, mixed callout] = m_delete(gs, "comparing");
	string similarity = "different";
	if (`+(@(note[*] == paint[*])) == 3) similarity = "identical";
	else {
		//Try to figure out whether the colors are similar or different
		//These values are scaled 0-255 (maybe higher), so "very different" could
		//be some fairly big numbers.
		[float r, float g, float b] = (array(float))((note[*] - paint[*])[*] ** 2);
		float greydiff = r * .2126 + g * .7152 + b * .0722;
		//write("Resulting differences: %O, %O, %O ==> %O\n", r, g, b, greydiff);
		//What constitutes "similar"? It's hard to judge. Also, should the components
		//(which are distance-squareds) be scaled by the square of these ratios?
		if (greydiff < 256) similarity = "similar";
	}
	gs->comparison_log += ({(["action": "result", "similarity": similarity])});
	update_game(gs->gameid);
}

void websocket_cmd_comparenotepaint(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%d#%s", int uid, string game); if (!uid) return;
	mapping gs = game_state[game]; if (!gs) return;
	if (gs->phase != "readnote") return;
	if (gs->roles[uid] != "contact") return;
	if (!gs->selected_note) return; //First select a note, then compare to the paint
	if (gs->comparing) return; //Another comparison is in progress.
	array color;
	if (msg->paint == (string)(int)msg->paint) color = gs->published_paints[(int)msg->paint][?1];
	else if (mapping saved = gs->saved_paints[uid][?msg->paint]) color = saved->color;
	if (!color) return;
	gs->comparing = ({gs->msg_color[gs->msg_order[gs->selected_note - 1]], color, call_out(complete_comparison, 5, gs)});
	gs->comparison_log += ({(["action": "compare", "coloridx": sizeof(gs->comparison_paints), "noteid": gs->selected_note])});
	gs->comparison_paints += ({hexcolor(color)});
	update_game(game);
}

void websocket_cmd_followinstrs(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%d#%s", int uid, string game); if (!uid) return;
	mapping gs = game_state[game]; if (!gs) return;
	if (gs->phase != "readnote") return;
	if (gs->roles[uid] != "contact") return;
	if (!gs->selected_note) return; //First select a note to follow
	if (gs->comparing) return; //A comparison is in progress. You probably don't want to skip out on it.
	int spymaster = search(gs->roles, "spymaster");
	int contact = search(gs->roles, "contact");
	mapping msgs = (["following": gs->msg_order[gs->selected_note - 1],
			"truth": gs->notes[spymaster]]);
	mapping roles = ([
		"spymaster": "Spymaster (" + gs->usernames[spymaster] + ")",
		"contact": "Contact (" + gs->usernames[contact] + ")",
	]);
	//Generate a flavourful game summary.
	array story;
	if (msgs->following == msgs->truth) story = random(WIN_STORIES);
	else story = random(LOSE_STORIES);
	array xfrm(string|array part) {
		if (stringp(part)) return ({"text", part});
		switch (part[0]) {
			case "role": return ({"role", roles[part[1]] || "(??)"});
			case "msg": return ({"msg", msgs[part[1]], hexcolor(gs->msg_color[msgs[part[1]]])});
			case "box": return part;
		}
		return ({"text", "(unknown part type)"});
	}
	gs->game_summary = map(story[*], xfrm);
	gs->phase = "gameover";
	update_game(game);
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

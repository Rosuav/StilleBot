inherit http_websocket;
inherit hook;
inherit irc_callback;

//Markdown; emote names will be replaced with their emotes, but will
//be greyed out if not available.
//NOTE: The display is aimed at no more than six emotes across.
constant hypetrain = replace(#"
## Hype Train set six
### Unlockable Dec 2023... ongoing or not?
HypeCute HypeYummy HypeKEKW HypeNoods HypeOho ????<br>
HypeHi HypeChill HypeMyHeart HypeWarm HypeFist ????<br>
HypeCries HypeGGEyes HypeAwh HypeElf HypeDelight ????<br>
HypeNotLikeSnow HypePls HypeMelt HypeCocoa HypeConfetti ????<br>
HypeSanta HypePeek HypeOhDeer HypeUwu HypeLick ????<br>

## Hype Train set five
### Unlockable Nov 2021 to Dec 2023
HypeLUL HypeCool HypeLove1 HypeSleep HypePat HypeCozy1<br>
HypeHands1 HypeHands2 HypeFail HypeHai HypeNom HypeBoop<br>
HypeBLEH HypeApplause HypeRage HypeMwah HypeHuh HypeSeemsGood<br>
HypeWave HypeReading HypeShock HypeStress HypeCry HypeDerp1<br>
HypeCheer HypeLurk HypePopcorn HypeEvil HypeAwww HypeHype<br>

## Hype Train set four
### Unlockable May 2021 to Oct 2021
HypeHeh HypeDoh HypeYum HypeShame HypeHide HypeWow<br>
HypeTongue HypePurr HypeOoh HypeBeard HypeEyes HypeHay<br>
HypeYesPlease HypeDerp HypeJudge HypeEars HypeCozy HypeYas<br>
HypeWant HypeStahp HypeYawn HypeCreep HypeDisguise HypeAttack<br>
HypeScream HypeSquawk HypeSus HypeHeyFriends HypeMine HypeShy<br>

## Hindsight 2020
### Part 1: Unlockable 2nd Dec 2020 to 16th Dec 2020
2020Party 2020Rivalry 2020Unroll 2020Suspicious<br>
2020HomeWork 2020Gift 2020Capture 2020Surprise<br>
2020Selfie 2020SpeakUp 2020Pajamas 2020Delivery<br>

### Part 2: Unlockable 16th Dec 2020 to 4th Jan 2021
2020ByeGuys 2020Drop 2020Glitchy 2020Partnered 2020Shhh<br>
2020Shred 2020Unity 2020Forward 2020Takeout 2020MaskUp<br>
2020Victory 2020Celebrate 2020Snacking 2020Wish<br>

## Hype Train set three
### Unlockable Nov 2020 to May 2021
HypeFighter HypeShield HypeKick HypeSwipe HypeRIP HypeGG<br>
HypeRanger HypeMiss HypeHit HypeHeart HypeTarget HypeWink<br>
HypeRogue HypeWut HypeGems HypeCoin HypeSneak HypeCash<br>
HypeBard HypeTune HypeRun HypeZzz HypeRock HypeJuggle<br>
HypeMage HypeWho HypeLol HypePotion HypeBook HypeSmoke<br>

## Celebrate KPOP
### Unlockable 19th Oct 2020 to 30th Oct 2020
KPOPvictory KPOPmerch KPOPselfie KPOPTT KPOPlove<br>
KPOPfan KPOPcheer KPOPdance KPOPglow KPOPheart<br>

## Hyper Scape
### Unlockable 17th Aug 2020 to 31st Aug 2020
HyperSlam HyperReveal HyperParkour HyperMine HyperMayhem<br>
HyperJump HyperHex HyperHaste HyperGravity HyperCrown<br>
HyperLost HyperCrate HyperCooldown HyperCheese HyperTiger<br>

## Hype Train set two
### Unlockable Apr 2020 to Nov 2020
HypeChimp HypeGhost HypeChest HypeFrog HypeCherry HypePeace<br>
HypeSideeye HypeBrain HypeZap HypeShip HypeSign HypeBug<br>
HypeYikes HypeRacer HypeCar HypeFirst HypeTrophy HypeBanana<br>
HypeBlock HypeDaze HypeBounce HypeJewel HypeBlob HypeTeamwork<br>
HypeLove HypePunk HypeKO HypePunch HypeFire HypePizza<br>

## Hype Train original
### Unlockable Jan 2020 to Apr 2020
HypeBigfoot1 HypeBigfoot2 HypeBigfoot3 HypeBigfoot4 HypeBigfoot5 HypeBigfoot6<br>
HypeGriffin1 HypeGriffin2 HypeGriffin3 HypeGriffin4 HypeGriffin5 HypeGriffin6<br>
HypeOni1 HypeOni2 HypeOni3 HypeOni4 HypeOni5 HypeOni6<br>
HypeDragon1 HypeDragon2 HypeDragon3 HypeDragon4 HypeDragon5 HypeDragon6<br>
HypeUnicorn1 HypeUnicorn2 HypeUnicorn3 HypeUnicorn4 HypeUnicorn5 HypeUnicorn6<br>

## StreamerLuv
### Unlockable 30th Jan 2020 to 16th Feb 2020
LuvBrownL LuvHearts LuvBlondeR LuvUok LuvOops<br>
LuvSign LuvPeekL LuvPeekR LuvCool LuvSnooze<br>
LuvBlush LuvBrownR LuvGift LuvBlondeL<br>

## HAHAHAlidays
### Unlockable 3rd Dec 2019 to 3rd Jan 2020
HahaNutcracker HahaPresent HahaGoose HahaBaby HahaNyandeer<br>
HahaGingercat HahaPoint HahaElf HahaSnowhal HahaReindeer<br>
HahaSweat HahaShrugLeft HahaShrugMiddle HahaShrugRight HahaThisisfine<br>
HahaLean HahaDreidel HahaThink HahaCat HahaTurtledove<br>
HahaSleep Haha2020 HahaBall HahaDoge HahaHide<br>

## RPG
### Unlockable 4th Oct 2019 to 18th Oct 2019
RPGFireball RPGYonger RPGTreeNua RPGOops RPGStaff<br>
RPGFei RPGAyaya RPGGhosto RPGHP RPGEmpty<br>
RPGBukka RPGBukkaNoo RPGEpicSword RPGShihu RPGPhatLoot<br>
RPGEpicStaff RPGMana RPGSeven<br>

## Special
### Unlockable by performing special actions or having special subscriptions. May or may not still be available.

2FA:<br>SirShield SirMad SirPrise SirSword SirSad SirMad<br>
Turbo:<br>BagOfMemes FlipThis KappaHD MindManners<br>MiniK PartyPopper ScaredyCat TableHere<br>
Prime:<br>PrimeYouDontSay PrimeUWot PrimeRlyTho<br>
Clip creation:<br>Clappy ClappyDerp ClappyHype<br>

## Single Survivors
For a while, Twitch released sets of emotes, but only let us keep the one
most popular emote from the set. These sole survivors are all that remain
of their formerly grand sets...
CupFooty ZombieKappa OWL2019Tracer FightCC<br>

", "<br>\n", "<br>"); //Remove the newlines after the line breaks so we don't get superfluous empty paragraphs
//For emotes that the bot has, we can get their IDs from chat sightings.
constant emoteids = ([
	"HypeOni6": "301205427", "OWL2019Tracer": "1833318",
	"PrimeYouDontSay": "134251", "PrimeUWot": "134252", "PrimeRlyTho": "134253",
	//Hype Train v4 bonus emotes
	"HypeWow": "emotesv2_d20a5e514e534288a1104b92c4f87834",
	"HypeHay": "emotesv2_50e775355dbe4992a086f24ffaa73676",
	"HypeYas": "emotesv2_d8271fc8f0264fdc9b1ac79051f75349",
	"HypeAttack": "emotesv2_f35caa0f5f3243b88cfbd85a3c9e69ff",
	"HypeShy": "emotesv2_d4a50cfaa51f46e99e5228ce8ef953c4",
	//Hype Train v6 uncollected emotes
	"HypeYummy": "emotesv2_1de038c78b7b42a6813eec49203a03e9",
	"HypeKEKW": "emotesv2_0ed449060b1042a3886705a71878d95d",
	"HypeNoods": "emotesv2_5c7d8853101c4f1daf94bae1e6008f72",
	"HypeOho": "emotesv2_c280f4f1d638452eb457b245bbdc0626",
	"HypeHi": "emotesv2_2ac008e6cefc423eb8a72388fe547eda",
	"HypeChill": "emotesv2_75fbd37276e14b2da995d1495246a267",
	"HypeMyHeart": "emotesv2_9f4c19c52e444ef98bc0af5b61f95a2b",
	"HypeWarm": "emotesv2_5c1d7a2705c341ac860915b706d51086",
	"HypeFist": "emotesv2_b520efa278fb4506971914f7d290f3f8",
	"HypeCries": "emotesv2_ce3c1c5b380746cdbbdbd2915bef3710",
	"HypeGGEyes": "emotesv2_da473526a7ce4c2b9ff5b62f18f561b0",
	"HypeAwh": "emotesv2_3a56169d4e0343a2ba72dd07e3aa8fb4",
	"HypeElf": "emotesv2_0264c8e0fe854a0a9486ffb30a46b1da",
	"HypeDelight": "emotesv2_15cb5689e3f64777b93c112fba0190ae",
	"HypeNotLikeSnow": "emotesv2_922c1f4705fa49d28b7439fac7d0ca03",
	"HypePls": "emotesv2_a002670712f54576acd0ce40e9015a12",
	"HypeMelt": "emotesv2_eb3ae3548224414ea104de573aee4d91",
	"HypeCocoa": "emotesv2_5b7686be9f65488e9a5910965ef0ce38",
	"HypeConfetti": "emotesv2_d026a0d9211e434fb153ba249c669d6b",
	"HypeSanta": "emotesv2_6c99e6a1d90c4e50a9f087ebeb659bbe",
	"HypePeek": "emotesv2_e621ef332af0497f91552c0efbfff0dd",
	"HypeOhDeer": "emotesv2_f721d941d14642e2b30de2e86fa28082",
	"HypeUwu": "emotesv2_9c5840880c854913867fa2e5ffdc1f17",
	"HypeLick": "emotesv2_47d858d7a1e042a3bf72eab138351415",
]);
array(string) tracked_emote_names;

//HACK: Send to a channel nobody cares about, but which the bot tracks.
//Bot hosts, ensure that this is a channel that you use with the bot.
//(Name must be in lowercase to match incoming message channel name.)
constant echolocation_channel = "#mustardmine";

Regexp.PCRE.Studied words = Regexp.PCRE.Studied("\\w+");

string img(string code, int|string id)
{
	return sprintf("<figure>![%s](%s)"
		"<figcaption>%[0]s</figcaption></figure>", code, emote_url((string)id, 3));
}

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	mapping emotesets = ([]);
	string login_link = "[Log in to highlight the emotes you have access to](:.twitchlogin data-scopes=@chat_login chat:edit@)";
	mapping v2_have = ([]);
	multiset scopes = req->misc->session->?scopes || (<>);
	string title = "Emote checklist";
	if (req->variables->showcase) {
		//?showcase=49497888 to see Rosuav's emotes
		//Only if permission granted.
		v2_have = persist_status->has_path("seen_emotes", req->variables->showcase) || ([]);
		if (!v2_have->_allow_showcase) v2_have = ([]);
		else title = "Emote showcase for " + v2_have->_allow_showcase;
	}
	else if (scopes->chat_login && scopes["chat:edit"]) {
		//Helix-friendly: query emotes by pushing them through chat.
		//No, this is not better than the Kraken way. Not even slightly.
		login_link = "<input type=checkbox id=showall>\n\n<label for=showall>Show all</label>\n\n"
			"[Check for newly-unlocked emotes](:#echolocate) [Enable showcase](:#toggleshowcase)\n\n"
			"[Show off your emotes here](checklist?showcase=" + req->misc->session->?user->?id + ")";
		v2_have = persist_status->path("seen_emotes", (string)req->misc->session->?user->?id) || ([]);
	}
	else login_link += "\n\n<input type=checkbox id=showall style=\"display:none\" checked>"; //Hack: Show all if not logged in
	mapping have_emotes = ([]);
	array(string) used = indices(v2_have); //Emote names that we have AND used. If they're in that mapping, they're in the checklist (by definition).
	foreach (emotesets;; array set) foreach (set, mapping em)
		have_emotes[em->code] = img(em->code, em->id);
	mapping botemotes = persist_status->path("bot_emotes");
	string text = words->replace(hypetrain, lambda(string w) {
		//1) Do we (the logged-in user) have the emote?
		if (string have = have_emotes[w]) {used += ({w}); return have;}
		//2) Does the bot have the emote?
		if (string id = botemotes[w]) return img(w, id);
		//3) Is it in the hard-coded list of known emote IDs?
		if (string id = emoteids[w]) return img(w, id);
		return w;
	});
	return render(req, ([
		"vars": (["ws_group": req->misc->session->?user->?id]),
		"login_link": login_link,
		"text": text, "emotes": sprintf("img[title=\"%s\"]", used[*]) * ", ",
		"title": title,
	]));
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {if (msg->group != conn->session->?user->?id) return "Not you";}
mapping get_state(string group) {
	return (["emotes": indices(persist_status->has_path("seen_emotes", group) || ([]))]);
}

continue Concurrent.Future echolocate(string user, string pass, array emotes) {
	//Break up the list of emote names into blocks no more than 500 characters each
	array messages = String.trim((sprintf("%=500s", emotes * " ") / "\n")[*]);
	object irc = yield(irc_connect((["user": user, "pass": pass])));
	irc->send(echolocation_channel, messages[*]);
	irc->quit();
}

void websocket_cmd_echolocate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping seen = persist_status->path("seen_emotes", conn->session->user->id);
	int threshold = time() - 86400;
	array emotes = filter(tracked_emote_names) {return seen[__ARGS__[0]] < threshold;};
	spawn_task(echolocate(conn->session->user->login, "oauth:" + conn->session->token, emotes));
}

void websocket_cmd_toggleshowcase(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping seen = persist_status->path("seen_emotes", conn->session->user->id);
	if (!m_delete(seen, "_allow_showcase")) seen->_allow_showcase = conn->session->user->display_name;
	persist_status->save();
	send_updates_all(conn->group);
}

@hook_allmsgs:
int message(object channel, mapping person, string msg) {
	if (!person->uid || !person->emotes || (!sizeof(person->emotes) && channel->name != echolocation_channel)) return 0;
	mapping v2 = G->G->emotes_v2;
	mapping seen = persist_status->has_path("seen_emotes", (string)person->uid);
	mapping botemotes = person->uid == G->G->bot_uid && persist_status->path("bot_emotes");
	int changed = 0, now = time();
	foreach (person->emotes, [string id, int start, int end]) {
		if (botemotes) {
			string code = msg[start..end];
			if (!has_prefix(code, "/") && !has_value(code, '_'))
				botemotes[code] = id;
		}
		string emotename = v2[id];
		if (!emotename) {
			//If it's not one of our list of known tracked emotes, check if the
			//emote name (drawn from the message text) shows up anywhere in the
			//Markdown for the emote checklist blocks. TODO: Recognize actual
			//emotes a bit more reliably.
			string code = msg[start..end];
			if (has_value(hypetrain, code)) emotename = code;
			else continue;
		}
		if (!seen) seen = persist_status->path("seen_emotes", (string)person->uid);
		if (!seen[emotename]) changed = 1;
		seen[emotename] = now;
		persist_status->save();
	}
	if (channel->name == echolocation_channel && seen) {
		//When it's a message specifically for emote testing, scan for words that are NOT emotes and
		//remove them from the seen_emotes list. This will avoid the uncertainty of whether or not
		//an emote is indeed available, and saves us the hassle of deciding whether to query
		//destructively or nondestructively, by being a brilliant combination of both.
		foreach (msg / " ", string w) {
			if (seen[w] && seen[w] != now) {
				m_delete(seen, w);
				persist_status->save();
				changed = 1;
			}
		}
	}
	if (changed) send_updates_all((string)person->uid);
}

protected void create(string name) {
	::create(name);
	//List of emotes to track - specifically, all the v2 emote IDs shown in the checklist.
	//No other emotes will be tracked, and we assume in general that these emotes will not
	//ever be lost. If they are, there'll need to be some way to say "purge those I haven't
	//used in X seconds", which will be possible, since they're stored with their timestamps.
	mapping v2 = filter(emoteids, stringp);
	G->G->emotes_v2 = mkmapping(values(v2), indices(v2));
	//List all emotes that would be detected by the main translation loop.
	//Technically the replacement is ignored, but it's consistent with the above.
	array trackme = ({ });
	mapping botemotes = persist_status->path("bot_emotes");
	string text = words->replace(hypetrain, lambda(string w) {
		if (botemotes[w] || emoteids[w]) trackme += ({w});
		return w;
	});
	tracked_emote_names = trackme;
}

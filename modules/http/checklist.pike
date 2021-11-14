inherit http_endpoint;

//Markdown; emote names will be replaced with their emotes, but will
//be greyed out if not available.
//NOTE: The display is aimed at no more than six emotes across.
constant hypetrain = replace(#"
## Hype Train set five
### Unlockable Nov 2021 to current
### (Highlighting is unreliable due to Twitch limitations)
HypeLUL HypeCool HypeLove1 HypeSleep HypePat HypeCozy1<br>
HypeHands1 HypeHands2 HypeFail HypeHai HypeNom HypeBoop<br>
HypeBLEH HypeApplause HypeRage HypeMwah HypeHuh HypeSeemsGood<br>
HypeWave HypeReading HypeShock HypeStress HypeCry HypeDerp1<br>
HypeCheer HypeLurk HypePopcorn HypeEvil HypeAwww HypeHype<br>

## Hype Train set four
### Unlockable May 2021 to Oct 2021
### (Highlighting is unreliable due to Twitch limitations)
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

TODO: Check Pok* (Pokemon) emotes
", "<br>\n", "<br>"); //Remove the newlines after the line breaks so we don't get superfluous empty paragraphs
//For V1 emotes that the bot has, we can get their IDs from the API.
//For others, list them here and they'll work. This means that all v2 emotes have to be
//kept here permanently, even if the bot has them. This may entail a maintenance cost
//if the emote IDs ever change. Hopefully they won't.
constant emoteids = ([
	"HypeOni6": 301205427, "OWL2019Tracer": 1833318,
	"PrimeYouDontSay": 134251, "PrimeUWot": 134252, "PrimeRlyTho": 134253,
	"HypeHeart": 304420791, //Not sure why this one, and this one alone, didn't show up
	//Hype Train v4: level 1
	"HypeHeh": "emotesv2_62199faa2ca34ea8a0f3567990a72a14",
	"HypeDoh": "emotesv2_69a7806c6837428f82475e99677d2f78",
	"HypeYum": "emotesv2_a964a0cbae9348e6bd981bc714eec71d",
	"HypeShame": "emotesv2_680c3aae688947d8b6067cff1a8bcdbe",
	"HypeHide": "emotesv2_6a99bc2baae743099b23ed6ab07bc5c4",
	"HypeWow": "emotesv2_d20a5e514e534288a1104b92c4f87834",

	//Level 2
	"HypeTongue": "emotesv2_ea658eb2e9d54833a4518c6dcc196dc6",
	"HypePurr": "emotesv2_811afb48bceb4ccdbd3281c602d3e3cb",
	"HypeOoh": "emotesv2_994d515930a14e5396fd36d45e785d48",
	"HypeBeard": "emotesv2_f045d9aa07d54961ab2ba77174305278",
	"HypeEyes": "emotesv2_23f63a570f724822bb976f36572a0785",
	"HypeHay": "emotesv2_50e775355dbe4992a086f24ffaa73676",

	//Level 3
	"HypeYesPlease": "emotesv2_fa2dad1f526b4c0a843d2cc4d12a7e06",
	"HypeDerp": "emotesv2_22683be90477418fbc8e76e0cd91a4bd",
	"HypeJudge": "emotesv2_164b5a252ea94201b7fcfcb7113fe621",
	"HypeEars": "emotesv2_5ade9654471d406994040073d80c78ac",
	"HypeCozy": "emotesv2_031719611d64458fb76982679a2d492a",
	"HypeYas": "emotesv2_d8271fc8f0264fdc9b1ac79051f75349",

	//Level 4
	"HypeWant": "emotesv2_2a3cd0373fe349cf853c058f10fae0be",
	"HypeStahp": "emotesv2_661e2889e5b0420a8bb0766dd6cf8010",
	"HypeYawn": "emotesv2_0f5d26b991a44ffbb88188495a8dd689",
	"HypeCreep": "emotesv2_19e3d6baefa5477caeaa238bf1b31fb1",
	"HypeDisguise": "emotesv2_dc24652ada1e4c84a5e3ceebae4de709",
	"HypeAttack": "emotesv2_f35caa0f5f3243b88cfbd85a3c9e69ff",

	//Level 5
	"HypeScream": "emotesv2_a05d626acce9485d83fdfb02b6553826",
	"HypeSquawk": "emotesv2_07dfbc3be2af4edea09217f6f9292b40",
	"HypeSus": "emotesv2_e0d949b6afb94b01b608fb3ad3e08348",
	"HypeHeyFriends": "emotesv2_be2e7ac3e077421da3526633fbbb9176",
	"HypeMine": "emotesv2_ebc2e7675cdd4f4f9871557cfed4b28e",
	"HypeShy": "emotesv2_d4a50cfaa51f46e99e5228ce8ef953c4",

	//Hype Train v5: level 1
	"HypeLUL": "emotesv2_e7a6e7e24a844e709c4d93c0845422e1",
	"HypeCool": "emotesv2_e2a11d74a4824cbf9a8b28079e5e67dd",
	"HypeLove1": "emotesv2_036fd741be4141198999b2ca4300668e",
	"HypeSleep": "emotesv2_3114c3d12dc44f53810140f632128b54",
	"HypePat": "emotesv2_7d457ecda087479f98501f80e23b5a04",
	"HypeCozy1": "emotesv2_6d27dcab0df7442b88260a25d60bd807",

	//Level 2
	"HypeHands1": "emotesv2_0457808073314f62962554c12ebb6b4d",
	"HypeHands2": "emotesv2_8c40cd16027f48c0a70ac7b1fa1c397e",
	"HypeFail": "emotesv2_0330a84e75ad48c1821c1d29a7dadd4d",
	"HypeHai": "emotesv2_9b68a8fa2f1d457496ac016b251e06b6",
	"HypeNom": "emotesv2_9bcc622c0b2a48b180a159c25a2b8245",
	"HypeBoop": "emotesv2_f930e2f43d284c51a3eb02714360a331",

	//Level 3
	"HypeBLEH": "emotesv2_08abf0cd0e78494a9da8a2315c3648f4",
	"HypeApplause": "emotesv2_ccc146905a694f3b8df390f55e34002a",
	"HypeRage": "emotesv2_4918bd32ff5b476f82bda49f3e958767",
	"HypeMwah": "emotesv2_7d01d1cf36b549098434c7a6e50a8828",
	"HypeHuh": "emotesv2_43da115e6b6749828f7dee47d17dd315",
	"HypeSeemsGood": "emotesv2_73aba26793314019b5ff7a5643e52749",

	//Level 4
	"HypeWave": "emotesv2_663dbd72c3ae48c585ffd61f3c348fa9",
	"HypeReading": "emotesv2_271ea48a09ca418baad2ea1f734ab09e",
	"HypeShock": "emotesv2_1337536bcecf49f4bb9cd1a699341ee2",
	"HypeStress": "emotesv2_8c1d964bd7e14fe1b8bd61d29ee0eb8c",
	"HypeCry": "emotesv2_cdc7a602ee08462e81fb6cc0e3e8de61",
	"HypeDerp1": "emotesv2_e029042dd623498d8b1e74e3ea472bea",

	//Level 5
	"HypeCheer": "emotesv2_dd4f4f9cea1a4039ad3390e20900abe4",
	"HypeLurk": "emotesv2_1630ff0e5ff34a808f4b25320a540ee7",
	"HypePopcorn": "emotesv2_7b8e74be7bd64601a2608c2ff5f6eb7a",
	"HypeEvil": "emotesv2_1885b5088372466b800789b02daf7b65",
	"HypeAwww": "emotesv2_85a13cc47247425fa152b9292c4589a9",
	"HypeHype": "emotesv2_e920cae6f2d8401d8e15392b1a292fbb",
]);

Regexp.PCRE.Studied words = Regexp.PCRE.Studied("\\w+");

string url(int|string id) {
	if (intp(id)) return sprintf("https://static-cdn.jtvnw.net/emoticons/v1/%d/3.0", id);
	return sprintf("https://static-cdn.jtvnw.net/emoticons/v2/%s/default/light/3.0", id);
}

string img(string code, int|string id)
{
	return sprintf("<figure>![%s](%s)"
		"<figcaption>%[0]s</figcaption></figure>", code, url(id));
}

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	mapping emotesets = ([]);
	string login_link = "[Log in to highlight the emotes you have access to](:.twitchlogin data-scopes=user_subscriptions)";
	mapping v2_have = ([]);
	if (req->misc->session->?scopes->?user_subscriptions)
	{
		login_link = "<input type=checkbox id=showall>\n\n<label for=showall>Show all</label>";
		emotesets = yield(twitch_api_request("https://api.twitch.tv/kraken/users/{{USER}}/emotes",
			(["Authorization": "OAuth " + req->misc->session->token]),
			(["username": req->misc->session->user->login])))->emoticon_sets;
		v2_have = persist_status->path("seen_emotes")[(string)req->misc->session->?user->?id] || ([]);
	}
	else login_link += "\n\n<input type=checkbox id=showall style=\"display:none\" checked>"; //Hack: Show all if not logged in
	mapping have_emotes = ([]);
	array(string) used = indices(v2_have); //Emote names that we have AND used. If they're in that mapping, they're in the checklist (by definition).
	foreach (emotesets;; array set) foreach (set, mapping em)
		have_emotes[em->code] = img(em->code, em->id);
	string text = words->replace(hypetrain, lambda(string w) {
		//1) Do we (the logged-in user) have the emote?
		if (string have = have_emotes[w]) {used += ({w}); return have;}
		if (!G->G->emote_code_to_markdown) return w;
		//2) Does the bot have the emote?
		string md = G->G->emote_code_to_markdown[w];
		if (md && sscanf(md, "%*s/v1/%d/1.0", int id)) return img(w, id);
		//3) Is it in the hard-coded list of known emote IDs?
		int|string id = emoteids[w];
		if (id) return img(w, id);
		return w;
	});
	return render_template("checklist.md", ([
		"login_link": login_link,
		"text": text, "emotes": sprintf("img[title=\"%s\"]", used[*]) * ", ",
	]));
}

int message(object channel, mapping person, string msg) {
	if (!person->uid || !person->emotes || !sizeof(person->emotes)) return 0;
	mapping v2 = G->G->emotes_v2;
	mapping seen = persist_status->path("seen_emotes")[(string)person->uid];
	mapping emotes = G->G->emote_code_to_markdown || ([]); //If not set, don't crash, just ignore them
	mapping botemotes = person->uid == G->G->bot_uid && persist_status->path("bot_emotes");
	foreach (person->emotes, [string id, int start, int end]) {
		if (botemotes) {
			string code = msg[start..end];
			if (!has_value(code, '_') && !botemotes[code]) {
				botemotes[code] = id;
				//Note: Uses the v2 URL scheme even if it's v1 - they seem to work
				emotes[code] = sprintf("![%s](https://static-cdn.jtvnw.net/emoticons/v2/%s/default/light/1.0)", code, id);
			}
		}
		string emotename = v2[id];
		if (!emotename) continue;
		if (!seen) seen = persist_status->path("seen_emotes", (string)person->uid);
		seen[emotename] = time();
		persist_status->save();
	}
}

protected void create(string name) {
	::create(name);
	//List of emotes to track - specifically, all the v2 emote IDs shown in the checklist.
	//No other emotes will be tracked, and we assume in general that these emotes will not
	//ever be lost. If they are, there'll need to be some way to say "purge those I haven't
	//used in X seconds", which will be possible, since they're stored with their timestamps.
	mapping v2 = filter(emoteids, stringp);
	G->G->emotes_v2 = mkmapping(values(v2), indices(v2));
	register_hook("all-msgs", message);
}

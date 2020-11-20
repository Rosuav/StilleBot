inherit http_endpoint;

//Markdown; emote names will be replaced with their emotes, but will
//be greyed out if not available.
//NOTE: The display is aimed at no more than six emotes across.
constant hypetrain = replace(#"
## Hype Train set three
### Unlockable Nov 2020 to current
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
//For emotes that the bot has, we can get their IDs from the API.
//For others, list them here and they'll work.
constant emoteids = ([
	"HypeOni6": 301205427, "OWL2019Tracer": 1833318,
	"PrimeYouDontSay": 134251, "PrimeUWot": 134252, "PrimeRlyTho": 134253,
	//L1 hype
	"HypeFighter": 304420773, "HypeShield": 304420921, "HypeKick": 304420811,
	"HypeRIP": 304420886, "HypeGG": 304420784,
	//L2 hype
	"HypeRanger": 304420869, "HypeMiss": 304420830, "HypeHit": 304420797,
	"HypeHeart": 304420791, "HypeTarget": 304421037, "HypeWink": 304421058,
	//L3 hype
	"HypeRogue": 304420899, "HypeWut": 304421062, "HypeGems": 304420779,
	"HypeCoin": 304420761, "HypeSneak": 304421025, "HypeCash": 304420757,
	//L4 hype
	"HypeBard": 304420723, "HypeTune": 304421042, "HypeRun": 304420909,
	"HypeZzz": 304421067, "HypeRock": 304420892, "HypeJuggle": 304420806,
	//L5 hype
	"HypeMage": 304420826, "HypeWho": 304421049, "HypeLol": 304420818,
	"HypePotion": 304420861, "HypeBook": 304420732, "HypeSmoke": 304420932,
]);

Regexp.PCRE.Studied words = Regexp.PCRE.Studied("\\w+");

string img(string code, int id)
{
	return sprintf("<figure>![%s](https://static-cdn.jtvnw.net/emoticons/v1/%d/3.0)"
		"<figcaption>%[0]s</figcaption></figure>", code, id);
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	object ret = Concurrent.resolve(0);
	mapping emotesets = ([]);
	string login_link = "[Log in to highlight the emotes you have access to](/twitchlogin?next=/checklist&scopes=user_subscriptions)";
	if (req->misc->session->?scopes->?user_subscriptions)
	{
		login_link = "<input type=checkbox id=showall>\n\n<label for=showall>Show all</label>";
		ret = ret->then(lambda() {return twitch_api_request("https://api.twitch.tv/kraken/users/{{USER}}/emotes",
			(["Authorization": "OAuth " + req->misc->session->token]),
			(["username": req->misc->session->user->login]));
			})->then(lambda(mapping info) {
				info->fetchtime = time();
				emotesets = info->emoticon_sets;
			});
	}
	return ret->then(lambda() {
		mapping have_emotes = ([]);
		array(string) used = ({ }); //Emote names that we have AND used
		foreach (emotesets;; array set) foreach (set, mapping em)
			have_emotes[em->code] = img(em->code, em->id);
		string text = words->replace(hypetrain, lambda(string w) {
			//1) Do we (the logged-in user) have the emote?
			if (string have = have_emotes[w]) {used += ({w}); return have;}
			//2) Does the bot have the emote?
			string md = G->G->emote_code_to_markdown[w];
			if (md && sscanf(md, "%*s/v1/%d/1.0", int id)) return img(w, id);
			//3) Is it in the hard-coded list of known emote IDs?
			int id = emoteids[w];
			if (id) return img(w, id);
			return w;
		});
		return render_template("checklist.md", ([
			"login_link": login_link,
			"text": text, "emotes": sprintf("img[title=\"%s\"]", used[*]) * ", ",
		]));
	});
}

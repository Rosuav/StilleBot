inherit http_websocket;
inherit hook;
inherit annotated;

//Markdown; emote names will be replaced with their emotes, but will
//be greyed out if not available.
//NOTE: The display is aimed at no more than six emotes across.
constant hypetrain = replace(#"
## Hype Train set nine
### Unlockable Apr 2025 to current
### The fourth column unlocked in Jul 2025
SpillTheTea ThatsAServe WhosThisDiva ConfettiHype<br>
RespectfullyNo ThatsIconique HerMind ImSpiraling<br>
NoComment DownBad UghMood ShyGhost<br>
TheyAte PlotTwist AnActualQueen LilTrickster<br>
PackItUp InTheirBag SpitTheTruth PufferPop<br>
(10) BleedPurpleHD (25) HeyHeyGuys (50) PogChomp (100) KappaInfinite<br>
(111) ShouldICelebrate<br>
Note that set eight can also still be unlocked.

## Holidays 2024
### Unlockable via Shared Chat during holidays
May:<br>SSSsssplode<br>
October:<br>TreatCorn TrickCorn<br>
December:<br>LightsSwirl LightsBlink LightsTwinkle CatintheChat<br>

## Hype Train set eight
### Unlockable May 2024 to Dec 2024 and Jan 2025 to current
FrogPonder ChillGirl ButtonMash BatterUp GoodOne MegaConsume<br>
AGiftForYou KittyHype DangerDance PersonalBest HenloThere GimmeDat<br>
MegaMlep RawkOut FallDamage RedCard ApplauseBreak TouchOfSalt<br>
KittyLove TurnUp CatScare LateSave NoTheyDidNot BeholdThis<br>
RaccoonPop GoblinJam YouMissed GriddyGoose CheersToThat StirThePot<br>
(10) BleedPurpleHD (25) HeyHeyGuys (50) PogChomp (100) KappaInfinite<br>
(max) DidIBreakIt<br>

## Hype Train set seven
### Unlockable Jan 2024 to Apr 2024
### Note that these are rereleases from older sets
### Starting 20240327, getting past level 5 has more emotes!
LuvPeekL LuvPeekR LuvBlush LuvHearts LuvSign<br>
HahaBall 2020Rivalry 2020Wish 2020ByeGuys 2020Celebrate<br>
RPGAyaya HahaCat RPGGhosto PrideWingR PrideWingL<br>
2020Party 2020Pajamas 2020Shred 2020Snacking 2020Glitchy<br>
PrideUwu PrideLaugh PrideCute PridePog PrideFloat<br>

## Hype Train set six
### Unlockable Dec 2023 to Jan 2024 and Dec 2024 to Jan 2025
HypeCute HypeYummy HypeKEKW HypeNoods HypeOho<br>
HypeHi HypeChill HypeMyHeart HypeWarm HypeFist<br>
HypeCries HypeGGEyes HypeAwh HypeElf HypeDelight<br>
HypeNotLikeSnow HypePls HypeMelt HypeCocoa HypeConfetti<br>
HypeSanta HypePeek HypeOhDeer HypeUwu HypeLick<br>

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
	//Pride emotes, now part of hype trains
	"PrideUwu": "302303590",
	"PrideLaugh": "302303593",
	"PrideCute": "302303594",
	"PridePog": "302303596",
	"PrideFloat": "302303599",
	"PrideWingL": "300354442",
	"PrideWingR": "300354435",
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
	//New bonus emotes for exceeding level 5!
	"BleedPurpleHD": "emotesv2_bf888b2af57b4abd80653dff26768ae5",
	"HeyHeyGuys": "emotesv2_132feb3980ee410e856244931d63fd31",
	"PogChomp": "emotesv2_00659fc4ae6948a6b23585e83f62d477",
	"KappaInfinite": "emotesv2_ae9328d25e4b424c8dd2af714045e538",
	"DidIBreakIt": "emotesv2_6d23a98b64ad45d9a9c78cb7e48908d6",
	//Hype train set 8
	"FrogPonder": "emotesv2_a3cdcbfcae9b41bb8215b012362eea35",
	"ChillGirl": "emotesv2_7fa0ba50748c418d956afa59c2e94883",
	"ButtonMash": "emotesv2_92d34a3642744c6bb540b091d3e9e9b0",
	"BatterUp": "emotesv2_bc2ca1d0a58b4731a9fc3432cb175c86",
	"GoodOne": "emotesv2_692f743d3e7147068bb1ddf842f9b99d",
	"MegaConsume": "emotesv2_aa8db3de21e1465dab81bedfa47e29f2",
	"AGiftForYou": "emotesv2_e7c9f4491c9b44d68e41aff832851872",
	"KittyHype": "emotesv2_3969f334f5a2425d9fad53daabb06982",
	"DangerDance": "emotesv2_da6ee66bc259434085eb866429687941",
	"PersonalBest": "emotesv2_20a5c29af55240d4a276e0ffd828db3e",
	"HenloThere": "emotesv2_18479de9ad48456aab82a8c9e24e864b",
	"GimmeDat": "emotesv2_0d9792a1c8d3499cac7c2b517dc0f682",
	"KittyLove": "emotesv2_3e61175d445245838665fff146bd2bb0",
	"TurnUp": "emotesv2_8b79f878cfff4671ae0fb7522c69ea07",
	"CatScare": "emotesv2_1cce76af186d4022821e8e67bb367055",
	"LateSave": "emotesv2_e8236afbc65347ebb4938c6507a78012",
	"NoTheyDidNot": "emotesv2_94736686188047bab48c9e2ca9666496",
	"BeholdThis": "emotesv2_cef4e35f8d134fbc8172fe622bc51bfe",
	"RaccoonPop": "emotesv2_1d68d57fa07a4636aa3325e95c85f19a",
	"GoblinJam": "emotesv2_f033a950174e447cb68a3380ed9da914",
	"YouMissed": "emotesv2_b13f48e4ca704d1cb13123631467616e",
	"GriddyGoose": "emotesv2_c7aefc45412147b284273098a518c94b",
	"CheersToThat": "emotesv2_b308322f860543f78e046294a9614c68",
	"StirThePot": "emotesv2_827188949087491ab7d44ecfbfb4e58c",
	"MegaMlep": "emotesv2_2a52b54c6fb04a6fbb6b9eb51fa8e0d0",
	"RawkOut": "emotesv2_91b3e913c6484fca894830ab953aa16b",
	"FallDamage": "emotesv2_8120b15b9e054b31a200a5cb6cade4c7",
	"RedCard": "emotesv2_a83f8ade02cd4b37b8ae079584407c66",
	"ApplauseBreak": "emotesv2_c3db311615df4ecb9e3be0c492fbfc8b",
	"TouchOfSalt": "emotesv2_871fb6fa55d54fae8e807198c59e082f",
	"SSSsssplode": "emotesv2_df1b3a19d9fc4bff81429afdfb46fff0",
	"TreatCorn": "emotesv2_0672054d322f4bd7a176b905b612810b",
	"TrickCorn": "emotesv2_e1623767957941d3960a16bab644b53e",
	"LightsSwirl": "emotesv2_beda979b077141acaa5fb0196e52a544",
	"LightsBlink": "emotesv2_f1337249b2ac4482ad1a9318bf2018f2",
	"LightsTwinkle": "emotesv2_2d3b718f2de34770ba2e61cfbc270a58",
	"CatintheChat": "emotesv2_a7768ce4552c4a3abdd0404f556f958e",
	//Hype train set 9
	"SpillTheTea": "emotesv2_3f209a93967a4f53909b3e83932eb883",
	"ThatsAServe": "emotesv2_71276b021c024affa2a4ffab59d32c56",
	"WhosThisDiva": "emotesv2_fdd2673444124ccb95745918e6946ebc",
	"RespectfullyNo": "emotesv2_8c5bc9cb160640c29423076da8cf692d",
	"ThatsIconique": "emotesv2_df29fd5cc4f8436a90c0f782d828b366",
	"HerMind": "emotesv2_2eb03cdc9a6240d4bf71d44bfbfdcbd3",
	"NoComment": "emotesv2_9d63f5aa1af3476b86b9c20a6e747dc2",
	"DownBad": "emotesv2_33cd123685f84ecb9899838472c55391",
	"UghMood": "emotesv2_393644bfc50c49498152f75b56f0ce22",
	"TheyAte": "emotesv2_f47a86e7457e440ab3fff868b2d5186e",
	"PlotTwist": "emotesv2_2a1863780183434da7beeb7e9a42eb34",
	"AnActualQueen": "emotesv2_5e4904678f50485aaac4fca44f03b570",
	"PackItUp": "emotesv2_2789bf0b8a4346a6900f24265733439b",
	"InTheirBag": "emotesv2_84f6901b23f54c5fbd9cdcc0ba66cb93",
	"SpitTheTruth": "emotesv2_a5df5c36d31640659aba8fe8641e0ba8",
	"ShouldICelebrate": "emotesv2_3cef4c51d4aa45be822ee327f97650a0",
	//Hype train set 9a
	"ConfettiHype": "emotesv2_bbbf6d16d9964fcbba2d965a7eea942f",
	"ImSpiraling": "emotesv2_44b6eb2a20e44887bb8b158869671619",
	"ShyGhost": "emotesv2_9c489ffe04e14791b1fc300872605ac1",
	"LilTrickster": "emotesv2_6f8b5741535344bf947ae6eea28c56c7",
]);

Regexp.PCRE.Studied words = Regexp.PCRE.Studied("\\w+");

@retain: mapping(string:multiset(string)) user_emotes = ([]); //Cached but easily purged

string img(string code, int|string id)
{
	return sprintf("<figure>![%s](%s)"
		"<figcaption>%[0]s</figcaption></figure>", code, emote_url((string)id, 3));
}

string parsed_emote_text;
mapping valid_showcase_groups = ([]); //After verifying, is valid for 60 seconds.

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string login_link = "[Log in to highlight the emotes you have access to](:.twitchlogin data-scopes=@user:read:emotes@)";
	multiset scopes = req->misc->session->?scopes || (<>);
	string title = "Emote checklist";
	string group = req->misc->session->?user->?id;
	if (string id = req->variables->showcase) {
		//?showcase=49497888 to see Rosuav's emotes
		//Only if permission granted.
		if (!await(G->G->DB->load_config(id, "is_enabled"))->showcase) return 0;
		title = "Emote showcase for " + await(get_user_info(id))->display_name;
		valid_showcase_groups[group = id] = time() + 60;
	}
	else if (scopes["user:read:emotes"]) {
		login_link = "<input type=checkbox id=showall>\n\n<label for=showall>Show all</label>\n\n"
			"[Enable showcase](:#toggleshowcase)\n\n"
			"[Show off your emotes here](checklist?showcase=" + req->misc->session->?user->?id + ")";
	}
	else login_link += "\n\n<input type=checkbox id=showall style=\"display:none\" checked>"; //Hack: Show all if not logged in
	mapping botemotes = await(G->G->DB->load_config(G->G->bot_uid, "bot_emotes"));
	if (!parsed_emote_text) parsed_emote_text = words->replace(hypetrain, lambda(string w) {
		if (string id = botemotes[w] || emoteids[w]) return img(w, id);
		return w;
	});
	return render(req, ([
		"vars": (["ws_group": group]),
		"login_link": login_link,
		"text": parsed_emote_text, "emotes": "",
		"title": title,
	]));
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (valid_showcase_groups[msg->group] > time()) {
		mapping cred = G->G->user_credentials[(int)msg->group];
		if (has_value(cred->scopes, "user:read:emotes")) update_user_emotes(msg->group, cred->token);
		return 0;
	}
	if (msg->group != conn->session->?user->?id) return "Not you";
	multiset scopes = conn->session->?scopes || (<>);
	if (scopes["user:read:emotes"]) update_user_emotes(conn->session->user->id, conn->session->token);
}
__async__ mapping get_state(string group) {
	return (["emotes": (array)(user_emotes[group] || ({ }))]);
}

__async__ void websocket_cmd_toggleshowcase(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->mutate_config(conn->session->?user->?id, "is_enabled") {mapping en = __ARGS__[0];
		if (!m_delete(en, "showcase")) en->showcase = 1;
	});
	send_updates_all(conn->group);
}

__async__ void update_user_emotes(string userid, string token) {
	//TODO: Fetch the template from Twitch; currently it's being discarded in the get_helix_paginated processing
	string template = "https://static-cdn.jtvnw.net/emoticons/v2/{{id}}/{{format}}/{{theme_mode}}/{{scale}}";
	array emotes = await(get_helix_paginated("https://api.twitch.tv/helix/chat/emotes/user", ([
		"user_id": userid,
		//"broadcaster_id": channel_id, //optionally include follower emotes from that channel
	]), (["Authorization": "Bearer " + token])));
	user_emotes[userid] = (multiset)emotes->name; //Ignore all else and just keep the emote names (eg "DinoDance")
	send_updates_all(userid);
}

@hook_allmsgs: int message(object channel, mapping person, string msg) {
	if (!person->uid || !person->emotes || !sizeof(person->emotes)) return 0;
	multiset emotes = user_emotes[(string)person->uid]; if (!emotes) return 0;
	int changed = 0;
	foreach (person->emotes, [string id, int start, int end])
		if (!emotes[id]) emotes[id] = changed = 1;
	if (changed) send_updates_all((string)person->uid);
}

protected void create(string name) {::create(name);}

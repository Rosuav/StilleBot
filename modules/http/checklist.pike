inherit http_endpoint;

//Markdown; emote names will be replaced with their emotes, but will
//be greyed out if not available.
constant hypetrain = #"
## Set one
HypeBigfoot1 HypeBigfoot2 HypeBigfoot3 HypeBigfoot4 HypeBigfoot5 HypeBigfoot6<br>
HypeGriffin1 HypeGriffin2 HypeGriffin3 HypeGriffin4 HypeGriffin5 HypeGriffin6<br>
HypeOni1 HypeOni2 HypeOni3 HypeOni4 HypeOni5 HypeOni6<br>
HypeDragon1 HypeDragon2 HypeDragon3 HypeDragon4 HypeDragon5 HypeDragon6<br>
HypeUnicorn1 HypeUnicorn2 HypeUnicorn3 HypeUnicorn4 HypeUnicorn5 HypeUnicorn6<br>

## Set two
HypeChimp HypeGhost HypeChest HypeFrog HypeCherry HypePeace<br>
HypeSideeye HypeBrain HypeZap HypeShip HypeSign HypeBug<br>
HypeYikes HypeRacer HypeCar HypeFirst HypeTrophy HypeBanana<br>
HypeBlock HypeDaze HypeBounce HypeJewel HypeBlob HypeTeamwork<br>
HypeLove HypePunk HypeKO HypePunch HypeFire HypePizza<br>
";
//For emotes that the bot has, we can get their IDs from the API.
//For others, list them here and they'll work.
constant emoteids = ([
	"HypePeace": 301739470, "HypeBug": 301739471, "HypeBanana": 301739487,
	"HypeTeamwork": 301739494, "HypePizza": 301739502, "HypeOni6": 301205427,
]);

Regexp.PCRE.Studied words = Regexp.PCRE.Studied("\\w+");

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "user_subscriptions")) return resp;
	object ret = Concurrent.resolve(0);
	mapping emotelist;
	if (!emotelist) //TODO: Cache this for a bit (and then skip this block if found in cache)
		ret = ret->then(lambda() {return twitch_api_request("https://api.twitch.tv/kraken/users/{{USER}}/emotes",
			(["Authorization": "OAuth " + req->misc->session->token]),
			(["username": req->misc->session->user->login]));
			})->then(lambda(mapping info) {
				info->fetchtime = time();
				emotelist = info;
			});
	return ret->then(lambda() {
		mapping have_emotes = ([]);
		array(string) used = ({ }); //Emote names that we have AND used
		foreach (emotelist->emoticon_sets;; array set) foreach (set, mapping em)
			have_emotes[em->code] = sprintf("![%s](https://static-cdn.jtvnw.net/emoticons/v1/%d/3.0)", em->code, em->id);
		string text = words->replace(hypetrain, lambda(string w) {
			//1) Do we (the logged-in user) have the emote?
			if (string have = have_emotes[w]) {used += ({w}); return have;}
			//2) Does the bot have the emote?
			string md = G->G->emote_code_to_markdown[w];
			if (md) return replace(md, "/1.0", "/3.0");
			//3) Is it in the hard-coded list of known emote IDs?
			int id = emoteids[w];
			if (id) return sprintf("![%s](https://static-cdn.jtvnw.net/emoticons/v1/%d/3.0)", w, id);
			return w;
		});
		return render_template("checklist.md", ([
			"backlink": "", "text": text,
			"emotes": sprintf("img[title=\"%s\"]", used[*]) * ", ",
		]));
	});
}

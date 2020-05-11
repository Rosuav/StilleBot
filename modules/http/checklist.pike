inherit http_endpoint;

//Markdown; emote names will be replaced with their emotes, but will
//be greyed out if not available.
constant hypetrain = #"
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
	"HypeTeamwork": 301739494, "HypePizza": 301739502,
]);

Regexp.PCRE.Studied words = Regexp.PCRE.Studied("\\w+");

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string user = req->variables->user;
	if (!user)
	{
		return render_template("checklist.md",
			(["backlink": "","text": words->replace(hypetrain, lambda(string w) {
				string md = G->G->emote_code_to_markdown[w];
				if (md) return replace(md, "/1.0", "/3.0");
				int id = emoteids[w];
				if (id) return sprintf("![%s](https://static-cdn.jtvnw.net/emoticons/v1/%d/3.0)", w, id);
				return w;
			}),
		]));
	}
	object ret = Concurrent.resolve(0);
	mapping emotelist;
	if (!emotelist) //TODO: Cache this for a bit (and then skip this block if found in cache)
		ret = ret->then(lambda() {return twitch_api_request("https://api.twitch.tv/kraken/users/{{USER}}/emotes",
			0, (["username": user]));
			})->then(lambda(mapping info) {
				info->fetchtime = time();
				emotelist = info;
			});
	return ret->then(lambda() {
		return ([
			"data": Standards.JSON.encode(emotelist, 7),
			"type": "application/json",
		]);
	});
}

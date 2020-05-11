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

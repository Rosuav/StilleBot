inherit http_endpoint;
constant markdown = #"# Quizgram

<style>
input.ltr {font-size: 100%; width: 1.25em; text-transform: uppercase; text-align: center;}
input[readonly].ltr {background: aliceblue;}
img[alt=\"Avatar\"] {max-height: 2em; vertical-align: middle;}
.word {margin-right: 0.3em;}
</style>

## `_____` `___` `__` `________`, `____` `_____` `_________`.
## - `___` `____`

---

### DeviCat
1. What is the channel mascot's name? `_-15-______`
2. What is Devi's favorite color? `__-34-_`

### CamaeSoultamer
1. What level of chaos is acceptable? `_-3-__`
2. What is Camae's favourite colour? `_____-1-` `_____`
3. Name the cat who hangs out on stream. `_____-40-`

### ABluSkittle
1. What kind of animals get hidden in all Skittle's art? `-29-___`

### RissaBunn
1. How many children does Rissa have? `__-10-`
2. What kind of cat is Tsuki? `___-35-__`

### Maaya
1. Maaya's raid call derives from a song from which band? `_`-`__-20-_`

### LexSin81
1. What's the adorable pink plushie's name? `-18-_____`

### Lolalli
1. What is Lolalli's favourite art medium? `___-27-____`

### LisaJarwal
1. What anatomical feature is emphasized in Lisa's art? `_-22-__`
2. What is Lisa's cat's name? `___-11-_`

### MangoLily0
1. What would Mango bring to the pot-luck? `___-16-__`
2. Who's the girl who runs the chat? `_____-7-___`

### SharpBalloons
1. What's the special cleanup tool called? `_____-5-_`
2. How does the raid saber make that noise? `-13-___________`

### StaticTides
1. How many cosplays has Static done? `-14-__` `____` and counting!
2. What is Static's favourite colour? `_____` `___-39-`
3. What's the cat's full name? `_____-6-_`

### AtomicKawaii
1. What is everything made of? `-33-___`
2. When will the placeholder commands be fixed? `-9-____`

### 1Neila1
1. Who's the alien sometimes seen on stream? `__-24-_`

### Wenffyria
1. What kind of animal is Bowlie? `_-41-___` `____`

### PantoufflesArt
1. Name the resident dog: `_-28-_`
2. What's the name of the channel mascot? `-43-_____`
3. What's Pan's favourite flower? `______-31-_`

### YarnCraftersCorner
1. What's the type of spindle used here, with two arms? `______-23-`
2. What variety of pet will visit the stream? `_-38-__`

### Suitedx
1. What is Suited's void called? `_-17-__`
2. Complete this quote: `_____-37-` ME, DEATH
3. What does a six-month subscriber become? `_-19-____`

### Blighted_Angel
1. What is Angel's favourite colour? `-4-__`
2. Who deserves treats? `________`, `_______-30-__`, and `______`

### Linvalin
1. What's Lin's favourite Pokemon? `__-25-_____`
2. What are Lin's community members called? `____` `___-12-___`
3. Name Lin's main OC: `_-2-___`
";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	array parts = markdown / "\n### ";
	foreach (parts; int i; string text) {
		if (!i) continue; //Skip the initial blob
		sscanf(text, "%s\n%s", string channel, text);
		mapping user = await(get_user_info(channel, "login"));
		parts[i] = sprintf("%s\n[![Avatar](%s) Visit %s's channel](https://twitch.tv/%s :target=_blank)\n\n%s", channel, user->profile_image_url, user->display_name, user->login, text);
	}
	return render_template(parts * "\n### ", (["js": "quizgram.js"]));
}

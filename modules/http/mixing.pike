inherit http_websocket;

constant markdown = #"# Diffie Hellman Paint Mixing

<style>
.swatch {display: inline-block; width: 200px; height: 150px; border: 1px solid black;}
.small {width: 80px; height: 60px;}
.label {display: inline-block; height: 90px;}
.design {display: flex; margin: 8px 0; gap: 5px;}
$$colors$$
</style>

$$swatches$$
";

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
	"Bulker": STANDARD_BASE[*] * 2, //Special-case this one and don't show swatches.
	"Charcoal": ({0x44, 0x45, 0x4f}),
	"Beige": STANDARD_BASE,
	//Special-case this one. Swatch it as a vibrant crimson (fresh blood), but use the actual "Blood" value for mixing (old blood).
	"Blood-fresh": ({0xAA, 0, 0}),
	"Blood": ({0x7E, 0x35, 0x17}),
]);
constant PIGMENT_DESCRIPTIONS = ([
	"Crimson": "It's red. What did you expect?",
	"Jade": "Derived from pulverised ancient artifacts. Probably not cursed.",
	"Cobalt": "Like balt, but the other way around",
	"Hot Pink": "Use it quickly before it cools down!",
	"Orange": "For when security absolutely depends on not being able to rhyme",
	"Lawn Green": "Not to be confused with Australian Lawn Green, which is brown",
	"Spring Green": "It's a lie; most of my springs are unpainted",
	"Sky Blue": "Paint your ceiling in this colour and pretend you're outside!",
	"Orchid": "And Kid didn't want to participate, so I got his brother instead",
	"Rebecca Purple": "A tribute to Eric Meyer's daughter. #663399",
	"Chocolate": "Everything's better with chocolate.",
	"Alice Blue": "Who is more famous - the president or his wife?",
	"Mint Mus": "Definitely not a frozen dessert.",
	"Bulker": "Add some more base colour to pale out your paint",
	"Charcoal": "Dirty grey for when vibrant colours just aren't your thing",
	"Beige": "In case the default beige just isn't beigey enough for you",
	"Blood": "This pigment is made from real blood. Use it wisely.",
]);
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
	return sprintf("%02X%02X%02X", @min(((array(int))color)[*], 255));
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
	mapping colors = (["base": hexcolor(STANDARD_BASE)]);
	array swatches = ({ });
	//TODO: Abstract this stuff out and make it tidier, don't just build HTML
	foreach (PIGMENTS; string name; array modifier) {
		string desc = PIGMENT_DESCRIPTIONS[name] || "(null)";
		name -= " ";
		array color = STANDARD_BASE;
		array design = ({({"swatch base", "Base"})});
		colors[name] = hexcolor(modifier);
		foreach (STRENGTHS, string strength) {
			color = mix(color, modifier);
			string ns = name + "-" + strength;
			design += ({({"swatch " + ns, ns})});
			colors[ns] = hexcolor(color);
		}
		design += ({({"swatch " + name, sprintf("<abbr title=\"%s\">%s</abbr>", desc, name)})});
		swatches += ({design});
	}
	void add_pattern(string name, array pattern) {
		array color = STANDARD_BASE;
		array design = ({({"small base", "Base"})});
		foreach (pattern; int i; [string pigment, int strength]) {
			for (int s = 0; s < strength; ++s)
				color = mix(color, PIGMENTS[pigment]);
			design += ({({sprintf("swatch small %s-%d", name, i + 1), sprintf("%s<br>(%s)", pigment, STRENGTHS[strength - 1])})});
			colors[name + "-" + (i+1)] = hexcolor(color);
		}
		colors[name] = hexcolor(color);
		design += ({({"label", sprintf("==&gt; %s:<br>%s", name, hexcolor(color))})});
		swatches += ({design});
	}
	//This part would be replaced with real-time stuff that depends on the user.
	add_pattern("Foo", ({({"Crimson", 3}), ({"Jade", 1})}));
	add_pattern("Bar", ({({"Jade", 1}), ({"Crimson", 3})}));
	add_pattern("Fum", ({({"Crimson", 2}), ({"Jade", 1}), ({"Crimson", 1})}));
	array KEY1 = ({({"Lawn Green", 3}), ({"Hot Pink", 1}), ({"Alice Blue", 3}), ({"Crimson", 1}), ({"Orchid", 3})});
	array KEY2 = ({({"Orchid", 2}), ({"Cobalt", 3}), ({"Bulker", 3}), ({"Chocolate", 1}), ({"Rebecca Purple", 1})});
	add_pattern("Spam", KEY1 + KEY2);
	add_pattern("Ham", KEY2 + KEY1);
	return render(req, ([
		//"vars": (["ws_group": req->misc->session->user->id]),
		"colors": sprintf("%{.%s {background: #%s;}\n%}", sort((array)colors)),
		"swatches": sprintf("<div class=design>%{<div class=\"%s\">%s</div>%}</div>", swatches[*]) * "\n",
	]));
}

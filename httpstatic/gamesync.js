import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, DIV, FORM, H1, H2, INPUT, LABEL, OPTION, SELECT, SPAN, STYLE, TABLE, TD, TH, TR} = lindt; //autoimport

let last_data = { };

function BUTTONBOX(data, name, selected, options) {
	return options.map(opt =>
		typeof opt === "object" ? opt :
		BUTTON({"data-setting": name, "data-value": opt, ...(data[name] === opt ? selected : {})}, opt)
	);
}

const games = {
	goldengrin: {
		label: "Payday 2: Golden Grin Casino",
		drink_colors: [["Green", "#7f7"], ["Blue", "#99f"], ["Pink", "#f7d"], ["Red", "#f77"]],
		render(data) {return [
			H2("Bars"),
			TABLE(["Pool", "VIP", "Above Ladies", "Above VIP"].map(bar => TR([
				TD(bar),
				this.drink_colors.map(([name, col]) => TD(
					BUTTON({
						"data-setting": "drink-" + name, "data-value": bar,
						"style": data["drink-" + name] === bar ? "background-color: " + col : "",
					}, name),
				)),
			]))),
			H2("Codes and locations"),
			TABLE([
				TR([TD("Room"), TD(BUTTONBOX(data, "room", {style: "background-color: black; color: white"},
					["99", "100", "101", "102", "103", "104", "105", BR(),
						"150", "151", "152", "153", "154", "155"]))]),
				TR([TD("Code"), TD([
					INPUT({"data-setting": "code-red", style: "background-color: red; color: white", type: "number", value: data["code-red"]}),
					INPUT({"data-setting": "code-green", style: "background-color: green; color: white", type: "number", value: data["code-green"]}),
					INPUT({"data-setting": "code-blue", style: "background-color: blue; color: white", type: "number", value: data["code-blue"]}),
				])]),
				TR([TD("Recep PC"), TD(BUTTONBOX(data, "recep", {style: "background-color: black; color: white"},
					["Left", "Center", "Right"]))]),
				TR([TD("Pit boss"), TD(BUTTONBOX(data, "pitboss", {style: "background-color: black; color: white"},
					["VIP", "Reception", "Above Gents"]))]),
			]),
			H2("Drinks"),
			TABLE([
				TR([TD("Gents"), TD(this.drink_colors.map(([name, col]) =>
					BUTTON({
						"data-setting": "Gents", "data-value": name,
						"style": data.Gents === name? "background-color: " + col : "",
					}, name))
				)]),
				TR([TD("Smoko"), TD(this.drink_colors.map(([name, col]) =>
					BUTTON({
						"data-setting": "Smoko", "data-value": name,
						"style": data.Smoko === name? "background-color: " + col : "",
					}, name))
				)]),
			]),
		];},
	},
	yacht: {
		label: "Payday 2: The Yacht Heist",
		tag_colors: {Green: "#0f0", Blue: "#4fe", Yellow: "#ff0", Red: location.search.includes("minimode") ? "#f77" : "#f11", White: "#fff"},
		tagset(data, deck, opts) {
			return [H2(deck), DIV({class: "tags"}, opts.map(loc => BUTTON({
				"data-setting": deck + "-" + loc.split(" ")[0], "data-value": loc,
				"style": data[deck + "-" + loc.split(" ")[0]] === loc ? "background-color: " + this.tag_colors[data.color] : ""
			}, loc)))];
		},
		render(data) {return [
			H2("Tag"),
			STYLE(".tags {display: flex; gap: 1.5em; justify-content: center; flex-wrap: wrap} .tags button {height: 2.5em; width: 6em; font-size: 150%}"),
			DIV({class: "tags"}, Object.entries(this.tag_colors).map(([name, col]) =>
				BUTTON({
					"data-setting": "color", "data-value": name,
					"style": data.color === name ? "background-color: " + col : "",
				}, name),
			)),
			this.tagset(data, "Lower Deck", ["Fridge"]), //Theoretically Cabinet, but never seen it
			this.tagset(data, "Main Deck", ["Cigar/Wine", "Lifeboat", "Aquarium", "Food cart"]),
			BR(),
			DIV({class: "tags"}, BUTTONBOX(data, "room", {style: "background-color: " + this.tag_colors[data.color]}, ["101", "102", "103", "104"])),
			this.tagset(data, "Upper 01", ["Food cart", "Aquarium"]),
			this.tagset(data, "Upper 02", ["Bookshelf", "Food cart"]),
		];},
	},
	murkystation: {
		label: "Payday 2: Murkywater Station",
		TRAINCAR(data, id) {return [DIV({class: "traincar"}, [
			SPAN({style: "padding: 0 3em 0 1em"}, id + " "),
			SELECT({"data-setting": "traincar-mode-" + id, value: data["traincar-mode-" + id]}, [
				OPTION(""),
				OPTION("Empty"), OPTION("Empty (open)"),
				OPTION("Has panel"), //Might contain loot or EMP - most likely not opened yet
				OPTION("Contains loot"), OPTION("Contains EMP"),
				OPTION("Loot removed"),
			]),
			" ",
			SELECT({"data-setting": "traincar-lock-" + id, value: data["traincar-lock-" + id]}, [
				OPTION(""),
				OPTION("Keycard"),
				OPTION("Blowtorch"),
				OPTION("Thermite"),
				OPTION("Hard drive"),
			]),
		])];},
		render(data) {return [
			H2("Dock (north end)"),
			STYLE(".row {display: flex; gap: 1.5em; justify-content: space-between} .row > * {width: 30%} .traincar {border: 1px solid black; padding: 10px 6px;}"),
			DIV({class: "row"}, [this.TRAINCAR(data, "06"), this.TRAINCAR(data, "07"), DIV("Whiteboard")]), //whiteboard is outside train yard in low difficulty
			DIV({style: "padding: 0 10%"}, "[ Ladder ]"),
			DIV({class: "row"}, [this.TRAINCAR(data, "05"), this.TRAINCAR(data, "04"), this.TRAINCAR(data, "03")]),
			DIV({style: "display: flex; flex-direction: row-reverse; padding: 0 10%"}, DIV("[ Ladder ]")),
			DIV({class: "row"}, [this.TRAINCAR(data, "01"), this.TRAINCAR(data, "02"), DIV({class: "traincar", style: "text-align: center"}, "Loco")]),
			H2("Bridge (south end)"),
		];},
	},
	bordercrossing: {
		label: "Payday 2: Border Crossing",
		render(data) {return [
			H2("USA side"),
			STYLE(".row {font-size: 200%; margin: 1em;} select {font-size: 100%;}"),
			DIV({class: "row"}, LABEL(["Reset code: ", SELECT(
				{"data-setting": "unlock-reset", value: data["unlock-reset"]}, [
				OPTION(""),
				OPTION("0000"),
				OPTION("1111"),
				OPTION("1234"),
			])])),
			DIV({class: "row"}, LABEL(["First arrest: ", SELECT(
				{"data-setting": "unlock-arrest", value: data["unlock-arrest"]}, [
				OPTION(""),
				OPTION("2002"),
				OPTION("2017"),
			])])),
			DIV({class: "row"}, LABEL(["Club founded: ", SELECT(
				{"data-setting": "unlock-founding", value: data["unlock-founding"]}, [
				OPTION(""),
				OPTION("2008"),
				OPTION("2009"),
			])])),
			DIV({class: "row"}, LABEL(["Graffiti: ", SELECT(
				{"data-setting": "unlock-graffiti", value: data["unlock-graffiti"]}, [
				OPTION(""),
				OPTION("0455"),
				OPTION("4828"),
				OPTION("5137"),
			])])),
			H2("Mexico side"),
			DIV([
				"Tip: Have two players grab keycards from USA and bring them. Otherwise, there's one available here.",
				" Don't waste keycards on the cages; have one player unlock them upstairs while the other slips inside.",
			]),
		];},
	},
	sanmartin: {
		label: "Payday 2: San Martín Bank",
		light_colors: {Red: "#f11", Green: "#0f0", Blue: "#4fe", Yellow: "#ff0"},
		render(data) {return [
			H2("Manager"),
			DIV([
				"Manager: ", SELECT({"data-setting": "manager-location", value: data["manager-location"]}, [
					OPTION("Kitchenette"),
					OPTION("Meeting room"),
					OPTION("Lounge"),
				]),
				" Tape: ", SELECT({"data-setting": "tape-location", value: data["tape-location"]}, [
					OPTION("Inside mtg room"),
					OPTION("Outside mtg room"),
				]),
			]),
			H2("Lock lights (pick two)"),
			STYLE(".lights {display: flex; gap: 3.5em; justify-content: center; flex-wrap: wrap} .lights > * {height: 2.5em; width: 6em; font-size: 150%; text-align: center}"),
			DIV({class: "lights"}, Object.entries(this.light_colors).map(([name, col]) =>
				BUTTON({
					"data-setting": "color-" + name, "data-value": "on",
					"style": data["color-" + name] === "on" ? "background-color: " + col : "",
				}, name),
			)),
			DIV({class: "lights"}, Object.entries(this.light_colors).map(([name, col]) =>
				INPUT({
					"data-setting": "code-" + name, value: data["code-" + name] || "",
					"style": data["color-" + name] === "on" ? "background-color: " + col : "background-color: grey",
				}, name),
			)),
			H2("Vault duty"),
			DIV([
				"Operator: ", SELECT({"data-setting": "vault-operator", value: data["vault-operator"]}, [
					OPTION("A. Banderas"),
					OPTION("U. Corberó"),
					OPTION("G. del Toro"),
					OPTION("G. Iglesias"),
					OPTION("J. Lopez"),
					OPTION("J. Lorenzo"),
					OPTION("R. R. Mendoza"),
					OPTION("A. C. Montes"),
					OPTION("P. Montoto"),
					OPTION("R. Nadal"),
					OPTION("B. B. Rodriguez"),
					OPTION("S. Segura"),
					OPTION("M. Zamora"),
				]),
				INPUT({"data-setting": "operator-code", value: data["operator-code"] || ""}),
			]),
		];},
	},
	diamondheist: {
		label: "Payday 2: Diamond Heist",
		render(data) {return [
			DIV("Not to be confused with The Diamond heist. Seriously, those sound nothing alike."),
			H2("Entry code"),
			STYLE(".code {display: flex; gap: 4.5em; justify-content: center; flex-wrap: wrap} .code > * {height: 2.5em; width: 6em; font-size: 175%; text-align: center}"),
			DIV({class: "code"}, [
				INPUT({"data-setting": "code-red", style: "background-color: red; color: white", type: "number", value: data["code-red"]}),
				INPUT({"data-setting": "code-green", style: "background-color: green; color: white", type: "number", value: data["code-green"]}),
				INPUT({"data-setting": "code-blue", style: "background-color: blue; color: white", type: "number", value: data["code-blue"]}),
			]),
		];},
	},
	whitehouse: {
		label: "Payday 2: White House",
		light_colors: {Red: "#f11", Green: "#0f0", Blue: "#4fe", Yellow: "#ff0"},
		rooms: [
			{WCorridor: "yellow", OutsideRed: "#faa", Piano: "yellow", OutsideGreen: "#8f8", ECorridor: "yellow"},
			{White: "#000; color: white", Red: "#f55", Blue: "#4fe", Green: "#0f0"},
			{Library: "yellow", Paintings: "yellow", Murals: "yellow", ChinaShop: "yellow"},
		],
		render(data) {return [
			H2("Lock lights (pick two)"),
			STYLE(".lights {display: flex; gap: 3.5em; justify-content: center; flex-wrap: wrap} .lights > * {height: 2.5em; width: 6em; font-size: 150%; text-align: center}"),
			DIV({class: "lights"}, Object.entries(this.light_colors).map(([name, col]) =>
				BUTTON({
					"data-setting": "color-" + name, "data-value": "on",
					"style": data["color-" + name] === "on" ? "background-color: " + col : "",
				}, name),
			)),
			H2("Rooms"),
			TABLE({style: "text-align: center"}, [
				this.rooms.map(row => TR(Object.entries(row).map(([name, col]) => TD([
					SPAN({style: "background-color: " + col}, name), BR(),
					BUTTON({
						"data-setting": "roombox-" + name, "data-value": "on",
						"style": data["roombox-" + name] === "on" ? "background-color: " + col : "",
					}, "Has box"), BR(),
					BUTTON({
						"data-setting": "roomcam-" + name, "data-value": "on",
						"style": data["roomcam-" + name] === "on" ? "background-color: " + col : "",
					}, "Has camera"), BR(),
				])))),
			]),
		];},
	},
	bulucsmansion: {
		label: "Payday 2: Buluc's Mansion",
		render(data) {return [
			H2("Door code"),
			DIV("To open the secret door, you will need to press buttons marked with images. They are identified by original and English names."),
			DIV("The clues give their original names, and the visual representations are shown on the corkboard. The English names are shown in hover text on the door itself."),
			DIV("Note that this has been described as an Aztec calendar, but the words don't appear to be Nahuatl. So I dunno."),
			STYLE(".code {display: flex; gap: 4.5em; justify-content: center; flex-wrap: wrap; margin-top: 1em;} .code > * {font-size: 225%}"),
			DIV({class: "code"}, ["one", "two", "three", "four"].map(idx =>
				SELECT({"data-setting": "code-" + idx, value: data["code-" + idx]}, [
					OPTION(""),
					OPTION("Peek' [Dog]"),
					OPTION("T'u'ul [Rabbit]"),
					OPTION("Ch'i'ibalil [Frog]"),
					OPTION("Kitam [Boar]"),
					OPTION("Buho [Owl]"),
					OPTION("Book' [Bat]"),
					OPTION("Baalam [Jaguar]"),
					OPTION("Batsò [Spider]"),
					OPTION("Cangrejo [Crab]"),
					OPTION("Ba'ats [Monkey]"),
					OPTION("Kaan [Snake]"),
					OPTION("Péepen [Butterfly]"),
					OPTION("Kaaye' [Fish]"),
					OPTION("Cocodrilo [Crocodile]"),
					OPTION("Síinik [Ant]"),
					OPTION("Áak [Turtle]"),
					OPTION("Úuricho' [Snail]"),
					OPTION("Áayin [Lizard]"),
					OPTION("Ku'uk [Squirrel]"),
					OPTION("Milpiés [Millipede]"),
				]),
			)),
			DIV({class: "code"}, [
				SPAN("Card holder"),
				SELECT({"data-setting": "cardholder", value: data.cardholder}, [
					OPTION(""),
					OPTION("Raúl"),
					OPTION("Miguel"),
					OPTION("Sanchez"),
					OPTION("Mucho Mike"),
				]),
				SELECT({"data-setting": "mask", value: data.mask}, [
					OPTION(""),
					OPTION({value: "tiger"}, "Tiger (orange suit, orange mask)"),
					OPTION({value: "blue"}, "?? (blue suit, blue mask)"),
					OPTION({value: "bird"}, "Bird (orange suit, red/yellow mask)"),
					OPTION({value: "mouse"}, "Mouse (red suit, b/w/grey mask)"),
				]),
			]),
		];},
	},
	dragonheist: {
		label: "Payday 2: Dragon Heist",
		render(data) {return [
			STYLE("div,input {font-size: 150%; margin: 0.25em;}"),
			DIV(["Office computer code: ", INPUT({"data-setting": "office-code", value: data["office-code"] || ""})]),
			DIV(["Vault code: ", INPUT({"data-setting": "vault-code", value: data["vault-code"] || ""})]),
		];},
	},
	blackcat: {
		label: "Payday 2: Black Cat",
		render(data) {return [
			STYLE("table,input,select {font-size: 150%; margin: 0.25em;} button {font-size: 125%; margin: 0 0.25em}"),
			DIV("North is the bow of the ship"),
			TABLE([
				TR([TD("Security room:"), TD(SELECT({"data-setting": "security-room", value: data["security-room"]}, [
					OPTION("Casino Port (E)"),
					OPTION("Casino Starboard (W)"),
					OPTION("Crew area"),
					OPTION("Spa"),
				]))]),
				TR([TD("Electrics: "), TD([
					BUTTON({
						"data-setting": "shield-loc", "data-value": "port",
						"style": data["shield-loc"] === "port" ? "background-color: red; color: white" : "",
					}, "Port (W)"),
					BUTTON({
						"data-setting": "shield-loc", "data-value": "starboard",
						"style": data["shield-loc"] === "starboard" ? "background-color: #5f5" : "",
					}, "Starboard (E)"),
				])]),
				TR([TD("Xun Kang's room: "), TD(INPUT({"data-setting": "room", value: data["room"] || ""}))]),
				TR([TD("Vault code: "), TD(INPUT({"data-setting": "vault-code", value: data["vault-code"] || ""}))]),
			]),
		];},
	},
	//For Ukrainian Prisoner, it may be of value to have these recorded:
	//0123456789 --> 零一二三四五六七八九
	//Chinese numerals. Though the game seems pretty merciful in their use, so it may not be necessary.
	//A lot of things are easier with the right assets, eg broken wall and ladder bridge, but w/o them
	//the numerals might come in handy.
};

export function render(data) {
	last_data = data;
	if (data.no_room) return replace_content("main", FORM([
		H1("Game sync"),
		LABEL(["Enter room name: ", INPUT({name: "room"})]),
		BR(),
		BUTTON({type: "submit"}, "Enter room"),
	]));
	replace_content("main", [
		location.search.includes("minimode") ?
			STYLE("body main {max-width: unset; margin: unset; background: transparent; font-size: 50%;} #topbar {display: none;} button {background: #aaa;}")
		: [
			H1(games[data.game] ? games[data.game].label : "Game sync"),
			SELECT({id: "gameselect", value: data.game},
				Object.entries(games).map(([id, info]) => OPTION({value: id}, info.label))),
			DIV({class: "buttonbox"}, [
				BUTTON({type: "button", id: "resetgame"}, "Reset game"),
				data.reset && BUTTON({type: "button", id: "undoreset"}, "Undo Reset"),
				A({href: location.pathname + location.search + "&minimode"}, "Mini mode"),
			]),
		],
		games[data.game] && games[data.game].render(data),
		
	]);
}

on("change", "#gameselect", e => {
	const game = e.match.value;
	if (game !== last_data.game) ws_sync.send({cmd: "replace_data", data: {game}});
});

on("click", "#resetgame", e => ws_sync.send({cmd: "replace_data", data: {game: last_data.game}}));
on("click", "#undoreset", e => ws_sync.send({cmd: "replace_data", data: last_data.reset}));

on("click", "button[data-setting]", e => {
	const key = e.match.dataset.setting;
	const val = last_data[key] === e.match.dataset.value ? null : e.match.dataset.value; //Selecting the current entry deselects.
	ws_sync.send({cmd: "update_data", key, val});
});
on("change", "select[data-setting]", e => ws_sync.send({cmd: "update_data", key: e.match.dataset.setting, val: e.match.value}));
on("input", "input[data-setting]", e => ws_sync.send({cmd: "update_data", key: e.match.dataset.setting, val: e.match.value}));

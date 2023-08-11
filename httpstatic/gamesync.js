import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DIV, FORM, H1, H2, INPUT, LABEL, OPTION, SELECT, SPAN, STYLE, TABLE, TD, TR} = lindt; //autoimport

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
			H2("Entry codes"),
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
		tag_colors: {Green: "#0f0", Blue: "#4fe", Yellow: "#ff0", Red: "#f11", White: "#fff"},
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
			DIV("Can this become a drop-down?"),
			DIV([
				INPUT({"data-setting": "vault-operator", value: data["vault-operator"] || ""}),
				INPUT({"data-setting": "operator-code", value: data["operator-code"] || ""}),
			]),
		];},
	},
	diamondheist: {
		label: "Payday 2: Diamond Heist",
		render(data) {return [
			DIV("Not to be confused with The Diamond heist. Seriously, those sound nothing alike."),
			H2("Entry code"),
			STYLE(".code {display: flex; gap: 4.5em; justify-content: center; flex-wrap: wrap} .code > * {height: 2.5em; width: 6em; font-size: 150%; text-align: center}"),
			DIV({class: "code"}, [
				INPUT({"data-setting": "code-red", style: "background-color: red; color: white", type: "number", value: data["code-red"]}),
				INPUT({"data-setting": "code-green", style: "background-color: green; color: white", type: "number", value: data["code-green"]}),
				INPUT({"data-setting": "code-blue", style: "background-color: blue; color: white", type: "number", value: data["code-blue"]}),
			]),
		];},
	},
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
		H1(games[data.game] ? games[data.game].label : "Game sync"),
		SELECT({id: "gameselect", value: data.game},
			Object.entries(games).map(([id, info]) => OPTION({value: id}, info.label))),
		DIV({class: "buttonbox"}, [
			BUTTON({type: "button", id: "resetgame"}, "Reset game"),
			data.reset && BUTTON({type: "button", id: "undoreset"}, "Undo Reset"),
		]),
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

import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DIV, FORM, H1, H2, INPUT, LABEL, OPTION, SELECT, STYLE, TABLE, TD, TR} = lindt; //autoimport

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
					//Red, Green, Blue
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

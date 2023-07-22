import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BR, BUTTON, DIV, FORM, H1, H2, INPUT, LABEL, OPTION, SELECT, TABLE, TD, TR} = lindt; //autoimport

let last_data = { };

const games = {
	goldengrin: {
		label: "Payday 2: Golden Grin Casino",
		render: data => [
			H2("Bars"),
			TABLE(["Pool", "VIP", "Above Ladies", "Above VIP"].map(bar => TR([
				TD(bar),
				[["Green", "#7f7"], ["Blue", "#99f"], ["Pink", "#f7d"], ["Red", "#f77"]].map(([name, col]) => TD(
					BUTTON({
						"data-setting": "drink-" + name, "data-value": bar,
						"style": data["drink-" + name] == bar ? "background-color: " + col : "",
					}, name),
				)),
			]))),
		],
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

on("click", "button[data-setting]", e => ws_sync.send({cmd: "update_data", key: e.match.dataset.setting, val: e.match.dataset.value}));

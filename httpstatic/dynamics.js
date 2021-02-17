import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {TR, TD, FORM, INPUT} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});

function render() {
	set_content("#rewards tbody", rewards.map(r => TR([
		TD(FORM({id: r.id, className: "editreward"}, INPUT({name: "title", value: r.title, "size": 40}))),
		TD(INPUT({name: "basecost", form: r.id, type: "number", value: r.basecost})),
		TD(INPUT({name: "formula", form: r.id, value: r.formula})),
		TD(INPUT({name: "curcost", form: r.id, type: "number", value: r.curcost})),
		TD([
			INPUT({name: "id", form: r.id, type: "hidden", value: r.id}),
			INPUT({form: r.id, type: "submit", value: "Save"}),
		]),
	])));
}
render();

DOM("#add").onclick = async e => {
	const res = await fetch("giveaway", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify({new_dynamic: 1}), //Yeah, I know, this probably ought to be a POST request instead
	});
	if (!res.ok) {console.error("Not okay response", res); return;}
	const body = await res.json();
	rewards.push(body.reward);
	render();
};

on("submit", "form.editreward", async e => {
	e.preventDefault();
	const el = e.match.elements;
	const body = {dynamic_id: el.id.value, title: el.title.value, basecost: el.basecost.value, formula: el.formula.value, curcost: el.curcost.value};
	const info = await (await fetch("giveaway", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(body),
	})).json();
	console.log("Got response:", info);
});

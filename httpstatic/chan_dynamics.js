import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {TR, TD, FORM, INPUT, OPTION} = choc;

let allrewards = { };

export const autorender = {
	dynreward_parent: DOM("#rewards tbody"),
	dynreward(r) {return TR({"data-id": r.id}, [
		TD(FORM({id: r.id, className: "editreward"}, INPUT({name: "title", value: r.title, "size": 40}))),
		TD(INPUT({name: "basecost", form: r.id, type: "number", value: r.basecost})),
		TD(INPUT({name: "availability", form: r.id, value: r.availability || "{online}"})),
		TD(INPUT({name: "formula", form: r.id, value: r.formula})),
		TD(INPUT({name: "curcost", form: r.id, type: "number", value: r.curcost})),
		TD([
			INPUT({name: "id", form: r.id, type: "hidden", value: r.id}),
			INPUT({form: r.id, type: "submit", value: "Save"}),
		]),
	]);},
	dynreward_empty() {return DOM("#rewards tbody").appendChild(TR([
		TD({colSpan: 6}, "No redemptions (add one!)"),
	]));},
}
export function render(data) {
	if (data.items) {
		allrewards = data.items;
		const copiables = allrewards.map((r, i) => OPTION({value: i}, r.title));
		copiables.unshift(DOM("#copyfrom").firstElementChild);
		set_content("#copyfrom", copiables);
	}
}

DOM("#add").onclick = async e => {
	//TODO: Put this on the websocket
	const res = await fetch("giveaway", {
		method: "PUT", //Yeah, I know, this probably ought to be a POST request instead
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify({new_dynamic: 1, copy_from: allrewards[DOM("#copyfrom").value]}),
	});
	if (!res.ok) {console.error("Not okay response", res); return;}
};

on("submit", "form.editreward", async e => {
	e.preventDefault();
	const el = e.match.elements;
	const body = {dynamic_id: el.id.value, title: el.title.value, basecost: el.basecost.value,
		availability: el.availability.value, formula: el.formula.value, curcost: el.curcost.value};
	const info = await (await fetch("giveaway", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(body),
	})).json();
	console.log("Got response:", info);
}, true);

on("input", "#rewards input", e => e.match.classList.add("dirty"));
on("change", "#rewards input", e => e.match.classList.add("dirty"));
on("paste", "#rewards input", e => e.match.classList.add("dirty"));

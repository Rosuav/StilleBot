import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {INPUT, LABEL, TD, TEXTAREA, TR} = choc; //autoimport

const cfg_vars = [
	{key: "title", label: "Title", render: val => INPUT({value: val, size: 40})},
	{key: "description", label: "Description", render: val => TEXTAREA({rows: 4, cols: 35}, val)},
];

export function render(data) {
	set_content("#configdlg tbody", cfg_vars.map(v => {
		const input = v.render(data.cfg[v.key] || "");
		input.id = "edit_" + v.key;
		return TR([
			TD(LABEL({for: input.id}, v.label)),
			TD(input),
		]);
	}));
	if (data.desc_html) DOM("#cfg_description").innerHTML = data.desc_html;
}

on("click", "#editconfig", e => DOM("#configdlg").showModal());
on("submit", "#configdlg form", e => {
	const el = e.match.elements;
	const msg = {cmd: "update"};
	cfg_vars.forEach(v => {
		const elem = el["edit_" + v.key];
		msg[v.key] = v.getvalue ? v.getvalue(elem) : elem.value;
	});
	ws_sync.send(msg);
});

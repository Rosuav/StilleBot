# VLC integration

Describe your music collection. Edit any entry and save. Blank the description to delete.

Path | Description |
-----|-------------|-
-    | -

<ul id=unknowns></ul>

<script type=module>
import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BUTTON, INPUT, LI, TR, TD} = choc;

const blocks = $$blocks$$;
const unknowns = $$unknowns$$;

function make_block_desc(path, desc) {
	return TR([
		TD(INPUT({value: path, className: "path", size: 80})),
		TD(INPUT({value: desc, className: "desc", size: 80})),
		TD([
			BUTTON({type: "button", onclick: e => {
				const tr = e.currentTarget.closest("tr");
				fetch("vlc?saveblock", {
					method: "POST",
					body: JSON.stringify({
						path: tr.querySelector(".path").value,
						desc: tr.querySelector(".desc").value,
					}),
					headers: {"content-type": "application/json"},
					credentials: "include",
				}).then(e => console.log(e));
			}}, "Save"),
		]),
	]);
}

const tbody = DOM("table tbody");
blocks.forEach(b => tbody.appendChild(make_block_desc(b[0], b[1])));

set_content("#unknowns", unknowns.map(path => LI(A({href: "", onclick: e => {
	e.preventDefault();
	tbody.appendChild(make_block_desc(path, ""));
}}, path))));
DOM("#unknowns").appendChild(LI(A({href: "", onclick: e => {
	e.preventDefault();
	tbody.appendChild(make_block_desc("", ""));
}}, "+ Add new")));
</script>

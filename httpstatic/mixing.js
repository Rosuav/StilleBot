import choc, {set_content, DOM} from "https://rosuav.github.io/shed/chocfactory.js";
const {B, DIV} = choc; //autoimport

export function render(data) {
	set_content("#swatches", swatches.map((sw, idx) => DIV(
		{className: "swatch " + sw.color, title: sw.desc, "data-coloridx": idx},
		sw.label
	)));
	//NOTE: For guests, curcolor is not synchronized in state, but will only be sent
	//to a specific client in response to that client's addcolor requests. This means
	//that a guest getting disconnected will result in losing state. Sorry. Log in to
	//avoid that issue.
	//TODO: Have a login button.
	if (data.curpaint) {
		//Your current paint is defined by a base and a series of zero or more
		//pigments. At each point, the server provides a hex color.
		set_content("#curpaint", data.curpaint.blobs.map(b => DIV(
			{className: "swatch", style: "background: #" + b.color},
			b.label
		)));
		DOM("#curcolor").style.background = "#" + data.curpaint.color;
	}
	if (data.loginbtn === 1) DOM("#loginbox").classList.remove("hidden");
	if (data.loginbtn === -1) DOM("#newgame").classList.remove("hidden");
	if (data.gameid) set_content("#gamedesc", ["Operation ", B(data.gameid), " is now in progress. "]);
}

let selectedcolor = null;
on("click", "#swatches div", e => {
	const sw = swatches[e.match.dataset.coloridx];
	if (!sw) return; //shouldn't happen
	selectedcolor = sw;
	set_content("#colorname", sw.label);
	set_content("#colordesc", sw.desc);
	set_content("#colorpicker", [
		DIV({className: "swatch large " + sw.color + "-spot", "data-strength": "1"}, "Spot"),
		DIV({className: "swatch large " + sw.color + "-spoonful", "data-strength": "2"}, "Spoonful"),
		DIV({className: "swatch large " + sw.color + "-splash", "data-strength": "3"}, "Splash"),
	]);
	DOM("#colordlg").showModal();
});

on("click", "#colorpicker div", e => {
	ws_sync.send({cmd: "addcolor", "color": selectedcolor.label, "strength": e.match.dataset.strength|0});
	DOM("#colordlg").close();
});

let selectedpaint = null;
on("click", "#basepots div", e => {
	selectedpaint = e.match.dataset.id;
	set_content("#bigsample", e.match.innerText).style.cssText = e.match.style.cssText;
	DOM("#freshpaint").showModal();
});

on("click", "#startpaint", e => {
	ws_sync.send({cmd: "freshpaint", base: selectedpaint});
	DOM("#freshpaint").close();
});

on("click", "#startnewgame", e => {
	ws_sync.send({cmd: "newgame"});
	DOM("#newgamedlg").close();
});

on("click", ".infobtn", e => DOM("#" + e.match.dataset.dlg).showModal());

//After starting a new game, have a completely fresh start - don't try to fudge things.
export function sockmsg_redirect(data) {location.href = "/mixing?game=" + data.game;}

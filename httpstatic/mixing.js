import choc, {set_content, DOM} from "https://rosuav.github.io/shed/chocfactory.js";
const {B, DIV} = choc; //autoimport

let published_color = null;
export function render(data) {
	set_content("#swatches", swatches.map((sw, idx) => DIV(
		{className: "swatch " + sw.color, title: sw.desc, "data-coloridx": idx},
		sw.label
	)));
	//NOTE: The current paint is not synchronized in state. (This may need to change,
	//but if so, only for logged-in users, not for guests.) Saved paints are, of course.
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
	if (data.gameid) set_content("#gamedesc", [
		"Operation ", B(data.gameid), " is now in progress. ",
		data.phase === "mixpaint" && ["It is ", B("morning"), " and the paint shop is open for mixing."],
		data.phase === "writenote" && ["It is ", B("afternoon"), " and the message board is receiving submissions."],
		data.phase === "readnote" && ["It is ", B("evening"), " and today's messages are on the board."],
		data.phase === "gameover" && ["The ", B("game is over"), ", and Rosuav needs to code this part."],
	]);
	if (data.paints) set_content("#basepots", data.paints.map(p => DIV(
		{className: "swatch", "data-id": p[0], style: "background: #" + p[2]},
		p[1],
	)));
	if (data.selfpublished) published_color = data.selfpublished;
	if (data.phase) set_content("#phase", "article#" + data.phase + " {display: block;}");
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

on("submit", "#savepaint", e => {
	e.preventDefault();
	const el = e.match.elements.paintid;
	if (el.value === "") return; //TODO: Give error message (can't save nameless)
	ws_sync.send({cmd: "savepaint", id: el.value});
	el.value = "";
});

on("click", "#publishpaint", e => {
	if (published_color) {
		set_content("#publishonce", "NOTE: You can only publish one paint. This is the paint you shared:");
		DOM("#publishme").style.cssText = "background: #" + published_color;
		DOM("#publishconfirm").classList.add("hidden");
		set_content("#publishcancel", "It will have to suffice.");
	}
	else DOM("#publishme").style.cssText = DOM("#curcolor").style.cssText;
	DOM("#publishdlg").showModal();
});

on("click", "#publishconfirm", e => {
	ws_sync.send({cmd: "publish"});
	DOM("#publishdlg").close();
});
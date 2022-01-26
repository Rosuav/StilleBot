import choc, {set_content, DOM} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, B, BR, BUTTON, CODE, DIV, INPUT, LABEL, LI, P} = choc; //autoimport

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
	if (data.loginbtn === 1) {
		DOM("#loginbox").classList.remove("hidden");
		if (data.gameid) set_content("#specview", "observe the game in progress");
	}
	if (data.loginbtn === -1) DOM("#gamedesc").classList.remove("hidden");
	if (data.gameid) set_content("#gamedesc", [
		"Operation ", B(data.gameid), " is now in progress. ",
		data.phase === "recruit" && ["It is ", B("that dark hour before dawn"), " and we need to know who's on what side. Share ",
			A({href: "/mixing?game=" + data.gameid}, "the link to this page"),
			" to recruit both friends and enemies!",
			data.is_host && P([
				"Are you live-streaming? ",
				BUTTON({className: "infobtn", "data-dlg": "chatlink"}, "I can post in chat for you"),
				" to try to attract people!",
			]),
		],
		data.phase === "mixpaint" && ["It is ", B("morning"), " and the paint shop is open for mixing."],
		data.phase === "writenote" && ["It is ", B("afternoon"), " and the message board is receiving submissions."],
		data.phase === "readnote" && ["It is ", B("evening"), " and today's messages are on the board."],
		data.phase === "gameover" && ["The ", B("game is over"), ", and the results can be seen below."],
		data.is_host && data.phase !== "gameover" && P([
			"When everything is ready, use your host privileges to ",
			BUTTON({className: "infobtn", "data-dlg": "nextphasedlg"}, "advance time"), " to the next phase.",
			data.nophaseshift && " (Once everything's ready. " + data.nophaseshift + ")",
		]),
		data.phase !== "recruit" && data.spymaster && data.contact && P([
			"The Spymaster is ", B(data.spymaster), " and the Contact is ", B(data.contact), ".",
		]),
	]);
	if (data.paints) {
		set_content(data.phase === "readnote" ? "#comparepaint .colorpicker" : "#basepots", data.paints.map(p => DIV(
			{className: "swatch", "data-id": p[0], style: "background: #" + p[2], "data-desc": p[3]},
			p[1],
		)));
		set_content("#paintradio", data.paints.map(p => LABEL(
			{className: "swatch", "data-id": p[0], style: "background: #" + p[2], "data-desc": p[3]},
			[p[1], BR(), INPUT({type: "radio", name: "notepaint", value: p[0]})],
		)));
	}
	if (data.selfpublished) published_color = data.selfpublished;
	if (data.phase) set_content("#phase", "article#" + data.phase + " {display: block;}");
	if (data.phase === "recruit" && data.chaos) {
		["spymaster", "contact"].forEach(role =>
			set_content("#" + role, data[role] || BUTTON({className: "setrole", "data-role": role}, "Claim role"))
		);
		set_content("#chaos", data.chaos.length ? data.chaos.join(", ") : "(none)");
	}
	if (data.note_to_send && DOM("#" + data.phase + " .note_to_send")) set_content("#" + data.phase + " .note_to_send", [
		data.note_send_color && DIV({className: "swatch inline", style: "background: #" + data.note_send_color}),
		data.note_to_send
	]);
	if (data.note_send_color) {DOM("#paintradio").classList.add("hidden"); DOM("#postnote").classList.add("hidden");}
	if (data.msg_order) set_content("#all_notes", data.msg_order.map((m, i) => LI({"data-id": i + 1}, [
		DIV({className: "swatch inline", style: "background: #" + data.msg_color_order[i]}),
		CODE(m),
	])));
	if (data.selected_note) {
		set_content("#notecolor", data.msg_order[data.selected_note - 1]).style = "background: #" + data.msg_color_order[data.selected_note - 1];
		set_content("#instrdescribe", [
			"Please confirm: You will be following the instructions in this note, which say: ", BR(),
			DIV({className: "swatch inline", style: "background: #" + data.msg_color_order[data.selected_note - 1]}),
			CODE(data.msg_order[data.selected_note - 1]),
			P("Is this correct?"),
		]);
	}
	if (data.comparison_log) {
		set_content("#comparison_log", [...data.comparison_log].reverse().map(action => LI([
			action.action === "select" && [
				"Took note #" + action.noteid + " for a closer look.", BR(),
				DIV({className: "swatch inline", style: "background: #" + data.msg_color_order[action.noteid - 1]}),
				CODE(data.msg_order[action.noteid - 1]),
			],
			action.action === "compare" && [
				"Compared ",
				DIV({className: "swatch inline", style: "background: #" + data.msg_color_order[action.noteid - 1]}),
				" note #" + action.noteid + " with a pot of ",
				//If you're the contact, show the paint you compared it against.
				data.comparison_paints && DIV({className: "swatch inline", style: "background: #" + data.comparison_paints[action.coloridx]}),
				" paint",
			],
			action.action === "result" && ["They look... ", B(action.similarity), "."],
		])));
		DOM("#comparison").classList.toggle("comparing", !!data.comparing);
	}
	if (data.phase === "readnote" && data.role === "contact") { //Need a more elegant way to do that
		DOM("#comparepaint").classList.remove("hidden");
		set_content("#midbtn", BUTTON({type: "button", id: "compare"}, "Compare!"));
	}
	if (data.role) set_content("#rolestyle", ".role." + data.role + " {display: block;}");
	if (data.host) set_content("#gamehost", data.host);
	if (data.no_save) {
		//You can't save paints, so hide the forms and explain.
		DOM("#savepaint").classList.add("hidden");
		DOM("#publishpaint").parentElement.classList.add("hidden"); //Hide the whole paragraph fwiw
		DOM("#onlybeige").classList.remove("hidden");
	}
	if (data.game_summary) set_content("#gamesummary", data.game_summary.map(para => P(para.map(part => {
		switch (part[0]) {
			case "text": return part[1];
			case "role": return B(part[1]);
			case "msg": return CODE([
				DIV({className: "swatch inline", style: "background: #" + part[2]}),
				part[1],
			]);
			case "box": return DIV({className: "gameoverbox " + part[1]}, part[2]);
		}
		return CODE("[?] " + part[0]);
	}))));
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
	set_content("#paintorigin", e.match.dataset.desc);
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

on("click", ".setrole", e => ws_sync.send({cmd: "setrole", role: e.match.dataset.role}));
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

on("click", "#nextphase", e => {
	ws_sync.send({cmd: "nextphase"});
	DOM("#nextphasedlg").close();
});

on("click", "#suggestmsg", e => {
	const messages = [
		"We're playing Diffie Hellman Paint Mixing - come join us at {link} !",
		"Join us to play or spectate a game about paint and security: {link}",
		"Come to {link} for a silly little game about paint mixing and spies!",
		"Secret Agents, your orders can be found at {link} - burn after reading.",
		"Follow us to {link} ... if you dare. Don't worry, it's just paint...",
		//More message suggestions welcome!
	];
	while (1) {
		const msg = messages[Math.floor(Math.random() * messages.length)];
		if (DOM("input[name=msg]").value === msg) continue;
		DOM("input[name=msg]").value = msg;
		break;
	}
});

on("click", "#postnote", e => {
	const rb = DOM("#paintradio input:checked");
	if (!rb) return; //TODO: Error message
	ws_sync.send({cmd: "postnote", paint: rb.value});
});

on("submit", "#chatlinkform", e => {
	e.preventDefault();
	const msg = e.match.elements.msg.value;
	if (msg === "") return; //TODO: Give error message
	ws_sync.send({cmd: "chatlink", msg});
	ws_sync.send({cmd: "prefs_update", diffie_hellman_chatlink: msg});
	DOM("#chatlink").close();
});

ws_sync.prefs_notify("diffie_hellman_chatlink", chatlink => {
	DOM("input[name=msg]").value = chatlink;
});

let comparisonpaint = null;
on("click", "#comparepaint .colorpicker div", e => {
	comparisonpaint = e.match.dataset.id;
	console.log("Comparison:", comparisonpaint);
	set_content("#paintcolor", "Compare against: " + e.match.dataset.id).style.cssText = e.match.style.cssText;
});

on("click", "#all_notes li", e => ws_sync.send({cmd: "selectnote", note: e.match.dataset.id|0}));
on("click", "#compare", e => ws_sync.send({cmd: "comparenotepaint", paint: comparisonpaint}));
on("click", "#followinstrs", e => {
	ws_sync.send({cmd: "followinstrs"});
	DOM("#useinstrs").close();
});

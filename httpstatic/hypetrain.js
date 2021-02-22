import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BR, DIV, IMG, P, UL, LI, SPAN} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});

//The threshold for "Super Hard" is this many bits per level (not total).
//In order to unlock the sixth emote for each level, you need to have a
//goal that is at least this number of bits for the level (since Insane
//is even higher - level 1 needs 10,000 bits).
const hardmode = [0, 5000, 7500, 10600, 14600, 22300];

const ismobile = !DOM("#configform");
let config = {};
if (!ismobile) {
	try {config = JSON.parse(localStorage.getItem("hypetrain_config")) || {};} catch (e) {}
	const el = DOM("#configform").elements;
	for (let name in config) {
		const [type, which] = name.split("_");
		const audio = DOM("#sfx_" + which);
		if (type === "use") {el[name].checked = true; audio.preload = "auto";}
		else if (type === "vol") {el[name].value = config[name]; audio.volume = config[name] / 100;}
		//That should be all the configs that get saved
	}
}

let expiry, updating = null;
function update() {
	let tm = Math.floor((expiry - +new Date()) / 1000);
	const time = document.getElementById("time");
	if (tm <= 0 || !time) {
		clearInterval(updating); updating = null;
		if (time) time.innerHTML = "";
		return;
	}
	let t = ":" + ("0" + (tm % 60)).slice(-2);
	if (tm >= 3600) t = Math.floor(tm / 3600) + ":" + ("0" + (Math.floor(tm / 60) % 60)).slice(-2) + t;
	else t = Math.floor(tm / 60) + t; //Common case - less than an hour
	time.innerHTML = t;
}

function subs(n) {return Math.floor((n + 499) / 500);} //Calculate how many T1 subs are needed

function fmt_contrib(c) {
	if (c.type === "BITS") return `${c.display_name} with ${c.total} bits`;
	return `${c.display_name} with ${c.total / 500} T1 subs (or equivalent)`;
}

//Play audio snippets, if configured to do so
function play(which, force) {
	if (!config["use_" + which] && !force) return; //Play if configured (or if testing)
	const el = DOM("#sfx_" + which);
	if (el.playing) return; //Don't stack audio
	const playing = el.play();
	if (playing) playing.catch(err => {
		//Autoplay was denied. Notify the console for debugging purposes.
		console.error("Unable to autoplay");
		console.error(err);
	});
	if (which === "insistent") {
		el.loop = true;
		setTimeout(() => el.loop = false, force ? 2500 : 9500);
	}
}
function hypetrain_started() {play("start");}
function cooldown_ended() {play("ding"); play("insistent");}

let interacted = 0;
function check_interaction() {
	DOM("#interact-warning").classList.toggle("hidden",
		interacted || (!config.use_ding && !config.use_insistent && !config.use_start)
	);
}

let last_rendered = null;
export let render = (state) => {
	check_interaction();
	//Show the emotes that we could win (or could have won last hype train)
	const lvl = state.cooldown && state.level; //If not active or cooling down, hide 'em all
	document.querySelectorAll("#emotes li").forEach((li, idx) => li.className =
		lvl >= idx + 2 || state.total >= state.goal ? "available" :
		state.expires && lvl === idx + 1 ? "next" : ""); //Only show "next" during active hype trains
	document.getElementById("emotes").classList.toggle("hardmode", state.goal >= hardmode[state.level]);

	if (!state.expires && !state.cooldown) {
		//Idle state. If we previously had a cooldown, it's now expired.
		set_content("#hypeinfo", [
			P({id: "status", className: "countdown"}, A(
				{"title": "The hype train is awaiting activity. If they're enabled, one can be started!", "href": "",},
				"Cookies are done!"
			)),
			//Note that we might not have conductors (or any data). It lasts a few days at most.
		]);
		document.querySelectorAll("#emotes li").forEach(li => li.className = "");
		if (last_rendered === "cooldown") cooldown_ended();
		last_rendered = "idle";
		return;
	}
	let goal, goalattrs = {id: "nextlevel"};
	if (state.expires)
	{
		//Active hype train!
		goal = `Level ${state.level} requires ${state.goal} bits or ${subs(state.goal)} tier one subs.`;
		goalattrs.className = "level" + state.level;
		let need = state.goal - state.total;
		if (need <= 0) {goal += " TIER FIVE COMPLETE!"; goalattrs.className = "level6";}
		else {
			goal += ` Need ${need} more bits or ${subs(need)} more subs.`;
			let mark = state.total / state.goal * 100;
			let delta = 0.375; //Width of the red marker line (each side)
			goalattrs.style = `background: linear-gradient(.25turn, var(--hype-level${state.level + 1}) ${mark-delta}%, red, var(--hype-level${state.level}) ${mark+delta}%, var(--hype-level${state.level}))`;
		}
		if (last_rendered === "idle") hypetrain_started();
		last_rendered = "active";
	}
	else
	{
		if (state.level === 1)
			goal = `The last hype train reached ${state.total} out of ${state.goal} to complete level 1.`;
		else if (state.level === 5 && state.total >= state.goal)
			goal = `The last hype train finished level 5 at ${Math.round(100 * state.total / state.goal)}%!!`;
		else
			goal = `The last hype train completed level ${state.level - 1}! Good job!`;
		last_rendered = "cooldown"; //No audio cue when changing from active to cooldown
	}
	expiry = (state.expires || state.cooldown) * 1000;
	let conduc = { };
	state.conductors.forEach(c => conduc[c.type] = P(
		{id: "cond_" + c.type.toLowerCase(), className: "present"},
		c.type + " conductor: " + fmt_contrib(c)
	));
	set_content("#hypeinfo", [
		P({id: "status", className: state.expires ? "countdown active" : "countdown"}, [
			state.expires ? "HYPE TRAIN ACTIVE! " : "The hype train is on cooldown. Next one can start in ",
			SPAN({id: "time"})
		]),
		conduc.BITS || P({id: "cond_bits"}, "No hype conductor for bits - cheer any number of bits to claim this spot!"),
		conduc.SUBS || P({id: "cond_subs"}, "No hype conductor for subs - subscribe/resub/subgift to claim this spot!"),
		P(["Latest contribution: ", fmt_contrib(state.lastcontrib)]),
		P(goalattrs, goal),
	]);
	if (updating) clearInterval(updating);
	updating = setInterval(update, 1000);
	update();
}
if (ismobile) render = (state) => {
	if (!state.expires && !state.cooldown) {
		set_content("#status", "Cookies are done!").className = "";
		//Technically this allows content to linger in the DOM. This is sort of a feature. Almost.
		return;
	}
	if (state.expires)
	{
		//Active hype train!
		set_content("#status", ["ACTIVE", BR(), SPAN({id: "time"})]).className = "active";
		let need = state.goal - state.total;
		if (need < 0) set_content("#nextlevel", "TIER FIVE COMPLETE!").className = "level6";
		else set_content("#nextlevel", [
			`Level ${state.level} needs`, BR(),
			need + " bits", BR(),
			subs(need) + " subs",
		]).className = "level" + state.level;
	}
	else
	{
		set_content("#status", ["Cooling down", BR(), SPAN({id: "time"})]).className = "";
		if (state.level === 1)
			set_content("#nextlevel", `Reached ${state.total} out of ${state.goal}`).className = "";
		else if (state.level === 5 && state.total >= state.goal)
			set_content("#nextlevel", `Finished level 5 at ${Math.round(100 * state.total / state.goal)}%!!`).className = "";
		else
			set_content("#nextlevel", `Finished level ${state.level - 1}!`).className = "";
	}
	expiry = (state.expires || state.cooldown) * 1000;
	const contrib = state.lastcontrib.type === "BITS" ? `${state.lastcontrib.total} bits` : `${state.lastcontrib.total / 500} subs`;
	set_content("#latest", ["Latest:", BR(), `${state.lastcontrib.display_name} - ${contrib}`]);
	let have_bits = 0, have_subs = 0;
	state.conductors.forEach(c => {
		let sel, desc;
		if (c.type === "BITS") {have_bits = 1; sel = "#cond_bits"; desc = c.total + " bits"}
		else {have_subs = 1; sel = "#cond_subs"; desc = (c.total/500) + " subs";}
		set_content(sel, ["Conductor:", BR(), c.display_name, BR(), desc]).className = "present";
	});
	if (!have_bits) set_content("#cond_bits", "").className = "";
	if (!have_subs) set_content("#cond_subs", "").className = "";
	if (updating) clearInterval(updating);
	updating = setInterval(update, 1000);
	update();
}

//This isn't needed most of the time (the webhook will signal us), but can help if
//anonymous events happen and are missed by the hook.
function refresh() {ws_sync.send({cmd: "refresh"});}
if (!ismobile) {
	DOM("#refresh").onclick = refresh;
	DOM("#configure").onclick = () => DOM("#config").showModal();
	on("click", ".play", e => {
		play(e.match.id.split("_")[1], 1);
	});
	on("click", ".countdown a", e => {
		e.preventDefault();
		set_content("#infopopup div", [
			P("The hype train is not currently active, nor is it cooling down. If hype trains are active, this means" +
				" that one can be started; there is no easy way to know whether they are active, or how many hype events" +
				" it will take to start one."),
			P("The default and most common setting is that three separate people must" +
				" contribute to start a hype train; however the streamer can increase this number to any value up to" +
				" twenty-five."),
			P("Anonymous actions count separately (the 'anonymous user' is its own user). All actions" +
				" must take place within a five-minute period to trigger a hype train."),
		]);
		DOM("#infopopup").showModal();
	});
	on("input", 'input[type="range"]', e => {
		const which = "#sfx_" + e.match.name.split("_")[1];
		DOM(which).volume = e.match.value / 100;
	});
	DOM("#configform").onsubmit = e => {
		e.preventDefault();
		config = {}; new FormData(DOM("#configform")).forEach((v,k) => config[k] = v);
		localStorage.setItem("hypetrain_config", JSON.stringify(config));
		DOM("#config").close();
	};
	document.onclick = () => {interacted = 1; check_interaction();}
}
else
{
	DOM("#emotestile").onclick = e => {
		set_content("#infopopup div", [
			P("TODO: This would get info about the earnable emotes."),
		]);
		DOM("#infopopup").showModal();
	};
}

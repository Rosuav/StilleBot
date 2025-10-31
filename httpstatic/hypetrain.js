import choc, {set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, DIV, IMG, P, SPAN} = choc; //autoimport

const hypelabel = {
	regular: "HYPE",
	treasure: "TREASURE",
	golden_kappa: "GOLDEN KAPPA",
};

const ismobile = !DOM("#configform");
let have_prefs = false, need_interaction = false;
if (!ismobile) ws_sync.prefs_notify(prefs => { //Note: Even if no prefs are set, we need a notification that they're loaded, so this is unkeyed notification for now.
	have_prefs = true;
	const config = prefs.hypetrain;
	//Ultimately: Set prefs_notify to tell us about "hypetrain" only.
	//CJA 20250915: This was previously merging in localStorage configs, no longer supported. However,
	//I don't recall why this meant it needed to be an unkeyed notification. What are the consequences
	//of switching to keyed, and can that now be done as a simplification?

	const el = DOM("#configform").elements;
	for (let name in config) {
		const [type, which] = name.split("_");
		if (!el[name]) continue; //Probably a former config setting, no longer in use (eg emotes_checklist)
		const audio = DOM("#sfx_" + which);
		if (type === "use") {el[name].checked = config[name]; audio.preload = config[name] ? "auto" : "none";}
		else if (type === "vol") {el[name].value = config[name]; audio.volume = config[name] / 100;}
		else if (type === "emotes") {
			el[name].checked = config[name];
			document.body.classList.toggle(name, config[name]);
		}
		//That should be all the configs that get saved
	}
	need_interaction = config.use_ding || config.use_insistent || config.use_start;
	check_interaction();
});

let expiry, updating = null;
let offset = 0;
function update() {
	let tm = Math.floor((expiry - +new Date() + offset) / 1000);
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
	if (!c.user_name) return ""; //No data available (can happen after a hype train ends)
	if (c.type === "BITS") return `${c.user_name} with ${c.total} bits`;
	return `${c.user_name} with ${c.total / 500} T1 subs (or equivalent)`;
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
	DOM("#interact-warning").classList.toggle("hidden", interacted || !need_interaction);
}

function level_color(level) {
	const degree = 216 - level * 20;
	//Color should be full red, full green, and a decreasing amount of blue, to give
	//a pale yellow at level 1 up to a vibrant yellow once we get beyond level 100ish.
	//The gradient progresses from the more vibrant one (next level) to the paler one
	//(current level). The current scheme gives decent colours up to level 10, then
	//locks in place until level 100. Would be nice to have more variation after that.
	//Reducing the multiplier on the degree to 2 would give variation as far as level
	//108, but at the cost of per-level differentiation, and thus usefulness.
	return "#ffff" + (degree < 0 ? "00" : ("0" + degree.toString(16)).slice(-2));
}

function all_time_stats(all_time_high) {
	return all_time_high && P({id: "all_time"}, [
		"All-time high: Level ", all_time_high.level, " at ", all_time_high.total, " total bits,",
		" achieved ", new Date(all_time_high.achieved_at).toLocaleDateString(),
	]);
}

let last_rendered = null;
export let render = (state) => {
	if (state.error) {
		set_content("#hypeinfo", P({id: "status"}, [
			state.error, A({href: state.errorlink}, state.errorlink), BR(),
			BUTTON({className: "twitchlogin", "data-scopes": need_scopes || "channel:read:hype_train"}, "Broadcaster log in"),
		]));
		return;
	}
	check_interaction();
	if (state.hack_now) offset = +new Date() - state.hack_now * 1000;
	//Show the emotes that we could win (or could have won last hype train)
	const lvl = state.cooldown && state.level; //If not active or cooling down, hide 'em all
	["#emotes", "#goldenkappa"].forEach(par =>
		document.querySelectorAll(par + " li").forEach((li, idx) => li.className =
			lvl >= idx + 2 || state.total >= state.goal ? "available" :
			state.expires && lvl === idx + 1 ? "next" : "" //Only show "next" during active hype trains
		)
	);
	if (!state.expires && !state.cooldown) {
		//Idle state. If we previously had a cooldown, it's now expired.
		set_content("#hypeinfo", [
			P({id: "status", className: "countdown"}, A(
				{"title": "The hype train is awaiting activity. If they're enabled, one can be started!", "href": "", class: "cookiesinfo"},
				"Cookies are done!"
			)),
			all_time_stats(state.all_time_high),
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
		let need = state.goal - state.total;
		if (need <= 0) goal += " HYPE TRAIN COMPLETE!"; //Probably never going to happen
		else {
			goal += ` Need ${need} more bits, or ${subs(need)} more subs.`;
			let mark = state.total / state.goal * 100;
			let delta = 0.375; //Width of the red marker line (each side)
			const from_color = level_color(state.level + 1);
			const to_color = level_color(state.level);
			goalattrs.style = `background: linear-gradient(.25turn, ${from_color} ${mark-delta}%, red, ${to_color} ${mark+delta}%, ${to_color})`;
		}
		if (last_rendered === "idle") hypetrain_started();
		last_rendered = "active";
	}
	else
	{
		if (state.level === 1)
			goal = `The last hype train reached ${state.total} out of ${state.goal} to complete level 1.`;
		else if (state.total >= state.goal) //Probably never going to happen
			goal = `The last hype train finished level ${state.level} at ${Math.round(100 * state.total / state.goal)}%!!`;
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
	document.body.dataset.hypetype = state.type || "none";
	set_content("#hypeinfo", [
		P({id: "status", className: state.expires ? "countdown active" : "countdown"}, [
			state.expires ? (hypelabel[state.type] || "HYPE") + " TRAIN ACTIVE! " : "The hype train is on cooldown. Next one can start in ",
			state.shared_train_participants && state.shared_train_participants.map(chan =>
				DIV([
					"Hype train also shared with ",
					A({href: "https://twitch.tv/" + chan.broadcaster_user_login, target: "_blank"}, [
						chan.profile_image_url && [IMG({class: "avatar", src: chan.profile_image_url}), " "],
						chan.broadcaster_user_name,
					]),
					"!",
				])
			),
			SPAN({id: "time"}),
		]),
		all_time_stats(state.all_time_high),
		conduc.BITS || P({id: "cond_bits"}, "No hype conductor for bits - cheer any number of bits to claim this spot!"),
		conduc.SUBS || P({id: "cond_subs"}, "No hype conductor for subs - subscribe/resub/subgift to claim this spot!"),
		P(goalattrs, goal),
	]);
	if (updating) clearInterval(updating);
	updating = setInterval(update, 1000);
	update();
}
if (ismobile) render = (state) => {
	if (state.error) {set_content("#hypeinfo", state.error); return;}
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
		if (need < 0) set_content("#nextlevel", "HYPE TRAIN COMPLETE!");
		else set_content("#nextlevel", [
			`Level ${state.level} needs`, BR(),
			need + " bits", BR(),
			subs(need) + " subs",
		]);
	}
	else
	{
		set_content("#status", ["Cooling down", BR(), SPAN({id: "time"})]);
		if (state.level === 1)
			set_content("#nextlevel", `Reached ${state.total} out of ${state.goal}`);
		else if (state.total >= state.goal)
			set_content("#nextlevel", `Finished level ${state.level} at ${Math.round(100 * state.total / state.goal)}%!!`);
		else
			set_content("#nextlevel", `Finished level ${state.level - 1}!`);
	}
	expiry = (state.expires || state.cooldown) * 1000;
	const contrib = state.lastcontrib.type === "BITS" ? `${state.lastcontrib.total} bits` : `${state.lastcontrib.total / 500} subs`;
	let have_bits = 0, have_subs = 0;
	state.conductors.forEach(c => {
		let sel, desc;
		if (c.type === "BITS") {have_bits = 1; sel = "#cond_bits"; desc = c.total + " bits"}
		else {have_subs = 1; sel = "#cond_subs"; desc = (c.total/500) + " subs";}
		set_content(sel, ["Conductor:", BR(), c.user_name, BR(), desc]).className = "present";
	});
	if (!have_bits) set_content("#cond_bits", "").className = "";
	if (!have_subs) set_content("#cond_subs", "").className = "";
	if (updating) clearInterval(updating);
	updating = setInterval(update, 1000);
	update();
}

//This isn't needed most of the time (the hook will signal us), but can help if
//anonymous events happen and are missed by the hook.
function refresh() {ws_sync.send({cmd: "refresh"});}
if (!ismobile) {
	DOM("#refresh").onclick = refresh;
	DOM("#configure").onclick = () => {
		DOM("#save_prefs").disabled = !have_prefs;
		if (have_prefs) DOM("#configform .twitchlogin").style.display = "none";
		DOM("#config").showModal();
	};
	on("click", ".play", e => {
		play(e.match.id.split("_")[1], 1);
	});
	on("click", ".cookiesinfo", e => {
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
		const config = {};
		DOM("#configform").querySelectorAll("input").forEach(el =>
			config[el.name] = el.type === "checkbox" ? el.checked : el.value
		);
		if (have_prefs) ws_sync.send({cmd: "prefs_update", hypetrain: config});
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

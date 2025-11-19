import Matter from "https://esm.run/matter-js";
import decomp from "https://esm.run/poly-decomp";
Matter.Common.setDecomp(decomp);
const hacks = ws_group === "4OCNIkpnmXUkUF0s0SfmOuKzurlCP6mlwxeM#49497888"; //For testing, sometimes will have special code
//const hacks = false;
const engine = Matter.Engine.create();
const width = window.innerWidth - 20, height = window.innerHeight - 20;
const renderer = Matter.Render.create({element: document.getElementById("display"), engine, options: {
	background: "transparent", width, height,
}});
const Rectangle = Matter.Bodies.rectangle, Circle = Matter.Bodies.circle;
//Increase precision at the cost of computational power. TODO: Make this broadcaster-configurable?
engine.positionIterations *= 2;
engine.velocityIterations *= 2;
Matter.Render.run(renderer);
Matter.Runner.run(Matter.Runner.create(), engine);
renderer.options.wireframes = false;
window.Matter = Matter;
window.renderer = renderer; //For debugging, eg toggle wireframes mode
window.wf = () => renderer.options.wireframes = !renderer.options.wireframes;
//If true, will (once only) add a bunch of automatic RPS entries.
let autorps = ws_group === "aIW6gTZ0GcACC17ENWMRYmc2QVKiSkKR80DN#0" ? 1 : 0;

//Conflict category definitions. If two objects have an assigned category, and A_B is in this
//list, then A wins. If B_A is in this list, then B wins. If neither, they bounce off each other.
const conflict_resolution = {
	rock_scissors: "Rock smashes Scissors",
	scissors_paper: "Scissors cut Paper",
	paper_rock: "Paper covers Rock",
	knife_pumpkin: "Knife carves Pumpkin",
	pumpkin_ghost: "Pumpkin scares Ghost",
	ghost_knife: "Ghost possesses Knife",
};
let merge_mode = "normal";

//Map a category ID to the array of things
const thingcategories = { };
//Map category ID to the server-provided information about it
let thingtypes = { };
let fadeouttime = 0, fader = 0, bouncemode = "Bounce", addmode = "Quantities";
let wall_config = { }, wall_objects = { };
const clawqueue = []; //If empty, the claw isn't active. If >1 entries, after the current one, the next will autostart.
//NOTE: These attributes will be applied any time the behaviour is reselected, so ensure that they don't need
//to be set with dedicated methods. Also, ensure that every attribute is set on every behaviour, otherwise things
//will get messy after multiple reselections.
const behaviour_attrs = {
	Gravity: {restitution: 0.25, friction: 0.1, frictionAir: 0.01},
	Floating: {restitution: 1, friction: 0, frictionAir: 0},
};
let behaviour = "Gravity", default_attrs = behaviour_attrs[behaviour];
const id_to_category = { }; //Map a MatterJS body ID to the thing category, or undefined if it isn't a thing

//Create a body from a set of vertices, where the body's origin is at (0,0) regardless of its centre of mass.
//The object will be placed at the origin.
function body_from_path(path, attrs) {
	const verts = Matter.Vertices.fromPath(path);
	let minx = verts[0].x, miny = verts[0].y;
	verts.forEach(v => {
		if (v.x < minx) minx = v.x;
		if (v.y < miny) miny = v.y;
	});
	const body = Matter.Bodies.fromVertices(0, 0, verts, attrs);
	const mins = body.bounds.min;
	//Re-center the body around the original origin. This involves scanning the vertices to find
	//the minimum (x, y) used, then comparing that to the resultant body's boundary, according to
	//the docs' description of correcting the Center of Mass calculation. Is there a better way
	//(read: simpler way) to do this?
	Matter.Body.setCentre(body, {x: mins.x - minx, y: mins.y - miny});
	Matter.Body.setPosition(body, {x: 0, y: 0});
	return body;
}

function unfade() {
	document.body.classList.remove("invisible");
	clearTimeout(fader);
	if (fadeouttime) fader = setTimeout(() => {fader = 0; document.body.classList.add("invisible")}, fadeouttime * 60000 - 5000);
}

const CLAW = {
	mode: "",
	width: 0,
};
function clawdrop() {
	unfade();
	Matter.Composite.translate(CLAW.claw, {x: Math.random() * (width - CLAW.width * 2) + CLAW.width, y: 5000});
	CLAW.mode = "descend";
}

function reset_claw() {
	Matter.Composite.translate(CLAW.claw, {x: -CLAW.head.position.x, y: -CLAW.head.position.y - 5000}); //Hide it way above the screen
	CLAW.claw.bodies.forEach((c, i) => {
		const loc = CLAW.initial_locations[i];
		Matter.Body.setPosition(c, loc);
		Matter.Body.setAngle(c, loc.angle);
	});
}

const shoulderangle = 0.3; //Fairly flat angle for the fixed part of the arm
const armangle = 0.08; //Initial angles. They will change once we touch something.
const shoulderangle_closed = 0.54, armangle_closed = 0.57; //Angles once the claw has fully closed (should still leave a small gap between the talons)
function create_claw(cfg) {
	//NOTE: At the moment, if you recreate the claw while it is ascending, the new claw will
	//be constructed in the jaws-open position, likely dropping any cargo it had been holding.
	let claw_pos = {x: 0, y: -5000}; //Hide it way above the screen
	if (CLAW.claw) { //If there's an existing claw, place this one where that was.
		claw_pos = {x: CLAW.head.position.x, y: CLAW.head.position.y};
		Matter.Composite.remove(engine.world, CLAW.claw);
	}
	const attrs = {
		isStatic: true,
		render: {fillStyle: cfg.clawcolor || "#71797E", lineWidth: 0},
	};
	CLAW.width = +cfg.clawsize; //TODO: Should this be increased a bit?
	const shoulderlength = +cfg.clawsize, armlength = +cfg.clawsize, talonlength = Math.floor(+cfg.clawsize / 4);
	const thickness = +cfg.clawthickness || 1;
	//The primary body of the claw is its head. Everything else is connected to that.
	//Note that the labels starting "head-" are the ones which, when contacted, will trigger the closing of the claw.
	CLAW.head = Matter.Bodies.fromVertices(0, 0, Matter.Vertices.fromPath("1 -12 8 5 4 10 -4 10 -8 5 -1 -12"), {...attrs, isStatic: true, label: "head-0"});
	CLAW.leftshoulder = Rectangle(-8 - shoulderlength / 2, 5, shoulderlength, thickness * 2, {...attrs, label: "head-1"});
	Matter.Body.setCentre(CLAW.leftshoulder, {x: -8, y: 5});
	Matter.Body.rotate(CLAW.leftshoulder, -shoulderangle);
	CLAW.rightshoulder = Rectangle(+8 + shoulderlength / 2, 5, shoulderlength, thickness * 2, {...attrs, label: "head-2"});
	Matter.Body.setCentre(CLAW.rightshoulder, {x: 8, y: 5});
	Matter.Body.rotate(CLAW.rightshoulder, +shoulderangle);
	const shoulderendx = shoulderlength * Math.cos(shoulderangle), shoulderendy = shoulderlength * Math.sin(shoulderangle);
	//Create an arm+talon combo which has its origin point at the top of the arm
	CLAW.leftarmtalon = body_from_path(`-${thickness} -${thickness} -${thickness} ${armlength+thickness} ${talonlength+thickness} ${armlength+thickness} ${talonlength+thickness} ${armlength-thickness} ${thickness} ${armlength-thickness} ${thickness} -${thickness}`, attrs);
	Matter.Body.rotate(CLAW.leftarmtalon, -armangle);
	Matter.Body.setPosition(CLAW.leftarmtalon, {x: -8 - shoulderendx, y: 5 + shoulderendy});
	CLAW.rightarmtalon = body_from_path(`${thickness} -${thickness} ${thickness} ${armlength+thickness} ${-talonlength-thickness} ${armlength+thickness} ${-talonlength-thickness} ${armlength-thickness} -${thickness} ${armlength-thickness} -${thickness} -${thickness}`, attrs);
	Matter.Body.rotate(CLAW.rightarmtalon, armangle);
	Matter.Body.setPosition(CLAW.rightarmtalon, {x: 8 + shoulderendx, y: 5 + shoulderendy});
	CLAW.claw = Matter.Composite.create({
		bodies: [
			//The head
			CLAW.head,
			//The tail
			Rectangle(0, -1000, thickness * 2, 2000, {...attrs, isStatic: true}),
			//Arms
			CLAW.leftshoulder, CLAW.rightshoulder, CLAW.leftarmtalon, CLAW.rightarmtalon,
			//Origin marker (keep last so it's on top)
			Rectangle(0, 0, 3, 3, {isStatic: true, render: {fillStyle: "#ffff22", lineWidth: 0}}),
		],
	});
	Matter.Composite.translate(CLAW.claw, claw_pos);
	if (!CLAW.initial_locations) CLAW.initial_locations = CLAW.claw.bodies.map(c => ({x: c.position.x, y: c.position.y, angle: c.angle}));
	Matter.Composite.add(engine.world, CLAW.claw);
	if (!CLAW.events_created) create_claw_events();
}

function create_claw_events() {
	CLAW.events_created = true;
	const steps = 30;
	Matter.Events.on(engine, "collisionStart", e => CLAW.mode === "descend" && e.pairs.forEach(pair => {
		const isheadA = pair.bodyA.label.startsWith("head-");
		const isheadB = pair.bodyB.label.startsWith("head-");
		if (isheadA !== isheadB) {
			//The head (or shoulder) has touched a thing! Not the armtalon though; if that
			//makes contact, it'll keep pushing, which gives better chances of grabbing.
			//NOTE: If multiple pairs touch in a single frame, this function may be
			//called multiple times. Ensure that it is idempotent. (Spawning multiple
			//timeouts that have the same delay and are themselves idempotent is, in
			//effect, idempotent.)
			CLAW.mode = ""; setTimeout(() => {CLAW.closing = steps; CLAW.mode = "close"}, 500);
		}
	}));
	//Each step, we rotate the shoulder a little, and then the arm a little beyond that.
	//Since the arm gets rotated around the shoulder too, the arm's own step is reduced
	//to compensate. Otherwise it would get double the rotation.
	Matter.Events.on(engine, "afterUpdate", e => {switch (CLAW.mode) {
		case "descend":
			Matter.Composite.translate(CLAW.claw, {x: 0, y: 2});
			//If we hit the floor, the collision check won't detect it, so just close below the surface and pull up.
			if (CLAW.head.position.y >= height) {CLAW.mode = ""; setTimeout(() => {CLAW.closing = steps; CLAW.mode = "close"}, 500);}
			break;
		case "close": {
			//To close the claws, we droop the shoulders slightly and then
			//bring the arm-talon pairs in. This involves rotating both the
			//shoulders and the arm-talons by the shoulder rotation, and
			//then rotating the arm-talons alone by the arm rotation.

			//As the step counter descends from steps to zero, the angles
			//should gently curve from their initial to final values. This
			//is done with a cosine curve starting at -pi and going to zero,
			//yielding positions from -1 to 1; rescaling this to be from 0
			//to 1 makes them into a fraction of the delta.
			--CLAW.closing;
			const pos = Math.cos((-CLAW.closing / steps) * Math.PI) / 2 + 0.5; //From zero to one
			const shouldergoal = shoulderangle + (shoulderangle_closed - shoulderangle) * pos;
			const armgoal = armangle + (armangle_closed - armangle) * pos;
			const shoulderstep = shouldergoal - CLAW.rightshoulder.angle;
			Matter.Body.rotate(CLAW.leftshoulder, -shoulderstep);
			Matter.Body.rotate(CLAW.rightshoulder, shoulderstep);
			Matter.Body.rotate(CLAW.leftarmtalon, -shoulderstep, {x: CLAW.leftshoulder.position.x, y: CLAW.leftshoulder.position.y});
			Matter.Body.rotate(CLAW.rightarmtalon, shoulderstep, {x: CLAW.rightshoulder.position.x, y: CLAW.rightshoulder.position.y});
			const armstep = armgoal - CLAW.rightarmtalon.angle;
			Matter.Body.rotate(CLAW.leftarmtalon, -armstep);
			Matter.Body.rotate(CLAW.rightarmtalon, armstep);
			if (!CLAW.closing) {
				CLAW.mode = ""; setTimeout(() => CLAW.mode = "ascend", 500);
			}
			break;
		}
		case "ascend":
			Matter.Composite.translate(CLAW.claw, {x: 0, y: -1});
			if (CLAW.head.position.y < -100) {
				CLAW.mode = "";
				//See what's above the screen. Note that there might be more than one thing,
				//but we'll only claim one prize (chosen randomly).
				let prizes = [], prizetype = "", label = null;
				engine.world.bodies.forEach(body => {if (body.position.y < 0) {
					const thingtype = id_to_category[body.id];
					if (!thingtype) return; //Notably, the top wall isn't in a thing category.
					const idx = thingcategories[thingtype].findIndex(thing => thing.id === body.id);
					if (idx >= 0) prizes.push([body, thingtype, idx]);
				}});
				if (prizes.length) {
					const prize = prizes[Math.floor(Math.random() * prizes.length)];
					thingcategories[prize[1]].splice(prize[2], 1);
					prizetype = prize[1];
					label = prize[0].label;
					Matter.Composite.remove(engine.world, prize[0]);
				}
				const clawid = clawqueue.shift(); //TODO: Have an autoretry option, which will skip shifting the queue if there was no prize.
				if (clawid && !window.frameElement) ws_sync.send({cmd: "clawdone", prizetype, label, clawid});
				reset_claw();
				if (clawqueue.length) setTimeout(clawdrop, 2000);
			}
			break;
	}});
}

//Apply random force to all objects, randomized within the span given, and multiplied by the magnitude.
function jostle(left, right, up, down, magnitude) {
	Object.values(thingcategories).forEach(cat => cat.forEach(obj =>
		Matter.Body.applyForce(obj, obj.position, {
			x: (Math.random() * (left + right) - left) * obj.mass * magnitude,
			y: (Math.random() * (up + down) - up) * obj.mass * magnitude,
		})
	));
}

const addxtra = { };

//For a given color eg #663399 and alpha eg 100, return an eight digit hex color. Note that alpha is in the range 0-100.
function hexcolor(color, alpha) {
	return (color || "#000000") + ("0" + Math.floor((alpha || 0) * 2.55 + 0.5).toString(16)).slice(-2);
}

let _bounce_events_created = false;
export function render(data) {
	if (data.data) { //Odd name but this is the primary reconfiguration
		if (data.data.fadeouttime) fadeouttime = +data.data.fadeouttime;
		if (data.data.behaviour && data.data.behaviour !== behaviour) {
			behaviour = data.data.behaviour;
			default_attrs = behaviour_attrs[behaviour] || behaviour_attrs.Gravity;
			engine.gravity.scale = behaviour === "Floating" ? 0 : 0.001;
			//TODO: What about the claw? Should its attributes be updated? They aren't currently being
			//applied in the first place.
			Matter.Composite.allBodies(engine.world).forEach(body => {
				for (let attr in default_attrs) body[attr] = default_attrs[attr];
			});
		}
		if (data.data.addmode) addmode = data.data.addmode;
		if (data.data.bouncemode) {
			bouncemode = data.data.bouncemode;
			if (!_bounce_events_created && bouncemode === "Merge") {
				_bounce_events_created = true;
				Matter.Events.on(engine, "collisionStart", e => bouncemode === "Merge" && e.pairs.forEach(pair => {
					if (!id_to_category[pair.bodyA.id] || !id_to_category[pair.bodyB.id]) return;
					if (merge_mode === "off") return; //The server can choose to (temporarily) disable all merging
					//If either of the textures hasn't loaded, let the things bounce off each other.
					//It'll be slightly odd in that an invisible object might cause a visible one to veer off, but
					//at least it won't result in things getting eaten by invisible (newly-added) objects.
					const texA = renderer.textures[pair.bodyA.render.sprite.texture];
					const texB = renderer.textures[pair.bodyB.render.sprite.texture];
					if (!texA || !texB || !texA.complete || !texB.complete) return;
					//To support Rock-Paper-Scissors merge, we need:
					//1) Conflict category for A and B
					//2) Conflict resolution for the pair of categories
					//If there is no conflict category for either object, merge B into A (ie A is winner).
					//If there is a conflict category for exactly one, or if they both have categories but
					//there is no defined resolution, then the objects bounce (just return).
					//Otherwise, the resolution will be either "A wins" or "B wins".
					let winner = pair.bodyA, loser = pair.bodyB;
					const confcatA = pair.bodyA.plugin.mustardmine_conflict;
					const confcatB = pair.bodyB.plugin.mustardmine_conflict;
					let conflict_description = null;
					if (confcatA && confcatB) {
						//Do we have a description showing that A beats B? If so, save that description
						//and carry on, letting A win.
						conflict_description = conflict_resolution[confcatA + "_" + confcatB];
						if (!conflict_description) {
							//Do we have one showing that B beats A? If so, swap winner and loser.
							conflict_description = conflict_resolution[confcatB + "_" + confcatA];
							if (conflict_description) {winner = pair.bodyB; loser = pair.bodyA;}
							//Otherwise, they bounce off. Paper collides with Paper.
							else return;
						}
					}
					//If one (but not both) has a category, they bounce off. Don't merge with the walls.
					else if (confcatA || confcatB) return;
					//So. To merge two objects, we add all the mass and momentum from bodyB onto bodyA,
					//then delete bodyB. If this results in bodyA becoming larger than the default size
					//for another body type, we should switch its type.
					const massA = winner.mass, massB = loser.mass, massAB = massA + massB;
					let scale = (massAB / massA) ** 0.5;
					if (scale > 4.0) scale = 1.0; //Muahahaha. If you get too big, you get shrunked down to size!
					//True conservation of angular momentum is a pain. We cheat. Each body contributes
					//an amount of pseudo-momentum equal to its velocity times its mass, which completely
					//ignores the size. Realistically, two objects with identical velocity and mass, but
					//different sizes, will have different angular momentum, but we assume uniform density
					//anyway, so this is massively fudged.
					const ang_vel = (winner.angularVelocity * massA + loser.angularVelocity * massB) / massAB;
					//Linear momentum is simpler. Velocity (in each basis direction) times mass.
					const lin_vel = {
						x: (winner.velocity.x * massA + loser.velocity.x * massB) / massAB,
						y: (winner.velocity.y * massA + loser.velocity.y * massB) / massAB,
					};
					Matter.Body.scale(winner, scale, scale);
					Matter.Body.setAngularVelocity(winner, ang_vel);
					Matter.Body.setVelocity(winner, lin_vel);
					//TODO: Reposition to the barycenter of the two objects?
					winner.render.sprite.xScale *= scale;
					winner.render.sprite.yScale *= scale;
					const thingtype = id_to_category[loser.id];
					const things = thingcategories[thingtype];
					id_to_category[loser.id] = null;
					const idx = things.findIndex(t => t.id === loser.id);
					if (idx >= 0) things.splice(idx, 1);
					if (!window.frameElement) ws_sync.send({cmd: "removed", thingtype, conflict_description, label: loser.label, newcount: things.length});
					Matter.Composite.remove(engine.world, loser);
					if (merge_mode === "contest") {
						//Once there's only one merge mode left, that is the winner!
						const mergemode = winner.plugin.mustardmine_conflict;
						let allsame = true;
						Object.values(thingcategories).forEach(cat => cat.forEach(thing => {
							if (thing.plugin.mustardmine_conflict !== mergemode) allsame = false;
						}));
						if (allsame) {
							ws_sync.send({cmd: "contestwinner", mergemode});
							merge_mode = "normal";
						}
					}
				}));
			}
		}
		if (data.data.things) thingtypes = Object.fromEntries(data.data.things.map(t => [t.id, t]));
		renderer.options.background = hexcolor(data.data.bgcolor, data.data.bgalpha);
		//If the floor dimension changes, recreate the walls as well. Otherwise, only recreate what's changed.
		//(Usually that'll be nothing. Changing the walls and floor is unusual.)
		const wallcolor = hexcolor(data.data.wallcolor, data.data.wallalpha);
		const floor_changed = data.data.wall_floor !== wall_config.floor
			|| wallcolor !== wall_config.color;
		for (let side of ["floor", "left", "right", "top"]) {
			if (data.data["wall_" + side] !== wall_config[side] || floor_changed) {
				wall_config[side] = data.data["wall_" + side];
				if (wall_objects[side]) {
					Matter.Composite.remove(engine.world, wall_objects[side]);
					delete wall_objects[side];
				}
			}
		}
		//The walls should have some thickness to them, to prevent weird bouncing. At 2px, there's a lot of bouncing;
		//even at 10px there's occasional issues. However, thicker walls look weird if the floor isn't 100% size.
		const wall_thickness = 95 < +wall_config.floor ? 60 : 10;
		//The need fields are 0 if no recreation is needed, or a percentage eg 50% to create a half-size wall.
		const need_top = !wall_objects.top && +wall_config.top;
		const need_floor = !wall_objects.floor && +wall_config.floor;
		const need_left = !wall_objects.left && +wall_config.left;
		const need_right = !wall_objects.right && +wall_config.right;
		const floor_size = width * +wall_config.floor / 200 + wall_thickness / 2 - 2;
		if (need_top) Matter.Composite.add(engine.world,
			//NOTE: The top is not placed above the left/right walls, but always at the very top. If
			//the left/right are not full height, there will be a gap below the top wall.
			wall_objects.top = Rectangle(width / 2, -28, width * need_top / 100 + 10, 60,
				{isStatic: true, render: {fillStyle: wallcolor, lineWidth: 0}, ...default_attrs}));
		if (need_floor) Matter.Composite.add(engine.world,
			wall_objects.floor = Rectangle(width / 2, height + 28, width * need_floor / 100 + 10, 60,
				{isStatic: true, render: {fillStyle: wallcolor, lineWidth: 0}, ...default_attrs}));
		if (need_left) Matter.Composite.add(engine.world,
			wall_objects.left = Rectangle(width / 2 - floor_size, height - height * need_left / 200, wall_thickness, height * need_left / 100 + 10,
				{isStatic: true, render: {fillStyle: wallcolor, lineWidth: 0}, ...default_attrs}));
		if (need_right) Matter.Composite.add(engine.world,
			wall_objects.right = Rectangle(width / 2 + floor_size, height - height * need_right / 200, wall_thickness, height * need_right / 100 + 10,
				{isStatic: true, render: {fillStyle: wallcolor, lineWidth: 0}, ...default_attrs}));
		if (+data.data.clawsize) create_claw(data.data);
		if (autorps === 1) {
			autorps = 2; //One autorps only, no more.
			merge_mode = "off";
			setTimeout(() => merge_mode = "normal", 5000);
			const uids = [49497888, 279141671, 54212603, 469694955, 265796767, 122743188];
			const augs = ["rock", "rock", "paper", "paper", "scissors", "scissors"];
			//const augs = ["knife", "knife", "pumpkin", "pumpkin", "ghost", "ghost"];
			const vips = [false, false, false, false, true, true];
			while (uids.length && augs.length && vips.length) {
				const uid = uids.splice(Math.floor(Math.random() * uids.length), 1)[0];
				const aug = augs.splice(Math.floor(Math.random() * augs.length), 1)[0];
				const vip = vips.splice(Math.floor(Math.random() * vips.length), 1)[0];
				render({silentmode: 1, addthing: "avatar", addxtra: "avatar", xtra: {
					conflict_category: aug,
					image: {
						url: "monitors?augment=" + aug + "&userid=" + uid + (vip ? "&crown" : ""),
						xsize: 448, ysize: 448,
					},
					label: "RPS demo", //Not putting usernames here as nothing uses them anyway
				}});
			}
			data.newcount = null;
		}
	}
	if (data.addxtra) addxtra[data.addxtra] = data.xtra;
	if (data.addthing) data.newcount = {[data.addthing]: (thingcategories[data.addthing]?.length||0) + 1};
	if (data.newcount) Object.entries(data.newcount).forEach(([thingtype, newcount]) => {
		const cat = thingtypes[thingtype];
		if (!cat) return;
		if (!thingcategories[thingtype]) thingcategories[thingtype] = [];
		const things = thingcategories[thingtype];
		while (things.length > newcount) Matter.Composite.remove(engine.world, things.pop());
		while (things.length < newcount) {
			if (addmode === "Explicit only" && !addxtra[thingtype]) break;
			const xtra = addxtra[thingtype] || { }; delete addxtra[thingtype];
			const img = xtra.image || cat.images[Math.floor(Math.random() * cat.images.length)] || default_thing_image;
			const scale = cat.xsize / img.xsize;
			const attrs = {
				render: {sprite: {
					texture: img.url,
					xOffset: img.xoffset || 0, yOffset: img.yoffset || 0,
					xScale: scale, yScale: scale, 
				}},
				...default_attrs,
			};
			if (xtra.label) attrs.label = "label-" + xtra.label; //Force a prefix so we can do hit-detection based on label category
			if (xtra.conflict_category) attrs.plugin = {mustardmine_conflict: xtra.conflict_category};
			let obj;
			const ysize = Math.ceil(img.ysize * scale);
			const xpos = Math.floor(Math.random() * (width - cat.xsize - 30) + cat.xsize / 2 + 15);
			//When things float around, start them anywhere. When they fall, start them near the top.
			const ypos = behaviour === "Floating"
				? Math.floor(Math.random() * (height - ysize - 30) + ysize / 2 + 15)
				: Math.floor(Math.random() * 100 + 10);
			switch (cat.shape) {
				case "circle": obj = Circle(
					xpos, ypos,
					cat.xsize / 2, //Our idea of xsize is width, so the radius is half that
					attrs);
				break;
				case "hull": if (/*img.simplehull || */img.hull) {
					obj = Matter.Body.create({
						position: {x: xpos, y: ypos},
						vertices: (/*img.simplehull || */img.hull).map(([x, y]) => ({x: x * scale, y: y * scale})),
						...attrs,
					});
					break;
				}
				//If no hull, fall through and make a simple rectangle.
				default: obj = Rectangle(
					xpos, ypos,
					cat.xsize, ysize,
					attrs);
			}
			//Angles are measured in radians. Angular velocity seems to be rad/frame and we're at
			//60Hz physics rate, meaning that 0.01 will rotate you by 0.60 rad/sec (before friction is
			//taken into account). Provide each newly-added element with a bit of rotation, either direction.
			Matter.Body.setAngularVelocity(obj, Math.random() * .2 - .1);
			//And if we're in zero-grav mode, also move them around a bit. More down than up.
			if (behaviour === "Floating") Matter.Body.setVelocity(obj, {x: Math.random() * width / 50 - width / 100, y: Math.random() * height / 50 - height / 200});
			Matter.Composite.add(engine.world, obj);
			things.push(obj);
			id_to_category[obj.id] = thingtype;
			//A new thing has been added! Make the pile visible.
			unfade();
		}
		if (data.addthing && !data.silentmode) ws_sync.send({cmd: "added", thingtype, newcount});
	});
	if (data.claw && CLAW.claw) {
		clawqueue.push(data.claw);
		if (clawqueue.length === 1) clawdrop();
	}
	if (data.shake) {
		//Add some random kinetic energy to all things. Tends to be more up than down. Works well with gravity piles.
		unfade();
		jostle(0.2, 0.2, 0.15, 0.05, data.shake);
	}
	if (data.rattle) {
		//Add random kinetic energy to all things multiple times. Mostly horizontal.
		unfade();
		setTimeout(jostle,   0, 0.1, 0.1, 0.020, 0.010, data.rattle);
		setTimeout(jostle, 100, 0.1, 0.1, 0.001, 0.001, data.rattle);
		setTimeout(jostle, 250, 0.1, 0.1, 0.030, 0.000, data.rattle);
		setTimeout(jostle, 500, 0.1, 0.1, 0.010, 0.010, data.rattle);
	}
	if (data.roll) {
		//Rotate gravity through a 360° turn. If there is no gravity, it will be added for the duration.
		unfade();
		const scale = engine.gravity.scale;
		engine.gravity.scale = width / 1.5e6; //A good-looking flight speed depends on how much of the display we traverse per time unit
		let start = +new Date;
		const timer = setInterval(() => {
			let pos = (+new Date - start) / 500; //After pi seconds, this will reach tau
			if (pos > Math.PI * 2) {
				clearInterval(timer);
				engine.gravity.x = 0;
				engine.gravity.y = 1;
				engine.gravity.scale = scale;
				return;
			}
			//NOTE: Normal orientation of trig functions puts sine on the Y axis and cosine on the X,
			//but in this case, the starting position (0 radians) corresponds to gravity pointing
			//straight down. We could do this by subtracting a quarter turn before taking the sin/cos,
			//but the same effect is achieved by flipping the coordinates.
			engine.gravity.x = Math.sin(pos);
			engine.gravity.y = Math.cos(pos);
		}, 0.01);
	}
	if (data.remove) {
		//Remove one of a thingtype, choosing based on label
		const things = thingcategories[data.remove];
		if (!things) return;
		for (let i = 0; i < things.length; ++i) {
			const thing = things[i];
			if (thing.label !== "label-" + data.label) continue;
			if (!window.frameElement) ws_sync.send({cmd: "removed", thingtype: data.remove, label: thing.label});
			Matter.Composite.remove(engine.world, thing);
			things.splice(i, 1);
			return;
		}
	}
	if (data.merge) merge_mode = data.merge;
}
if (!autorps) ws_sync.send({cmd: "querycounts"});

//Demo mode? Emote dropping mode?
if (0) setInterval(() => {
	const cat = thingtypes.emotes; //TODO: User selection from the available categories
	if (!cat) return;
	const img = cat[Math.floor(Math.random() * cat.length)];
	const obj = Rectangle(Math.floor(Math.random() * width), Math.floor(Math.random() * 100 + 10), img.xsize, img.ysize, {
		render: {sprite: {texture: img.url, xOffset: img.xoffset, yOffset: img.yoffset}},
	});
	//Angles are measured in radians. Angular velocity seems to be rad/frame and we're at
	//60Hz physics rate, meaning that 0.01 will rotate you by 0.60 rad/sec (before friction is
	//taken into account). Provide each newly-added element with a bit of rotation, either direction.
	Matter.Body.setAngularVelocity(obj, Math.random() * .2 - .1);
	Matter.Composite.add(engine.world, obj);
}, 2000);
//TODO: Handle things dropping past the floor? Would need to remove them and signal the server to decrement the count.
//Might need to be governed by a broadcaster control.

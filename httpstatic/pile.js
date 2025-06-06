const hacks = ws_group === "4OCNIkpnmXUkUF0s0SfmOuKzurlCP6mlwxeM#49497888";
const engine = Matter.Engine.create();
const width = window.innerWidth - 20, height = window.innerHeight - 20;
//NOTE: For debugging and testing, background and fillStyle are both colours. For
//production, they should be transparent, with actual elements for interaction purposes.
const visible_walls = hacks;
const renderer = Matter.Render.create({element: document.getElementById("display"), engine, options: {
	background: visible_walls ? "aliceblue" : "transparent", width, height,
}});
const Rectangle = Matter.Bodies.rectangle, Circle = Matter.Bodies.circle;
Matter.Render.run(renderer);
Matter.Runner.run(Matter.Runner.create(), engine);
renderer.options.wireframes = false;
window.renderer = renderer; //For debugging, eg toggle wireframes mode

if (hacks) {
	console.log("Hacks mode enabled");
	const attrs = {
		isStatic: true,
		render: {fillStyle: "#71797E", lineWidth: 0},
	};
	//The primary body of the claw is its head. Everything else is connected to that.
	const armlength = 50, clawlength = 50; //TODO: Make configurable (maybe as a single size, rather than separate arm/claw lengths)
	const armangle = 0.3; //Fairly flat angle for the fixed part of the arm
	const initialclawangle = 1.65; //Just past the vertical for the claws as we descend
	const finalclawangle = 3.05; //Nearly horizontal when the claws close (if they don't touch anything)
	const leftarm = Rectangle(-8 - armlength / 2, 5, armlength, 2, attrs);
	Matter.Body.rotate(leftarm, -armangle, {x: -8, y: 5});
	const rightarm = Rectangle(+8 + armlength / 2, 5, armlength, 2, attrs);
	Matter.Body.rotate(rightarm, +armangle, {x: +8, y: 5});
	const clawx = +8 + armlength * Math.cos(armangle), clawy = 5 + armlength * Math.sin(armangle);
	const leftclaw = Rectangle(-clawx - clawlength / 2, clawy, clawlength, 2, attrs);
	Matter.Body.rotate(leftclaw, -initialclawangle, {x: -clawx, y: clawy});
	const rightclaw = Rectangle(+clawx + clawlength / 2, clawy, clawlength, 2, attrs);
	Matter.Body.rotate(rightclaw, +initialclawangle, {x: +clawx, y: clawy});
	const claw = Matter.Composite.create({
		bodies: [
			//The head
			Matter.Bodies.fromVertices(0, 0, Matter.Vertices.fromPath("1 -12 8 5 4 10 -4 10 -8 5 -1 -12"), attrs),
			//The tail
			Rectangle(0, -1000, 2, 2000, attrs),
			//Arms
			leftarm, rightarm, leftclaw, rightclaw,
			//Origin marker (keep last so it's on top)
			Rectangle(0, 0, 3, 3, {isStatic: true, render: {fillStyle: "#ffff22", lineWidth: 0}}),
		],
	});
	Matter.Composite.translate(claw, {x: width / 2, y: height / 5});
	Matter.Composite.add(engine.world, claw);
}

//Map a category ID to the array of things
const thingcategories = { };
//Map category ID to the server-provided information about it
let thingtypes = { };
let fadeouttime = 0, fader = 0;
let wall_sizes = { }, wall_objects = { };
export function render(data) {
	if (data.data) {
		if (data.data.fadeouttime) fadeouttime = +data.data.fadeouttime;
		if (data.data.things) thingtypes = Object.fromEntries(data.data.things.map(t => [t.id, t]));
		//If the floor dimension changes, recreate the walls as well. Otherwise, only recreate what's changed.
		//(Usually that'll be nothing. Changing the walls and floor is unusual.)
		let floor_changed = data.data.wall_floor !== wall_sizes.floor;
		for (let side of ["floor", "left", "right"]) {
			if (data.data["wall_" + side] !== wall_sizes[side] || floor_changed) {
				wall_sizes[side] = data.data["wall_" + side];
				if (wall_objects[side]) {
					Matter.Composite.remove(engine.world, wall_objects[side]);
					delete wall_objects[side];
				}
			}
		}
		//The walls should have some thickness to them, to prevent weird bouncing. At 2px, there's a lot of bouncing;
		//even at 10px there's occasional issues. However, thicker walls look weird if the floor isn't 100% size.
		const wall_thickness = 95 < +wall_sizes.floor ? 60 : 10;
		//The need fields are 0 if no recreation is needed, or a percentage eg 50% to create a half-size wall.
		const need_floor = !wall_objects.floor && +wall_sizes.floor;
		const need_left = !wall_objects.left && +wall_sizes.left;
		const need_right = !wall_objects.right && +wall_sizes.right;
		const floor_size = width * +wall_sizes.floor / 200 + wall_thickness / 2 - 2;
		if (need_floor) Matter.Composite.add(engine.world,
			wall_objects.floor = Rectangle(width / 2, height + 28, width * need_floor / 100 + 10, 60,
				{isStatic: true, render: {fillStyle: visible_walls ? "rebeccapurple" : "transparent", lineWidth: 0}}));
		if (need_left) Matter.Composite.add(engine.world,
			wall_objects.left = Rectangle(width / 2 - floor_size, height - height * need_left / 200, wall_thickness, height * need_left / 100 + 10,
				{isStatic: true, render: {fillStyle: visible_walls ? "rebeccapurple" : "transparent", lineWidth: 0}}));
		if (need_right) Matter.Composite.add(engine.world,
			wall_objects.right = Rectangle(width / 2 + floor_size, height - height * need_right / 200, wall_thickness, height * need_right / 100 + 10,
				{isStatic: true, render: {fillStyle: visible_walls ? "rebeccapurple" : "transparent", lineWidth: 0}}));
	}
	if (data.newcount) Object.entries(data.newcount).forEach(([thingtype, newcount]) => {
		const cat = thingtypes[thingtype];
		if (!cat) return;
		if (!thingcategories[thingtype]) thingcategories[thingtype] = [];
		const things = thingcategories[thingtype];
		while (things.length > newcount) Matter.Composite.remove(engine.world, things.pop());
		while (things.length < newcount) {
			const img = cat.images[Math.floor(Math.random() * cat.images.length)] || default_thing_image;
			const scale = cat.xsize / img.xsize;
			const attrs = {
				render: {sprite: {
					texture: img.url,
					//xOffset: cat.xoffset || 0, yOffset: cat.yoffset || 0, //Not currently configured on the back end
					xScale: scale, yScale: scale, 
				}},
				restitution: 0.25, //Make 'em a little bit bouncier
			};
			let obj;
			switch (cat.shape) {
				case "circle": obj = Circle(
					Math.floor(Math.random() * (width - cat.xsize - 30) + cat.xsize / 2 + 15),
					Math.floor(Math.random() * 100 + 10),
					cat.xsize / 2, //Our idea of xsize is width, so the radius is half that
					attrs);
				break;
				default: obj = Rectangle(
					Math.floor(Math.random() * (width - cat.xsize - 30) + cat.xsize / 2 + 15),
					Math.floor(Math.random() * 100 + 10),
					cat.xsize, Math.ceil(img.ysize * scale),
					attrs);
			}
			//Angles are measured in radians. Angular velocity seems to be rad/frame and we're at
			//60Hz physics rate, meaning that 0.01 will rotate you by 0.60 rad/sec (before friction is
			//taken into account). Provide each newly-added element with a bit of rotation, either direction.
			Matter.Body.setAngularVelocity(obj, Math.random() * .2 - .1);
			Matter.Composite.add(engine.world, obj);
			things.push(obj);
			//A new thing has been added! Make the pile visible.
			document.body.classList.remove("invisible");
			clearTimeout(fader);
			if (fadeouttime) fader = setTimeout(() => {fader = 0; document.body.classList.add("invisible")}, fadeouttime * 60000 - 5000);
		}
	});
}
ws_sync.send({cmd: "querycounts"});

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
//TODO: If stable mode is selected, then after adding something, set a quarter-second interval timer to
//check the newly created thing's speed, and if it's low enough, setStatic() on it.
//Alternatively, set everything to Sleeping? Wake them up when something new is added?
/* Next steps:

* Create an object type ("category", need a good name for it)
* Upload an image for an object type - may be done more than once. If not done, will use Mustard Mine squavatar.
* Builtin to manipulate objects
  - Needs a type. Will only manipulate objects of that type.
  - Add N (default to 1), remove N (default to 1), or set to N on screen
    - "+1", "-1", "1"?
* Handle objects falling off the bottom?
* On the edit dlg, button to add/remove objects given a type

*/

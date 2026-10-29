shader_type canvas_item;
render_mode unshaded;

uniform sampler2D paint_source : source_color, filter_linear, repeat_disable;
uniform float local_clock = 0.0;
uniform bool focused = false;

const vec2 opening[8] = {vec2(16.0,8.0),vec2(30.0,3.0),vec2(44.0,8.0),vec2(55.0,24.0),vec2(61.0,43.0),vec2(58.0,94.0),vec2(4.0,94.0),vec2(7.0,37.0)};

float arch_distance(vec2 p) {
	float edge_distance = 1000.0;
	for (int i=0; i<8; i++) {
		vec2 edge = opening[(i+1)%8]-opening[i];
		vec2 offset = p-opening[i];
		edge_distance = min(edge_distance,(edge.x*offset.y-edge.y*offset.x)/length(edge));
	}
	return edge_distance;
}

vec3 painted_flow(vec2 p, float phase) {
	// Increasing the sampled radius brings painted features inward. Two soft
	// overlapping cycles hide the reset, rather than moving a digital line ring.
	float radius = length(p);
	float turn = local_clock*0.105 + radius*0.06;
	mat2 rotate = mat2(vec2(cos(turn),sin(turn)),vec2(-sin(turn),cos(turn)));
	vec2 brush = rotate*p*exp((phase-0.5)*0.30);
	vec2 source_uv = clamp(vec2(0.461,0.580)+brush*vec2(0.175,0.153),vec2(0.276,0.417),vec2(0.708,0.753));
	return texture(paint_source,source_uv).rgb;
}

void fragment() {
	float clip = smoothstep(0.0,0.85,arch_distance(UV*vec2(63.0,100.0)));
	vec2 p = (UV-vec2(0.50,0.55))/vec2(0.48,0.52);
	float phase_a = fract(local_clock*0.046);
	float phase_b = fract(local_clock*0.046+0.5);
	float weight_a = pow(sin(phase_a*3.14159265),2.0);
	float weight_b = pow(sin(phase_b*3.14159265),2.0);
	vec3 paint = (painted_flow(p,phase_a)*weight_a+painted_flow(p,phase_b)*weight_b)/max(0.001,weight_a+weight_b);
	float edge_depth = smoothstep(0.4,1.1,length(p));
	paint = mix(paint*vec3(0.87,0.91,0.94),vec3(0.16,0.40,0.55),edge_depth*0.27);
	paint *= 0.94+0.025*sin(local_clock*0.65);
	if (focused) paint = mix(paint,vec3(0.71,0.91,0.92),0.09);
	COLOR = vec4(paint,clip*0.94);
}

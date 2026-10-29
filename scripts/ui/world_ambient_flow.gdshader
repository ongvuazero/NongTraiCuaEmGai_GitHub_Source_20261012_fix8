shader_type canvas_item;
render_mode unshaded;

uniform float local_clock = 0.0;
uniform int effect_kind = 0;
uniform float strength : hint_range(0.0,1.0) = 0.15;
uniform vec2 flow_direction = vec2(0.5,0.1);
uniform vec2 region_size = vec2(100.0,100.0);
uniform vec2 region_origin = vec2(0.0,0.0);
uniform vec4 ui_blocks[32];
uniform int ui_block_count = 0;
uniform vec4 tint : source_color = vec4(0.75,0.93,1.0,1.0);
uniform sampler2D world_plate : source_color, filter_linear;
uniform vec2 canvas_size = vec2(1280.0,720.0);
uniform vec2 plate_origin = vec2(0.0);
uniform vec2 plate_size = vec2(1280.0,720.0);
uniform float phase = 0.0;
uniform float sway_pixels = 2.6;
uniform vec2 mask_points[20];
uniform int mask_point_count = 0;
varying vec2 scene_vertex;

void vertex() {
    scene_vertex = VERTEX;
    if (effect_kind == 7) {
        // Crop tops bend while the actual planting root and hit geometry stay fixed.
        float rooted = pow(clamp(1.0-UV.y,0.0,1.0),2.0);
        VERTEX.x += sin(local_clock*0.95+phase+UV.y*1.7)*sway_pixels*rooted;
    }
}

float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(cell),hash21(cell+vec2(1,0)),u.x),mix(hash21(cell+vec2(0,1)),hash21(cell+vec2(1,1)),u.x),u.y);
}

float painted_edge(vec2 point) {
    float nearest = 10000.0;
    for (int i=0; i<20; i++) {
        if (i >= mask_point_count) { break; }
        int next = i + 1;
        if (next >= mask_point_count) { next = 0; }
        vec2 a = mask_points[i];
        vec2 segment = mask_points[next]-a;
        float along = clamp(dot(point-a,segment)/max(dot(segment,segment),0.0001),0.0,1.0);
        nearest = min(nearest,length(point-a-segment*along));
    }
    return smoothstep(0.0,2.4,nearest);
}

vec3 painted_flow(vec2 point,vec2 direction,float speed,float span) {
    // Two painted samples crossfade while traveling in one direction. Each
    // sample resets only at zero weight; there is no whole-plate UV warp.
    float travel = mod(local_clock*speed+phase,span);
    float second = mod(travel+span*0.5,span);
    float first_weight = pow(sin(travel/span*3.14159265),2.0);
    float second_weight = 1.0-first_weight;
    vec3 a = texture(world_plate,(point-direction*travel-plate_origin)/plate_size).rgb;
    vec3 b = texture(world_plate,(point-direction*second-plate_origin)/plate_size).rgb;
    return a*first_weight+b*second_weight;
}

void fragment() {
    vec4 sprite_color = COLOR;
    vec2 px = scene_vertex - region_origin;
    vec2 region_uv = px / region_size;
    float t = local_clock;
    vec3 rgb = tint.rgb;
    float alpha = 0.0;
    if (effect_kind == 0 || effect_kind == 1 || effect_kind == 2) {
        vec3 base = texture(world_plate,(scene_vertex-plate_origin)/plate_size).rgb;
        bool falling = effect_kind == 1 || effect_kind == 2;
        vec2 direction = normalize(flow_direction+vec2(0.00001));
        float span = falling ? 5.5 : 3.2;
        float speed = effect_kind == 2 ? 1.4 : falling ? 5.5 : 1.5;
        rgb = painted_flow(scene_vertex,direction,speed,span);
        // Keep rocks, boats, plants and architecture fixed even at imperfect
        // traced boundaries. Source pigment determines water/lava coverage.
        float cool = smoothstep(0.03,0.12,base.b-base.r)*smoothstep(0.02,0.10,base.g-base.r);
        float white_foam = smoothstep(0.65,0.90,min(base.r,min(base.g,base.b)));
        float painted_water = max(cool,falling ? white_foam : 0.0);
        if (effect_kind == 2) { painted_water = smoothstep(0.12,0.35,base.r-base.b)*smoothstep(0.35,0.70,base.r); }
        alpha = min(strength*2.2,0.74)*painted_water*painted_edge(scene_vertex);
    } else if (effect_kind == 3) {
        vec2 advected = px * 0.024 - t * flow_direction * 0.20;
        float soft = noise(advected) * 0.7 + noise(advected * 1.8 + 15.0) * 0.3;
        float edge = smoothstep(0.0,0.16,region_uv.x) * smoothstep(0.0,0.16,1.0-region_uv.x) * smoothstep(0.0,0.2,region_uv.y) * smoothstep(0.0,0.2,1.0-region_uv.y);
        alpha = strength * smoothstep(0.22,0.83,soft) * edge;
    } else if (effect_kind == 4) {
        vec2 center = vec2(0.5,1.18);
        float distance_to_arc = length((region_uv-center)*vec2(1.0,0.73));
        float band = smoothstep(0.61,0.66,distance_to_arc) * (1.0-smoothstep(0.72,0.77,distance_to_arc));
        float hue = clamp((distance_to_arc - 0.63) / 0.13,0.0,1.0);
        rgb = 0.65 + 0.35*cos(vec3(0.0,2.1,4.2) + hue * 4.2);
        alpha = min(strength,0.038) * band * sin(clamp(region_uv.x,0.0,1.0)*3.14159) * (0.92 + 0.08*sin(t*0.27));
    } else if (effect_kind == 5) {
        float distance_to_light = length((region_uv-vec2(0.5))*2.0);
        alpha = strength * exp(-distance_to_light*3.5) * (0.92 + 0.08*sin(t*0.30+1.0));
    } else if (effect_kind == 6 || effect_kind == 9) {
        // Flattened painting has no clean backplate beneath its leaves or
        // cloth. Keep those silhouettes fixed: drifting loose leaves supply
        // wind, while a gentle pigment sheen passes through the traced patch.
        vec3 base = texture(world_plate,(scene_vertex-plate_origin)/plate_size).rgb;
        float leaf = smoothstep(0.015,0.09,base.g-base.r)*smoothstep(0.02,0.08,base.g-base.b);
        float sheen = noise(px*0.047-vec2(t*0.12,0.0)+phase);
        rgb = base*(0.985+0.045*sheen);
        alpha = strength*painted_edge(scene_vertex)*(effect_kind == 9 ? 0.55 : leaf*0.65);
    } else {
        alpha = 0.0;
    }
    vec2 scene_point = region_origin + px;
    for (int i=0; i<32; i++) {
        if (i >= ui_block_count) { break; }
        vec4 block = ui_blocks[i];
        if (scene_point.x >= block.x && scene_point.y >= block.y && scene_point.x <= block.x+block.z && scene_point.y <= block.y+block.w) { alpha = 0.0; }
    }
    COLOR = effect_kind == 7 ? sprite_color : vec4(rgb,alpha);
}

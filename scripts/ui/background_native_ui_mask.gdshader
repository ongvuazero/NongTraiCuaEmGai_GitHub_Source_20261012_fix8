shader_type canvas_item;
render_mode unshaded;

// Preserve original native panel pixels and reveal the new scenery around
// them. Dynamic labels, thumbnails, icons and hit targets are separate nodes.
uniform vec2 source_size = vec2(1280.0, 720.0);
uniform int keep_rect_count = 0;
uniform vec4 keep_rects[16];
uniform int restore_rect_count = 0;
uniform vec4 restore_rects[16];
uniform sampler2D backing_ui : source_color, filter_linear;
uniform int backing_rect_count = 0;
uniform vec4 backing_rects[4];
uniform bool reject_cold_backing_pixels = false;
uniform int cold_filter_exempt_count = 0;
uniform vec4 cold_filter_exempt_rects[4];
// Hide only the former baked wordmark; native Unicode branding sits above it.
uniform vec4 localized_brand_exclusion = vec4(-1.0, -1.0, 0.0, 0.0);

float inside_rect(vec2 point, vec4 rect) {
	vec2 lower = step(rect.xy, point);
	vec2 upper = step(point, rect.xy + rect.zw);
	return lower.x * lower.y * upper.x * upper.y;
}

void fragment() {
	vec2 point = UV * source_size;
	float keep = 0.0;
	float restore = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= keep_rect_count) { break; }
		keep = max(keep, inside_rect(point, keep_rects[i]));
	}
	for (int i = 0; i < 16; i++) {
		if (i >= restore_rect_count) { break; }
		restore = max(restore, inside_rect(point, restore_rects[i]));
	}
	vec4 skin = texture(TEXTURE, UV);
	vec4 silhouette = skin;
	// The native overlay clears alpha over former captions but retains the
	// cleaned wood/paper RGB. Restore that authored skin, not baked captions.
	for (int i = 0; i < 4; i++) {
		if (i >= backing_rect_count) { break; }
		if (inside_rect(point, backing_rects[i]) > 0.5) {
			skin = texture(backing_ui, UV);
		}
	}
	// UI-only plates use zero RGB for the transparent space around their
	// artwork. Preserve those silhouettes while repairing internal alpha holes.
	float has_rgb = step(0.001, dot(silhouette.rgb, vec3(1.0)));
	float internal_hole = (1.0 - step(0.001, silhouette.a)) * restore * has_rgb;
	float alpha = keep * max(silhouette.a, internal_hole);
	// The opaque Save composite includes blue sky around curved native frames.
	// Retain warm paper/wood/leaf artwork, not rectangular patches of old sky.
	if (reject_cold_backing_pixels) {
		float exempt = 0.0;
		for (int i = 0; i < 4; i++) {
			if (i >= cold_filter_exempt_count) { break; }
			exempt = max(exempt, inside_rect(point, cold_filter_exempt_rects[i]));
		}
		// Neutral white lettering/petals are original UI artwork. Only blue
		// scenery is rejected; the authored green Confirm skin stays opaque.
		float warm_or_neutral = smoothstep(-0.10, -0.025, skin.r - skin.b);
		alpha *= mix(warm_or_neutral, 1.0, exempt);
	}
	alpha *= 1.0 - inside_rect(point, localized_brand_exclusion);
	COLOR = vec4(skin.rgb, alpha);
}

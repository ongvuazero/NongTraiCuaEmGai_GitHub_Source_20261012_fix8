shader_type canvas_item;
render_mode unshaded;
uniform bool hide_original=false;
varying vec4 vertex_modulate;
void vertex() { vertex_modulate=COLOR; }
void fragment() {
    // This material only switches the old art off for complete pose sprites.
    // It deliberately does not rotate, squeeze or distort any body pixels.
    vec4 original_color=texture(TEXTURE,UV);
    if(hide_original) original_color.a=0.0;
    COLOR=original_color*vertex_modulate;
}


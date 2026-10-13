shader_type spatial;
render_mode depth_prepass_alpha, cull_disabled;
uniform vec3 water_color : source_color = vec3(0.065, 0.105, 0.11);
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise21(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash21(i),hash21(i+vec2(1.0,0.0)),f.x), mix(hash21(i+vec2(0.0,1.0)),hash21(i+vec2(1.0,1.0)),f.x),f.y);
}
void fragment() {
 vec2 p=(UV-0.5)*2.0;
 float edge=length(p*vec2(0.9,1.1));
 float silhouette=noise21(UV*7.0)*0.22+noise21(UV*15.0)*0.055;
 float coverage=1.0-smoothstep(0.64+silhouette,0.89+silhouette,edge);
 if(coverage<0.08) { discard; }
 float ripple=sin(length(p-vec2(-0.25,0.16))*22.0-TIME*3.4)*0.006;
 vec2 swell=vec2(sin(p.x*3.8+TIME*0.4),cos(p.y*4.7-TIME*0.3))*0.025;
 ALBEDO=water_color+noise21(UV*11.0)*0.014;
 ROUGHNESS=0.15+noise21(UV*9.0)*0.06;
 METALLIC=0.35;
 NORMAL_MAP=vec3(0.5+swell.x+ripple,0.5+swell.y+ripple,1.0);
 NORMAL_MAP_DEPTH=0.4;
 ALPHA=coverage*0.85;
}
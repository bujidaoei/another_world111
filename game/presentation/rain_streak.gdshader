shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float weather_time = 0.0;
uniform float flight_height = 9.0;
uniform float minimum_speed = 14.0;
uniform float maximum_speed = 18.0;
uniform vec2 wind = vec2(0.4, 0.15);
uniform vec4 rain_color : source_color = vec4(0.45,0.6,0.64,0.3);
varying float opacity;
void vertex() {
 float speed=mix(minimum_speed,maximum_speed,INSTANCE_CUSTOM.y);
 float traveled=mod(weather_time*speed+INSTANCE_CUSTOM.x*flight_height,flight_height);
 vec3 center=MODEL_MATRIX[3].xyz+vec3(wind.x*traveled/flight_height,flight_height-traveled,wind.y*traveled/flight_height);
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(vec4(INV_VIEW_MATRIX[0].xyz,0.0),vec4(INV_VIEW_MATRIX[1].xyz,0.0),vec4(INV_VIEW_MATRIX[2].xyz,0.0),vec4(center,1.0));
 opacity=mix(0.4,1.0,INSTANCE_CUSTOM.w);
}
void fragment() {
 float width_mask=1.0-smoothstep(0.15,0.5,abs(UV.x-0.5));
 float length_mask=smoothstep(0.0,0.15,UV.y)*(1.0-smoothstep(0.7,1.0,UV.y));
 ALBEDO=rain_color.rgb;
 ALPHA=rain_color.a*opacity*width_mask*length_mask;
}
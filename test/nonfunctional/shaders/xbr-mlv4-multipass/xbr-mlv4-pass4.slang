#version 450

/*

   Hyllian's xBR MultiLevel4 Shader - Pass4
   
   Copyright (C) 2011-2015 Hyllian - sergiogdb@gmail.com

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
   THE SOFTWARE.

*/

layout(push_constant) uniform Push
{
	vec4 SourceSize;
	vec4 OriginalSize;
	vec4 OutputSize;
	uint FrameCount;
} params;

layout(std140, set = 0, binding = 0) uniform UBO
{
	mat4 MVP;
} global;

#define round(X) floor((X)+0.5)
#define mul(a,b) (b*a)
#define saturate(c) clamp(c, 0.0, 1.0)

const vec3 bin            = vec3(  4.0,   2.0,   1.0);
const vec4 low            = vec4(-64.0, -64.0, -64.0, -64.0);
const vec4 high           = vec4( 64.0,  64.0,  64.0,  64.0);

vec4 remapFrom01(vec4 v, vec4 low, vec4 high)
{
	return round(mix(low, high, v));
}

float c_df(vec3 c1, vec3 c2)
{
	vec3 df = abs(c1 - c2);
	return df.r + df.g + df.b;
}

vec4 unpack_info(float i)
{
	vec4 info;
	info.x = round(modf(i / 2.0, i));
	info.y = round(modf(i / 2.0, i));
	info.z = round(modf(i / 2.0, i));
	info.w = i;

	return info;
}

float df(float A, float B)
{
	return abs(A-B);
}

#define GET_PIXEL(PARAM, PIXEL)\
	info = PARAM;\
	ay.z = round(  modf( info / 2.0, info )  );\
	ay.y = round(  modf( info / 2.0, info )  );\
	ay.x = round(  modf( info / 2.0, info )  );\
	ax.z = round(  modf( info / 2.0, info )  );\
	ax.y = round(  modf( info / 2.0, info )  );\
	ax.x = round(  info  );\
	iq.x = dot( ax, bin ) - 2.0;\
	iq.y = dot( ay, bin ) - 2.0;\
	PIXEL = texture( Original, vTexCoord + iq.x * t1.xy + iq.y * t1.zw ).xyz;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;
layout(location = 1) out vec4 t1;
layout(location = 2) out float scale_factor;

void main()
{
   gl_Position = global.MVP * Position;
   vTexCoord = TexCoord * 1.0004;
	float dx	=	params.OriginalSize.z;
	float dy	=	params.OriginalSize.w;
   
	//      A3 B3 C3
	//      A1 B1 C1
	//A2 A0  A  B  C C4 C6
	//D2 D0  D  E  F F4 F6
	//G2 G0  G  H  I I4 I6
	//      G5 H5 I5
	//      G7 H7 I7
	t1	=	vec4(dx, 0., 0., dy);  // F  H
	scale_factor	=	params.OutputSize.x * params.OriginalSize.z;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 1) in vec4 t1;
layout(location = 2) in float scale_factor;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;
layout(set = 0, binding = 3) uniform sampler2D Original;

void main()
{
	vec2	fp	=	fract( vTexCoord * params.OriginalSize.xy ) - vec2( 0.4999, 0.4999 ); // pos = pixel position

	vec2	pxcoord	=	floor(vTexCoord * params.OriginalSize.xy) * params.OriginalSize.zw;

	vec4	UL	=	texture(Source, pxcoord + 0.25 * t1.xy + 0.25 * t1.zw );
	vec4	UR	=	texture(Source, pxcoord + 0.75 * t1.xy + 0.25 * t1.zw );
	vec4	DL	=	texture(Source, pxcoord + 0.25 * t1.xy + 0.75 * t1.zw );
	vec4	DR	=	texture(Source, pxcoord + 0.75 * t1.xy + 0.75 * t1.zw );

	vec4	ulparam	=	remapFrom01( UL, low, high ); // retrieve 1st pass info
	vec4	urparam	=	remapFrom01( UR, low, high ); // retrieve 1st pass info
	vec4	dlparam	=	remapFrom01( DL, low, high ); // retrieve 1st pass info
	vec4	drparam	=	remapFrom01( DR, low, high ); // retrieve 1st pass info
	
	vec3 E = texture( Original, vTexCoord ).xyz;

	vec3 ax, ay, PX, PY, PZ, PW;
	float info;
	vec2 iq;
	
	GET_PIXEL(ulparam.w, PX);
	GET_PIXEL(urparam.w, PY);
	GET_PIXEL(dlparam.w, PZ);
	GET_PIXEL(drparam.w, PW);
	
	vec3 fp1 = vec3( fp, -1. );

	vec3 color;
	vec4 fx;

	vec4 inc	=	vec4(abs(ulparam.x / ulparam.y), abs(urparam.x / urparam.y), abs(dlparam.x / dlparam.y), abs(drparam.x / drparam.y));
	vec4 level	=	max(inc, 1.0 / inc);
	
	fx.x	=	saturate( dot( fp1, ulparam.xyz ) * scale_factor / ( 8. * level.x ) + 0.5 );
	fx.y	=	saturate( dot( fp1, urparam.xyz ) * scale_factor / ( 8. * level.y ) + 0.5 );
	fx.z	=	saturate( dot( fp1, dlparam.xyz ) * scale_factor / ( 8. * level.z ) + 0.5 );
	fx.w	=	saturate( dot( fp1, drparam.xyz ) * scale_factor / ( 8. * level.w ) + 0.5 );
	
	vec3 c1, c2, c3, c4;

	c1	=	mix( E, PX, fx.x );
	c2	=	mix( E, PY, fx.y );
	c3	=	mix( E, PZ, fx.z );
	c4	=	mix( E, PW, fx.w );
	
	color = c1;
	color = ( (c_df(c2, E) > c_df(color, E)) ) ? c2 : color;
	color = ( (c_df(c3, E) > c_df(color, E)) ) ? c3 : color;
	color = ( (c_df(c4, E) > c_df(color, E)) ) ? c4 : color;
	
	FragColor = vec4(color, 1.0);
}
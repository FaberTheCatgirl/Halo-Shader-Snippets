/*
WATER_SHADING.FX
Copyright (c) Microsoft Corporation, Gungnir Softworks ULC, 2023. all rights reserved.
04/12/2006 13:36 davcook	
05/31/2023 01:46 rosehg
*/

#include "atmosphere.fx"
#include "texture_xform.fx"
#include "blend.fx"
#include "bump_mapping.fx"
#include "simple_lights.fx"
#include "utilities.fx"
#include "lightmap_sampling.fx"
#include "spherical_harmonics.fx"
#include "debug_modes.fx"

/* vertex shader implementation */
#ifdef VERTEX_SHADER

#if DX_VERSION == 9
#define CATEGORY_PARAM(_name) PARAM(int, _name)
#elif DX_VERSION == 11
#define CATEGORY_PARAM(_name) PARAM(float, _name)
#endif

// If the categories are not defined by the preprocessor, treat them as shader constants set by the game.
// We could automatically prepend this to the shader file when doing generate-templates, hmmm...
#ifndef category_global_shape
CATEGORY_PARAM(category_global_shape);
#endif

#ifndef category_waveshape
CATEGORY_PARAM(category_waveshape);
#endif

float4 barycentric_interpolate(float4 a, float4 b, float4 c, float3 weights)
{
	return a*weights.z + b*weights.y + c*weights.x;
}
float3 barycentric_interpolate(float3 a, float3 b, float3 c, float3 weights)
{
	return a*weights.z + b*weights.y + c*weights.x;
}
float2 barycentric_interpolate(float2 a, float2 b, float2 c, float3 weights)
{
	return a*weights.z + b*weights.y + c*weights.x;
}

// interpolate vertex porperties accroding tesselation information
s_water_render_vertex get_tessellated_vertex( s_vertex_type_water_shading IN )
{
	s_water_render_vertex OUT;

	// indices of vertices
#ifdef pc
	int index= 0;
#else
	int index= IN.index + k_water_index_offset.x;
#endif
	float4 v_index0, v_index1, v_index2;
#ifdef pc
   v_index0 = 0;
   v_index1 = 0;
   v_index2 = 0;
#else
	asm {
		vfetch v_index0, index, color0
		vfetch v_index1, index, color1
		vfetch v_index2, index, color2
	};
#endif
	//	fetch vertex porpertices
	float4 pos0, pos1, pos2;
	float4 tex0, tex1, tex2;
	float4 nml0, nml1, nml2;		
	float4 tan0, tan1, tan2;
	float4 bnl0, bnl1, bnl2;
	float4 btex0, btex1, btex2;
	float4 loc0, loc1, loc2;
	float4 lm_tex0, lm_tex1, lm_tex2;
	

	int v0_index_mesh= v_index0.x;
	int v0_index_water= v_index0.y;

	int v1_index_mesh= v_index1.x;
	int v1_index_water= v_index1.y;

	int v2_index_mesh= v_index2.x;
	int v2_index_water= v_index2.y;
#ifdef pc
	pos0 = float4(0,0,0,0);
	tex0 = float4(0,0,0,0);
	nml0 = float4(0,0,1,0);
	tan0 = float4(1,0,0,0);
	bnl0 = float4(0,1,0,0);
	lm_tex0 = float4(0,0,0,0);
	loc0 = float4(0,0,0,0);
	btex0 = float4(0,0,0,0);

	pos1 = float4(0,0,0,0);
	tex1 = float4(0,0,0,0);
	nml1 = float4(0,0,1,0);
	tan1 = float4(1,0,0,0);
	bnl1 = float4(0,1,0,0);
	lm_tex1 = float4(0,0,0,0);
	loc1 = float4(0,0,0,0);
	btex1 = float4(0,0,0,0);

	pos2 = float4(0,0,0,0);
	tex2 = float4(0,0,0,0);
	nml2 = float4(0,0,1,0);
	tan2 = float4(1,0,0,0);
	bnl2 = float4(0,1,0,0);
	lm_tex2 = float4(0,0,0,0);
	loc2 = float4(0,0,0,0);
	btex2 = float4(0,0,0,0);
#else
	asm {
		vfetch pos0, v0_index_mesh, position0
		vfetch tex0, v0_index_mesh, texcoord0
		vfetch nml0, v0_index_mesh, normal0			
		vfetch tan0, v0_index_mesh, tangent0
		vfetch bnl0, v0_index_mesh, binormal0
		vfetch lm_tex0, v0_index_mesh, texcoord1
		vfetch loc0, v0_index_water, position1			
		vfetch btex0, v0_index_water, position3					

		vfetch pos1, v1_index_mesh, position0
		vfetch tex1, v1_index_mesh, texcoord0	
		vfetch nml1, v1_index_mesh, normal0		
		vfetch tan1, v1_index_mesh, tangent0
		vfetch bnl1, v1_index_mesh, binormal0			
		vfetch lm_tex1, v1_index_mesh, texcoord1
		vfetch loc1, v1_index_water, position1
		vfetch btex1, v1_index_water, position3					

		vfetch pos2, v2_index_mesh, position0
		vfetch tex2, v2_index_mesh, texcoord0
		vfetch nml2, v2_index_mesh, normal0			
		vfetch tan2, v2_index_mesh, tangent0
		vfetch lm_tex2, v2_index_mesh, texcoord1
		vfetch bnl2, v2_index_mesh, binormal0			
		vfetch loc2, v2_index_water, position1
		vfetch btex2, v2_index_water, position3
	};
#endif
	// re-order the weights based on the QuadID
#ifdef pc
	float3 weights = float3(1, 0, 0);
#else
	float3 weights= IN.uvw * (0==IN.quad_id);
	weights+= IN.uvw.zxy * (1==IN.quad_id);
	weights+= IN.uvw.yzx * (2==IN.quad_id); 
	weights+= IN.uvw.xzy * (4==IN.quad_id); 
	weights+= IN.uvw.yxz * (5==IN.quad_id);
	weights+= IN.uvw.zyx * (6==IN.quad_id);
#endif

	// interpoate otuput		
	OUT.position= barycentric_interpolate(pos0, pos1, pos2, weights);
	OUT.texcoord= barycentric_interpolate(tex0, tex1, tex2, weights);		
	OUT.tangent= barycentric_interpolate(tan0, tan1, tan2, weights);
	OUT.binormal= -barycentric_interpolate(bnl0, bnl1, bnl2, weights);	// ###xwan inversion binormal to right hand			
	OUT.local_info= barycentric_interpolate(loc0, loc1, loc2, weights);	
	OUT.base_tex= barycentric_interpolate(btex0, btex1, btex2, weights);
	OUT.lm_tex= barycentric_interpolate(lm_tex0, lm_tex1, lm_tex2, weights);
	OUT.normal= normalize(OUT.normal);
	OUT.tangent= normalize(OUT.tangent);
	OUT.binormal= float4(cross(OUT.normal.xyz, OUT.tangent.xyz), 0);
	OUT.position.w= 1.0f;
	OUT.vmf_intensity= 1.0f;

	// ###xwan to save vfetch number, normal is generated by tangent and binormal
	OUT.normal.xyz= cross(OUT.tangent.xyz, OUT.binormal.xyz);
	OUT.normal= float4(normalize(OUT.normal.xyz), 0);

	return OUT;
}

// get vertex properties
#ifdef pc
s_water_render_vertex get_vertex( s_vertex_type_water_shading IN, const bool has_per_vertex_lighting )
{
	s_water_render_vertex OUT;
#ifndef PC_WATER_TESSELLATION
	
	OUT.position = float4(IN.position, 1);
	OUT.texcoord = float4(IN.texcoord, 0, 0);
	OUT.normal   = float4(IN.normal, 0);
	OUT.tangent  = float4(IN.tangent, 0);
	OUT.binormal =-float4(IN.binormal, 0); // ###xwan inversion binormal to right hand
	
	OUT.local_info = float4(IN.local_info, 0);
	OUT.base_tex = float4(IN.base_texcoord, 0);
	OUT.lm_tex = float4(IN.lm_tex, 0, 0);
#else

	float3 bc = IN.bc;
	
	// unpack data structures
	float3 position1 = float3(IN.pos1xyz_tc1x.x, IN.pos1xyz_tc1x.y, IN.pos1xyz_tc1x.z);
	float2 texcoord1 = float2(IN.pos1xyz_tc1x.w, IN.tc1y_tan1xyz.x);
	float3 tangent1  = float3(IN.tc1y_tan1xyz.y, IN.tc1y_tan1xyz.z, IN.tc1y_tan1xyz.w);
	float3 binormal1 = float3(IN.bin1xyz_lm1x.x, IN.bin1xyz_lm1x.y, IN.bin1xyz_lm1x.z);
	float2 lm1       = float2(IN.bin1xyz_lm1x.w, IN.lm1y_pos2xyz.x);
	float mi1        = IN.lm1y_mi1_pos2xy.y;
	
	float3 position2 = float3(IN.lm1y_pos2xyz.y, IN.lm1y_pos2xyz.z, IN.lm1y_pos2xyz.w);
	float2 texcoord2 = float2(IN.tc2xy_tan2xy.x, IN.tc2xy_tan2xy.y);
	float3 tangent2  = float3(IN.tc2xy_tan2xy.z, IN.tc2xy_tan2xy.w, IN.tan2z_bin2xyz.x);
	float3 binormal2 = float3(IN.tan2z_bin2xyz.y, IN.tan2z_bin2xyz.z, IN.tan2z_bin2xyz.w);
	float2 lm2       = float2(IN.lm2xy_pos3xy.x, IN.lm2xy_pos3xy.y);
	float mi2        = IN.bin2z_lm2xy_mi2.w;

	float3 position3 = float3(IN.lm2xy_pos3xy.z, IN.lm2xy_pos3xy.w, IN.pos3z_tc3xy_tan3x.x);
	float2 texcoord3 = float2(IN.pos3z_tc3xy_tan3x.y, IN.pos3z_tc3xy_tan3x.z);
	float3 tangent3  = float3(IN.pos3z_tc3xy_tan3x.w, IN.tan3yz_bin3xy.x, IN.tan3yz_bin3xy.y);
	float3 binormal3 = float3(IN.tan3yz_bin3xy.z, IN.tan3yz_bin3xy.w, IN.bin3z_lm3xy.x);
	float2 lm3       = float2(IN.bin3z_lm3xy.y, IN.bin3z_lm3xy.z);
	float mi3		 = IN.lm3y_mi3.y;

	// unpack append data
	float3 local_info1 = float3(IN.li1xyz_bt1x.x, IN.li1xyz_bt1x.y, IN.li1xyz_bt1x.z);
	float3 base_tex1   = float3(IN.li1xyz_bt1x.w, IN.bt1yz_li2xy.x, IN.bt1yz_li2xy.y);
	
	float3 local_info2 = float3(IN.bt1yz_li2xy.z, IN.bt1yz_li2xy.w, IN.li2z_bt2xyz.x);
	float3 base_tex2   = float3(IN.li2z_bt2xyz.y, IN.li2z_bt2xyz.z, IN.li2z_bt2xyz.w);

	float3 local_info3 = float3(IN.li3xyz_bt3x.x, IN.li3xyz_bt3x.y, IN.li3xyz_bt3x.z);
	float3 base_tex3   = float3(IN.li3xyz_bt3x.w, IN.bt3yz.x, IN.bt3yz.y);

	// interpolate
	OUT.position = float4(barycentric_interpolate(position1, position2, position3, bc), 1);
	OUT.texcoord = float4(barycentric_interpolate(texcoord1, texcoord2, texcoord3, bc), 0, 0);
	OUT.tangent  = float4(barycentric_interpolate(tangent1,  tangent2,  tangent3,  bc), 0);
	OUT.binormal =-float4(barycentric_interpolate(binormal1, binormal2, binormal3, bc), 0);
	OUT.lm_tex 	 = float4(barycentric_interpolate(lm1, lm2, lm3, bc), 0, 0);

	OUT.local_info  = float4(barycentric_interpolate(local_info1, local_info2, local_info3, bc), 0);
	OUT.base_tex    = float4(barycentric_interpolate(base_tex1, base_tex2, base_tex3, bc), 0);

	// calculate normal
	OUT.tangent = normalize(OUT.tangent);
	OUT.binormal= normalize(OUT.binormal);
	// ###xwan to save vfetch number, normal is generated by tangent and binormal
	OUT.normal.xyz= cross(OUT.tangent.xyz, OUT.binormal.xyz);
	OUT.normal= float4(normalize(OUT.normal.xyz), 0);

	if (has_per_vertex_lighting)
	{
	    float4 vmf_light0_1, vmf_light0_2, vmf_light0_3;
		float4 vmf_light1_1, vmf_light1_2, vmf_light1_3;

		int vertex_index_after_offset_1= int(mi1) - per_vertex_lighting_offset.x;
		int vertex_index_after_offset_2= int(mi2) - per_vertex_lighting_offset.x;
		int vertex_index_after_offset_3= int(mi3) - per_vertex_lighting_offset.x;

		fetch_stream(vertex_index_after_offset_1, vmf_light0_1, vmf_light1_1);
		fetch_stream(vertex_index_after_offset_2, vmf_light0_2, vmf_light1_2);
		fetch_stream(vertex_index_after_offset_3, vmf_light0_3, vmf_light1_3);

		float4 vmf0_1, vmf1_1, vmf2_1, vmf3_1;
		float4 vmf0_2, vmf1_2, vmf2_2, vmf3_2;
		float4 vmf0_3, vmf1_3, vmf2_3, vmf3_3;
		decompress_per_vertex_lighting_data(vmf_light0_1, vmf_light1_1, vmf0_1, vmf1_1, vmf2_1, vmf3_1);
		decompress_per_vertex_lighting_data(vmf_light0_2, vmf_light1_2, vmf0_2, vmf1_2, vmf2_2, vmf3_2);
		decompress_per_vertex_lighting_data(vmf_light0_3, vmf_light1_3, vmf0_3, vmf1_3, vmf2_3, vmf3_3);

		OUT.vmf_intensity= barycentric_interpolate(vmf1_1.rgb + vmf0_1.a, vmf1_2.rgb + vmf0_2.a, vmf1_3.rgb + vmf0_3.a, bc);
	}
	else
	{
		OUT.vmf_intensity= 0;
	}
#endif
	return OUT;
}
#else
s_water_render_vertex get_vertex( s_vertex_type_water_shading IN, const bool has_per_vertex_lighting)
{
	s_water_render_vertex OUT;

	// indices of vertices			
	float in_index= IN.uvw.x; // ###xwan after declaration of uvw and quad_id, Xenon has mistakely put index into uvw.x. :-(
	int t_index;
	[isolate]
	{
		t_index= floor((in_index+0.3f)/3);	//	triangle index		
	}

	int v_guid;
	[isolate]
	{
		float temp= in_index - t_index*3 + 0.1f;
		v_guid= (int) temp;
	}

	float4 v_index0, v_index1, v_index2;
#ifdef pc

#else
	asm {
		vfetch v_index0, t_index, color0
		vfetch v_index1, t_index, color1
		vfetch v_index2, t_index, color2
	};
#endif
	float4 v_index= v_index0 * (0==v_guid);
	v_index+= v_index1 * (1==v_guid);
	v_index+= v_index2 * (2==v_guid);	
	

	//	fetch vertex porpertices
	float4 pos, tex, nml, tan, bnl, btex, loc, lm_tex;
	int v_index_mesh= v_index.x;
	int v_index_water= v_index.y;
#ifdef pc
	pos = float4(0,0,0,0);
	tex = float4(0,0,0,0);
	nml = float4(0,0,0,0);
	tan = float4(0,0,0,0);
	bnl = float4(0,0,0,0);
	lm_tex = float4(0,0,0,0);
	loc = float4(0,0,0,0);
	btex = float4(0,0,0,0);
#else
	asm {
		vfetch pos, v_index_mesh, position0
		vfetch tex, v_index_mesh, texcoord0
		vfetch nml, v_index_mesh, normal0
		vfetch tan, v_index_mesh, tangent0
		vfetch bnl, v_index_mesh, binormal0
		vfetch lm_tex, v_index_mesh, texcoord1		
		vfetch loc, v_index_water, position1
		vfetch btex, v_index_water, position3
		
	};

	if (has_per_vertex_lighting)
	{
	    float4 vmf_light0;
		float4 vmf_light1;

		int vertex_index_after_offset= v_index_mesh - per_vertex_lighting_offset.x;
		fetch_stream(vertex_index_after_offset, vmf_light0, vmf_light1);

		float4 vmf0, vmf1, vmf2, vmf3;
		decompress_per_vertex_lighting_data(vmf_light0, vmf_light1, vmf0, vmf1, vmf2, vmf3);

		OUT.vmf_intensity= vmf1.rgb + vmf0.a;
	}
	else
	{
		OUT.vmf_intensity= 0;
	}	
#endif
	// interpoate otuput		
	OUT.position= pos;
	OUT.texcoord= tex;
	OUT.normal= nml;
	OUT.tangent= tan;
	OUT.binormal= float4(cross(OUT.normal, OUT.tangent), 0);
	//OUT.binormal= -bnl;	// ###xwan inversion binormal to right hand
	
	OUT.local_info= loc;		
	OUT.base_tex= btex;
	OUT.lm_tex= lm_tex;
	OUT.position.w= 1.0f;
	return OUT;
}
#endif // pc

float3 restore_displacement(
			float3 displacement,
			float3 range,
			float3 min,
			float height)
{
	displacement*= range;
	displacement+= min;	
	displacement*= height;

	return displacement;
}

float3 apply_choppiness(
			float3 displacement,			
			float chop_forward,
			float chop_backward,
			float chop_side)
{	
	displacement.y*= chop_side;	//	backward choppiness
	displacement.x*= (displacement.x<0) ? chop_forward : chop_backward; //forward scale, y backword scale		
	return displacement;
}
			
float2 calculate_ripple_coordinate_by_world_position(
			float2 position)
{
	float2 texcoord_ripple= (position - Camera_Position.xy) / k_ripple_buffer_radius;
	float len= length(texcoord_ripple);
	texcoord_ripple*= rsqrt(len);

	texcoord_ripple+= k_view_dependent_buffer_center_shifting;
	texcoord_ripple= texcoord_ripple*0.5f + 0.5f;
	texcoord_ripple= saturate(texcoord_ripple);
	return texcoord_ripple;
}

// transform vertex position, normal etc accroding to wave 
s_water_interpolators transform_vertex( s_water_render_vertex IN, const bool has_per_vertex_lighting)
{
	//	vertex to eye displacement
	float4 incident_ws;
	incident_ws.xyz= Camera_Position - IN.position.xyz;		
	incident_ws.w= length(incident_ws.xyz);
	incident_ws.xyz= normalize(incident_ws.xyz);
	float mipmap_level= max(incident_ws.w / wave_visual_damping_distance, 1.0f); 		

	// apply global shape control
	float height_scale_global= 1.0f;
	float choppy_scale_global= 1.0f;
	if ( TEST_CATEGORY_OPTION(global_shape, paint) )
	{
		float4 shape_control= sample2Dlod(global_shape_texture, transform_texcoord(IN.base_tex.xy, global_shape_texture_xform), mipmap_level);
		height_scale_global= shape_control.x;
		choppy_scale_global= shape_control.y;
	}
	else if ( TEST_CATEGORY_OPTION(global_shape, depth) )
	{
		float height_scale_for_shallow_water= saturate(IN.local_info.y / globalshape_infuence_depth);
		height_scale_global= height_scale_for_shallow_water;
	}

	// get ripple texcoord
	float2 texcoord_ripple= 0.0f;	
	if (k_is_water_interaction)
	{			
		texcoord_ripple= (IN.position.xy - Camera_Position.xy) / k_ripple_buffer_radius;		
		float len= length(texcoord_ripple);		
		texcoord_ripple*= rsqrt(len);		

		texcoord_ripple+= k_ripple_buffer_center;
		texcoord_ripple= texcoord_ripple*0.5f + 0.5f;
		texcoord_ripple= saturate(texcoord_ripple);
	}

	// calculate displacement of vertex
	float4 position= IN.position;
	float water_height_relative= 0.0f;
	float max_height_relative= 1.0f;

	if (k_is_water_tessellated)
	{	
		float3 displacement= 0.0f;
		if ( TEST_CATEGORY_OPTION(waveshape, default) )
		{
			//	re-assemble constants	
			float3 displacement_range= float3(displacement_range_x, displacement_range_y, displacement_range_z);
			float3 displacement_min= -displacement_range/2;		
			
			float4 texcoord= float4(transform_texcoord(IN.texcoord.xy, wave_displacement_array_xform),  time_warp, mipmap_level);		
			float4 texcoord_aux= float4(transform_texcoord(IN.texcoord.xy, wave_slope_array_xform),  time_warp_aux, mipmap_level);

         #ifndef pc
			   // dirty hack to work around the texture fetch bug of screenshot on Xenon			
			   if ( k_is_under_screenshot ) 
			   {
				   texcoord.w= 0.0f;
				   texcoord_aux.w= 0.0f;
			   }
			#endif


#if DX_VERSION == 9			
			displacement= sample3Dlod(wave_displacement_array, texcoord.xyz, texcoord.w).xyz;			
			float3 displacement_aux= sample3Dlod(wave_displacement_array, texcoord_aux.xyz, texcoord_aux.w).xyz;		
#elif DX_VERSION == 11
			float4 array_texcoord = convert_3d_texture_coord_to_array_texture(wave_displacement_array, texcoord.xyz);
			float4 array_texcoord_aux = convert_3d_texture_coord_to_array_texture(wave_displacement_array, texcoord_aux.xyz);
			float array_texcoord_t = frac(array_texcoord.z);
			float array_texcoord_aux_t = frac(array_texcoord_aux.z);
			array_texcoord.zw = floor(array_texcoord.zw);
			array_texcoord_aux.zw = floor(array_texcoord_aux.zw);			
			
			displacement = lerp(
				wave_displacement_array.t.SampleLevel(wave_displacement_array.s, array_texcoord.xyz, texcoord.w),
				wave_displacement_array.t.SampleLevel(wave_displacement_array.s, array_texcoord.xyw, texcoord.w),
				frac(array_texcoord_t));
			float3 displacement_aux = lerp(
				wave_displacement_array.t.SampleLevel(wave_displacement_array.s, array_texcoord_aux.xyz, texcoord_aux.w),
				wave_displacement_array.t.SampleLevel(wave_displacement_array.s, array_texcoord_aux.xyw, texcoord_aux.w),
				frac(array_texcoord_aux_t));
#endif
			//float3 displacement_aux= 0.0f;
			

			// restore displacement
			displacement= restore_displacement(
								displacement,
								displacement_range,
								displacement_min,
								wave_height);	

			displacement_aux= restore_displacement(
								displacement_aux,
								displacement_range,
								displacement_min,
								wave_height_aux);		

			float wave_scale= sqrt( wave_displacement_array_xform.x * wave_displacement_array_xform.y);
			//float wave_scale_aux= sqrt( wave_slope_array_xform.x * wave_slope_array_xform.y);
			float wave_scale_aux= wave_scale;	

			// scale and accumulate waves	
			displacement/= wave_scale;
			displacement_aux/= wave_scale_aux;
			displacement= displacement + displacement_aux;	

			displacement= apply_choppiness(
								displacement,						
								choppiness_forward * choppy_scale_global,
								choppiness_backward * choppy_scale_global, 
								choppiness_side * choppy_scale_global);

			// convert procedure wave displacement from texture space to geometry space
			displacement*= IN.local_info.x;	
			max_height_relative= 0.5f * IN.local_info.x * displacement_range_z*(wave_height + wave_height_aux) / wave_scale;

			// apply global height control
			displacement.z*= height_scale_global;		
		}
		// else 
		//	DO NOTHING

		// preserve the height
		water_height_relative= displacement.z;		

		// interaction + get ripple texcoord + consider interaction	after displacement
		if (k_is_water_interaction)
		{
			texcoord_ripple= (IN.position.xy - Camera_Position.xy) / k_ripple_buffer_radius;
			float len= length(texcoord_ripple);
			texcoord_ripple*= rsqrt(len);

			texcoord_ripple+= k_view_dependent_buffer_center_shifting;
			texcoord_ripple= texcoord_ripple*0.5f + 0.5f;
			texcoord_ripple= saturate(texcoord_ripple);
			texcoord_ripple= calculate_ripple_coordinate_by_world_position(position.xy);
			float4 ripple_hei= sample2Dlod(vs_tex_ripple_buffer_slope_height, texcoord_ripple.xy, 0);		

			float ripple_height= ripple_hei.r*2.0f - 1.0f;
			float ripple_weak= 1.0f /(1.0f + 3.0f * abs(ripple_height));
			ripple_height*= 0.2f;	//	maximune disturbance of water is 5 inchs

			// low down ripple for shallow water
			ripple_height*= height_scale_global;
			position+= IN.normal * ripple_height;

			// low down ripple for shallow water
			//ripple_height*= min( IN.local_info.y * 10 + 0.1f, 1.0f);
			//float sign= (ripple_height > 0)? 1: -1;
			//ripple_height= sign * min(abs(ripple_height), IN.local_info.y * 0.5f + 0.01f);			
			
			//displacement.z= displacement.z*ripple_weak - abs(displacement.z*ripple_height) + ripple_height;	//	maximune disturbance of water is 5 inchs;
			displacement.z= displacement.z*ripple_weak + ripple_height;	//	maximune disturbance of water is 5 inchs;
			displacement.xy*= ripple_weak;
			//displacement.z= ripple_height;
			//displacement.xy*= 1.0f + (ripple_hei.g - ripple_hei.b);
		}
		// apply vertex displacement
		position+= 
			IN.tangent *displacement.x +
			IN.binormal *displacement.y + 
			IN.normal *displacement.z;					
		position.w= 1.0f;		
	}

	//	computer atmosphere fog
	float3 fog_extinction;
	float3 fog_inscatter;
	compute_scattering(Camera_Position, position.xyz, fog_extinction, fog_inscatter);
	

	s_water_interpolators OUT;
	//OUT.position= mul( position, k_vs_water_view_xform );	//View_Projection
	OUT.position= mul( position, View_Projection );	
	OUT.texcoord= float4(IN.texcoord.xyz, mipmap_level);
#ifndef pc // todo: not enough output registers on PC [01/28/2013 paul.smirnov]
	OUT.normal= IN.normal;
#endif // pc
	OUT.tangent= IN.tangent;
	OUT.binormal= IN.binormal;		//	hack hack from LH to RH
	OUT.position_ss= OUT.position * float4(0.5f, -0.5f, 1.0f, 1.0f) + float4(0.5f, 0.5f, 0.0f, 0.0f) * OUT.position.w;

	OUT.incident_ws= incident_ws;
	OUT.position_ws= float4(position.xyz, 1.0f/max(incident_ws.w, 0.01f)); // one_over_camera_distance
	//OUT.position_ws= position;

	float4 misc_info= 
		float4(
			(TEST_CATEGORY_OPTION(waveshape, default)) ? sqrt(height_scale_global * wave_height) : 0, 
			(TEST_CATEGORY_OPTION(waveshape, default)) ? sqrt(height_scale_global * wave_height_aux) : 0,
			0.0f,	
			IN.local_info.y);	// height_scale, height_scale_aux, water_height, water_depth
#ifndef pc // todo: not enough output registers on PC [01/28/2013 paul.smirnov]
	OUT.misc_info= misc_info;
#else
	OUT.tangent.w = misc_info.x;
	OUT.binormal.w = misc_info.y;
	OUT.position_ws.w = misc_info.w;
#endif

	OUT.lm_tex= float4(IN.lm_tex.xy, texcoord_ripple);
	OUT.fog_extinction= float4(fog_extinction, 0.0f);
	OUT.fog_inscatter= float4(fog_inscatter, 0.0f);
	OUT.base_tex= 
		float4(IN.base_tex.xy, water_height_relative*10, max_height_relative*10);
	
	if (has_per_vertex_lighting)
	{
		OUT.lm_tex= float4(IN.vmf_intensity, 0.0f);
	}
	else
	{
		OUT.lm_tex= float4(IN.lm_tex.xy, 0, 0);
	}

	return OUT;
}

#endif //VERTEX_SHADER



/* pixel shader implementation */
#ifdef PIXEL_SHADER

float2 restore_slope(
			float2 slope,
			float2 range, // same as displacement ?
			float2 min)
{
	slope*= range;
	slope+= min;
	
	return slope;
}
// This Code didn't port easily. who the hell originally worked on this crap? [05/31/2023 rose.h]
float2 compute_detail_slope(
			float2 base_texcoord,
			float4 base_texture_xform,
			float time_warp,
			float mipmap_level)
{
	float2 slope_detail= 0.0f;
	if ( TEST_CATEGORY_OPTION(detail, repeat) )
	{
		float4 wave_detail_xform= base_texture_xform * float4(detail_slope_scale_x, detail_slope_scale_y, 1, 1);
		float4 texcoord_detail= float4(transform_texcoord(base_texcoord, wave_detail_xform),  time_warp*detail_slope_scale_z, mipmap_level);
#ifdef xenon
		asm
		{
			tfetch3D slope_detail.xy, texcoord_detail.xyz, wave_slope_array, MagFilter= linear, MinFilter= linear, MipFilter= linear, VolMagFilter= linear, VolMinFilter= linear
		};
#elif DX_VERSION == 11
		float4 array_texcoord = convert_3d_texture_coord_to_array_texture(wave_slope_array, texcoord_detail.xyz);
		float array_texcoord_t = frac(array_texcoord.z);
		array_texcoord.zw = floor(array_texcoord.zw);
		slope_detail.xy = lerp(
			wave_slope_array.t.Sample(wave_slope_array.s, array_texcoord.xyz),
			wave_slope_array.t.Sample(wave_slope_array.s, array_texcoord.xyw),
			frac(array_texcoord_t));
#endif
		slope_detail.xy *= detail_slope_steepness;
	}

	return slope_detail;
}

void compose_slope(float4 texcoord_in, float height_scale, float height_aux_scale, float height_detail_scale, out float2 slope_shading, out float2 slope_refraction, out float wave_choppiness_ratio)
{	
	//This is a hack to get around the fact that the compiler doesn't like to have a texture fetch in a loop [05/31/2023 rose.h]
	float2 slope_range= float2(slope_range_x, slope_range_y);
	float2 slope_min= -slope_range/2;

	float4 wave_detail_xform= wave_displacement_array_xform * float4(detail_slope_scale_x, detail_slope_scale_y, 1, 1);

	//time_warp= 0;
	//time_warp_aux= 0;

	float mipmap_level= texcoord_in.w;	
	float4 texcoord= float4(transform_texcoord(texcoord_in.xy, wave_displacement_array_xform),  time_warp, mipmap_level);
	float4 texcoord_aux= float4(transform_texcoord(texcoord_in.xy, wave_slope_array_xform),  time_warp_aux, mipmap_level);
	float4 texcoord_detail= float4(transform_texcoord(texcoord_in.xy, wave_detail_xform),  time_warp*detail_slope_scale_z, mipmap_level+1);	

	

	float2 slope;
	float2 slope_aux;
	float2 slope_detail;		
	//slope= tex3D(wave_slope_array, texcoord.xyz).xy;
	//slope_aux= tex3D(wave_slope_array, texcoord_aux.xyz).xy;
	//slope_detail= tex3D(wave_slope_array, texcoord_detail.xyz).xy;	
#if (DX_VERSION == 9) && defined(pc)
	TFETCH_3D(slope.xy, texcoord.xyz, wave_slope_array, 0, 1);
	slope.xy = BUMP_CONVERT(slope.xy);
	TFETCH_3D(slope_aux.xy, texcoord_aux.xyz, wave_slope_array, 0, 1);
	slope_aux.xy = BUMP_CONVERT(slope_aux.xy);
	TFETCH_3D(slope_detail.xy, texcoord_detail.xyz, wave_slope_array, 0, 1);
	slope_detail.xy = BUMP_CONVERT(slope_detail.xy);
#elif DX_VERSION == 11
	float4 array_texcoord = convert_3d_texture_coord_to_array_texture(wave_slope_array, texcoord.xyz);
	float4 array_texcoord_aux = convert_3d_texture_coord_to_array_texture(wave_slope_array, texcoord_aux.xyz);
	float4 array_texcoord_detail = convert_3d_texture_coord_to_array_texture(wave_slope_array, texcoord_detail.xyz);
	float array_texcoord_t = frac(array_texcoord.z);
	float array_texcoord_aux_t = frac(array_texcoord_aux.z);
	float array_texcoord_detail_t = frac(array_texcoord_detail.z);
	array_texcoord.zw = floor(array_texcoord.zw);
	array_texcoord_aux.zw = floor(array_texcoord_aux.zw);
	array_texcoord_detail.zw = floor(array_texcoord_detail.zw);
	
	slope.xy = lerp(
		wave_slope_array.t.Sample(wave_slope_array.s, array_texcoord.xyz),
		wave_slope_array.t.Sample(wave_slope_array.s, array_texcoord.xyw),
		frac(array_texcoord_t));
	slope_aux.xy = lerp(
		wave_slope_array.t.Sample(wave_slope_array.s, array_texcoord_aux.xyz),
		wave_slope_array.t.Sample(wave_slope_array.s, array_texcoord_aux.xyw),
		frac(array_texcoord_aux_t));
	slope_detail.xy = lerp(
		wave_slope_array.t.Sample(wave_slope_array.s, array_texcoord_detail.xyz),
		wave_slope_array.t.Sample(wave_slope_array.s, array_texcoord_detail.xyw),
		frac(array_texcoord_detail_t));
#else
	asm{
		tfetch3D slope.xy, texcoord.xyz, wave_slope_array, MagFilter= linear, MinFilter= linear, MipFilter= linear, VolMagFilter= linear, VolMinFilter= linear
		tfetch3D slope_aux.xy, texcoord_aux.xyz, wave_slope_array, MagFilter= linear, MinFilter= linear, MipFilter= linear, VolMagFilter= linear, VolMinFilter= linear
		tfetch3D slope_detail.xy, texcoord_detail.xyz, wave_slope_array, MagFilter= linear, MinFilter= linear, MipFilter= linear, VolMagFilter= linear, VolMinFilter= linear
	};
#endif
	slope= restore_slope(slope, slope_range, slope_min);	
	slope_aux= restore_slope(slope_aux, slope_range, slope_min);	
	slope_detail= restore_slope(slope_detail, slope_range, slope_min);		
	wave_choppiness_ratio= 1.0f - abs(slope.x) - abs(slope.y);

	float2 slope_detail= compute_detail_slope(texcoord_in.xy, wave_displacement_array_xform, time_warp, mipmap_level+1);

	//	apply scale		
	slope_aux= 
		slope_aux*height_aux_scale + 
		slope_detail*height_detail_scale;		

	slope_shading= 	slope*height_scale + slope_aux + slope_detail;		
	slope_refraction= slope*max(height_scale, minimal_wave_disturbance) + slope_aux;	
}

// fresnel approximation
float compute_fresnel(
			float3 incident,
			float3 normal,
			float r0,
			float r1)
{
 	float eye_dot_normal= saturate(dot(incident, normal));
	eye_dot_normal=			saturate(r1 - eye_dot_normal);
	return saturate(r0 * eye_dot_normal * eye_dot_normal);			//pow(eye_dot_normal, 2.5)
	//return r0 + (1.0 - r0) * pow(1.0 - eye_dot_normal, 2.5);
}

float compute_fog_transparency(
			float murkiness,
			float negative_depth)
{
	return saturate(exp2(murkiness * negative_depth));
}

float compute_fog_factor( 
			float murkiness,
			float depth)
{
	return 1.0f - compute_fog_transparency(murkiness, -depth);
}

float3 decode_bpp16_luvw(
	in float4 val0,
	in float4 val1,
	in float l_range)
{	
	float L = val0.a * val1.a * l_range;
	float3 uvw = val0.xyz + val1.xyz;
	return (uvw * 2.0f - 2.0f) * L;	
}

float sample_depth(float2 texcoord)
{
#if defined(pc) || (DX_VERSION == 11)
	return depth_buffer.Sample(scene_ldr_texture.s, texcoord).r;
#else // xenon hack
	float4 result;
	asm
	{
		tfetch2D result, texcoord, depth_buffer, MagFilter= point, MinFilter= point, MipFilter= point, AnisoFilter= disabled, OffsetX= 0.5, OffsetY= 0.5
	};
	return result.r;
#endif // xenon hack
}

//#define USE_LOD_SAMPLER false;

// shade water surface
accum_pixel water_shading(s_water_interpolators INTERPOLATORS, uniform const bool has_per_vertex_lighting, uniform const bool alpha_blend_output)			// actually uses multiply-add blend mode if true)
{			
	float3 output_color= 0;	

	// interaction
	float2 ripple_slope= 0.0f;		
	float ripple_foam_factor= 0.0f;

	[branch]
	if (k_is_water_interaction)
	{			
		float2 texcoord_ripple= INTERPOLATORS.lm_tex.zw;		
		float4 ripple;
		#ifdef pc
         ripple = sample2Dlod(tex_ripple_buffer_slope_height, texcoord_ripple.xy, 0);		
		#else
			asm {tfetch2D ripple, texcoord_ripple, tex_ripple_buffer_slope_height, MagFilter= linear, MinFilter= linear};
		#endif

		ripple_slope= (ripple.gb - 0.5f) * 6.0f;	// hack		
		ripple_foam_factor= ripple.a;
	}	

	//float ripple_slope_length= length(float3(1.5f * ripple_slope, 1.0f)); // hack ripple appearance 
	//float ripple_slope_weak= 1.0f / ripple_slope_length;

	float ripple_slope_length= dot(abs(ripple_slope.xy), 2.0f) + 1.0f;
	ripple_slope_length= max(ripple_slope_length, 0.3f);
	ripple_slope_length= min(ripple_slope_length, 2.1f);

	float ripple_slope_weak= 1.0f / ripple_slope_length;


	float2 slope_shading= 0.0f;
	float wave_choppiness_ratio= 0.0f;
	float2 slope_refraction= 0.0f;	
	if (TEST_CATEGORY_OPTION(waveshape, default))
	{
		compose_slope(
			INTERPOLATORS.texcoord,
			1.0f,
			1.0f,
#ifndef pc // todo: not enough output registers on PC [01/28/2013 paul.smirnov]
			INTERPOLATORS.misc_info.x * ripple_slope_weak,
			INTERPOLATORS.misc_info.y * ripple_slope_weak,
#else
			INTERPOLATORS.tangent.w * ripple_slope_weak,
			INTERPOLATORS.binormal.w * ripple_slope_weak,
#endif // pc
			detail_slope_steepness * ripple_slope_weak,
			slope_shading,
			slope_refraction,
			wave_choppiness_ratio);			
	}
	else if (TEST_CATEGORY_OPTION(waveshape, bump) )
	{
		// grap code from calc_bumpmap_detail_ps in bump_mapping.fx
		float3 bump= sample_bumpmap(bump_map, transform_texcoord(INTERPOLATORS.texcoord, bump_map_xform));					// in tangent space
		float3 detail= sample_bumpmap(bump_detail_map, transform_texcoord(INTERPOLATORS.texcoord, bump_detail_map_xform));	// in tangent space	
		bump.xy+= detail.xy;

		// convert bump into slope		
		slope_shading= bump.xy/max(bump.z, 0.01f);
		slope_refraction= slope_shading;
	}

	//	adjust normal
	float normal_hack_ratio= max(INTERPOLATORS.texcoord.w, 1.0f);
	slope_shading= slope_shading/normal_hack_ratio;		

		slope_shading= slope_shading * slope_scaler + ripple_slope;

	float3x3 tangent_frame_matrix= { INTERPOLATORS.tangent.xyz, INTERPOLATORS.binormal.xyz, INTERPOLATORS.normal.xyz };
	float3 normal= mul(float3(slope_shading, 1.0f), tangent_frame_matrix);
	normal= normalize(normal);
	slope_refraction= slope_refraction + ripple_slope;

#ifdef pc // todo: not enough output registers on PC [01/28/2013 paul.smirnov]
	float3 INTERPOLATORS_normal = -normalize(cross(INTERPOLATORS.binormal.xyz, INTERPOLATORS.tangent.xyz));
	float3x3 tangent_frame_matrix= { INTERPOLATORS.tangent.xyz, INTERPOLATORS.binormal.xyz, INTERPOLATORS_normal.xyz };
#else
	float3x3 tangent_frame_matrix= { INTERPOLATORS.tangent.xyz, INTERPOLATORS.binormal.xyz, INTERPOLATORS.normal.xyz };
#endif
	float3 normal= mul(normalize(float3(slope_shading, 1.0f)), tangent_frame_matrix);	
	normal= normalize(normal);

	// apply lightmap shadow
	float3 lightmap_intensity= 1.0f;

#if (!defined(pc)) || (DX_VERSION == 11)
	if (has_per_vertex_lighting)
	{
		lightmap_intensity= INTERPOLATORS.lm_tex.rgb;
	}
	else
	{
		[branch]
		if (k_is_lightmap_exist)
		{
			const float2 lightmap_texcoord= INTERPOLATORS.lm_tex.xy;

			float4 vmf_coefficients[4];
			sample_lightprobe_texture(lightmap_texcoord, vmf_coefficients);

			// ###xwan it's a hack way, however, tons of content has been set by current water shaders. dangerous to change it	(###ctchou $NOTE:  I'll say)
			lightmap_intensity=
				vmf_coefficients[1].rgb +		// Colors[0]*p_lightmap_compress_constant_0.x*fIntensity
				vmf_coefficients[0].a;			// sun visibility_mask
		}
		//float3 sh_coefficients_0;
#ifdef DEBUG_UNCOMPRESSED_LIGHTMAPS
		if ( p_lightmap_compress_constant_using_dxt )
#endif //DEBUG_UNCOMPRESSED_LIGHTMAPS
		{
			float4 sh_dxt_vector_0;
			float4 sh_dxt_vector_1;
			float3 lightmap_texcoord_bottom= float3(INTERPOLATORS.lm_tex.xy, 0.0f);
#ifdef pc
			TFETCH_3D(sh_dxt_vector_0, lightmap_texcoord_bottom, lightprobe_texture_array, 0.5, 8);
			TFETCH_3D(sh_dxt_vector_1, lightmap_texcoord_bottom, lightprobe_texture_array, 1.5, 8);
#else
			asm{ tfetch3D sh_dxt_vector_0, lightmap_texcoord_bottom, lightprobe_texture_array, OffsetZ= 0.5 };
			asm{ tfetch3D sh_dxt_vector_1, lightmap_texcoord_bottom, lightprobe_texture_array, OffsetZ= 1.5 };
#endif
			sh_coefficients_0= decode_bpp16_luvw(sh_dxt_vector_0, sh_dxt_vector_1, p_lightmap_compress_constant_0.x);					
		}
#ifdef DEBUG_UNCOMPRESSED_LIGHTMAPS
		else
		{
			sh_coefficients_0= tex3D(lightprobe_texture_array, float3(INTERPOLATORS.lm_tex.xy, 0.1f));	//0.5/5
		}		
#endif //DEBUG_UNCOMPRESSED_LIGHTMAPS
		lightmap_intensity= saturate(sh_coefficients_0);		
	}

	// calcuate texcoord in screen space
	INTERPOLATORS.position_ss/= INTERPOLATORS.position_ss.w;
	float2 texcoord_ss= INTERPOLATORS.position_ss.xy;
	texcoord_ss= texcoord_ss / 2 + 0.5;
	texcoord_ss.y= 1 - texcoord_ss.y;
	texcoord_ss= k_water_player_view_constant.xy + texcoord_ss*k_water_player_view_constant.zw;
			
	float4 water_color_from_texture= sample2D(watercolor_texture, transform_texcoord(INTERPOLATORS.base_tex.xy, watercolor_texture_xform)); // adding interpolation to the texture coordinates [05/31/2023 rose.h]
	water_color_from_texture.xyz*= watercolor_coefficient; //todo: finish code from here [05/31/2023 rose.h]	

	float3 water_color;
	if (TEST_CATEGORY_OPTION(watercolor, pure))
	{
		water_color= water_color_pure;		
	}
	else if  (TEST_CATEGORY_OPTION(watercolor, texture))
	{
		water_color= water_color_from_texture.rgb * watercolor_coefficient;	
	}
	water_color*= lightmap_intensity;
	
	float3 color_refraction;
	float3 color_refraction_bed;
	float color_refraction_bed_contribution= 0.0f;		// track the contribution ratio to avoid double fog effect

	float depth_refraction= 0.0f;
	float depth_water= 0.0f;
	if (TEST_CATEGORY_OPTION(refraction, none))
	{
		color_refraction= water_color;
		color_refraction_bed= water_color;
	}
	else if (TEST_CATEGORY_OPTION(refraction, dynamic))
	{
		//	calculate water depth
#if DX_VERSION == 11
		float depth_width, depth_height;
		depth_buffer.GetDimensions(depth_width, depth_height);
		depth_water = depth_buffer.Load(int3((texcoord_ss * float2(depth_width, depth_height)), 0)).r;
#else	
		depth_water= sample2D(depth_buffer, texcoord_ss).r;
#endif
#if (DX_VERSION == 9) && defined(pc)
		depth_water = k_water_view_depth_constant.x / depth_water + k_water_view_depth_constant.y; // Zbuf = -FN/(F-N) / z + F/(F-N)
#endif // pc
		//float4 point_underwater= float4(INTERPOLATORS.position_ss.xy, 1.0f - depth_water, 1.0f);		
		float4 point_underwater= float4(INTERPOLATORS.position_ss.xy, depth_water, 1.0f);		
		point_underwater= mul(point_underwater, k_water_view_xform_inverse);
		point_underwater.xyz/= point_underwater.w;
		depth_water= length(point_underwater.xyz - INTERPOLATORS.position_ws.xyz);	
		
		float2 bump= slope_refraction.xy * INTERPOLATORS.incident_ws.yx * refraction_texcoord_shift  * saturate(3 * depth_water);
		bump*= min(max(2 / INTERPOLATORS.incident_ws.w, 0.0f), 1.0f);
		bump*= k_water_player_view_constant.zw;
		bump*= ripple_slope_length;

		float2 texcoord_refraction= texcoord_ss + bump;

		float2 delta= 0.001f;	//###xwan avoid fetch back pixel, it could be considered into k_water_player_view_constant
		texcoord_refraction= clamp(texcoord_refraction, k_water_player_view_constant.xy+delta, k_water_player_view_constant.xy+k_water_player_view_constant.zw-delta);

#if DX_VERSION == 11
		depth_refraction = depth_buffer.Load(int3((texcoord_refraction * float2(depth_width, depth_height)), 0)).r;
#else		
		depth_refraction= sample2D(depth_buffer, texcoord_refraction).r;	
#endif
#if (DX_VERSION == 9) && defined(pc)
		depth_refraction = k_water_view_depth_constant.x / depth_refraction + k_water_view_depth_constant.y; // Zbuf = -FN/(F-N) / z + F/(F-N)
#endif // pc

		//	###xwan this comparision need to some tolerance to avoid dirty boundary of refraction	
		texcoord_refraction= lerp(
			texcoord_ss, 
			texcoord_refraction, 
			(depth_refraction<INTERPOLATORS.position_ss.z));

		
		color_refraction= sample2D(scene_ldr_texture, texcoord_refraction);		

		// remove scatter
		//color_refraction= (color_refraction - INTERPOLATORS.fog_inscatter) / INTERPOLATORS.fog_extinction;
		
		color_refraction_bed= color_refraction;	//	pure color of under water stuff

		//	check real refraction
#if DX_VERSION == 11
		depth_refraction = depth_buffer.Load(int3((texcoord_refraction * float2(depth_width, depth_height)), 0)).r;
#else
		depth_refraction= sample2D(depth_buffer, texcoord_refraction).r;	
#endif
#if (DX_VERSION == 9) && defined(pc)
		depth_refraction = k_water_view_depth_constant.x / depth_refraction + k_water_view_depth_constant.y; // Zbuf = -FN/(F-N) / z + F/(F-N)
#endif // pc
		texcoord_refraction.y= 1.0 - texcoord_refraction.y;
		texcoord_refraction= texcoord_refraction*2 - 1.0f;
		float4 point_refraction= float4(texcoord_refraction, depth_refraction, 1.0f);
		point_refraction= mul(point_refraction, k_water_view_xform_inverse);
		point_refraction.xyz/= point_refraction.w;		

		// hack refraction by depth only, requirement from Justin
		float depth_refraction_by_depth= abs(point_refraction.z - INTERPOLATORS.position_ws.z);		
		float depth_refraction_by_distance= length(point_refraction.xyz - INTERPOLATORS.position_ws.xyz);		
		depth_refraction= lerp(depth_refraction_by_distance, depth_refraction_by_depth, refraction_depth_dominant_ratio);		

		// compute refraction
		float transparence= saturate(1.0f - compute_fog_factor(water_murkiness, depth_refraction) * ripple_slope_length);			
		transparence= transparence * saturate(1.0f - INTERPOLATORS.incident_ws.w/refraction_extinct_distance);		
		color_refraction= lerp(water_color * ripple_slope_length, color_refraction, transparence);	
		color_refraction_bed_contribution= transparence; // track refraction bed contribution
	}	
	
	// compute foam	
	float4 foam_color= 0.0f;
	float foam_factor= 0.0f;	
	{
		// calculate factor
		float foam_factor_auto= 0.0f;
		float foam_factor_paint= 0.0f;
		if (TEST_CATEGORY_OPTION(foam, auto) || TEST_CATEGORY_OPTION(foam, both))
		{				
			foam_factor_auto= saturate( (INTERPOLATORS.base_tex.z - foam_height) / saturate(INTERPOLATORS.base_tex.w - foam_height));							
			foam_factor_auto= pow(foam_factor_auto, foam_pow);
		}	

		if (TEST_CATEGORY_OPTION(foam, paint) || TEST_CATEGORY_OPTION(foam, both))
		{
			foam_factor_paint= sample2D(global_shape_texture, INTERPOLATORS.base_tex.xy).b;			
			//float foam_factor_shape= saturate( (INTERPOLATORS.base_tex.z + INTERPOLATORS.base_tex.w) / (2 * INTERPOLATORS.base_tex.w));										
			//foam_factor_paint *= foam_factor_shape;
		}

		// output factor
		if (TEST_CATEGORY_OPTION(foam, auto))
		{
			foam_factor= foam_factor_auto;
		}
		else if (TEST_CATEGORY_OPTION(foam, paint))
		{
			foam_factor= foam_factor_paint;
		}
		else if (TEST_CATEGORY_OPTION(foam, both))
		{
			foam_factor= max(foam_factor_auto, foam_factor_paint);
		}

		// add ripple foam
		foam_factor= max(ripple_foam_factor, foam_factor);

#ifndef pc
		[branch]
#endif // pc
		if ( foam_factor > 0.002f )
		{
			// blend textures
			float4 foam= sample2D(foam_texture, transform_texcoord(INTERPOLATORS.texcoord.xy, foam_texture_xform));
			float4 foam_detail= sample2D(foam_texture_detail, transform_texcoord(INTERPOLATORS.texcoord.xy, foam_texture_detail_xform));
			foam_color.rgb= foam.rgb * foam_detail.rgb;
			foam_color.a= foam.a * foam_detail.a;		
			foam_factor= foam_color.w * foam_factor;
		}
	}

	// compute diffuse by n dot l
	float3 water_kd= water_diffuse; 
	float3 sun_dir_ws= float3(0.0, 0.0, 1.0);	//	sun direction
	//sun_dir_ws= normalize(sun_dir_ws);
	float n_dot_l= saturate(dot(sun_dir_ws, normal));	
	float3 color_diffuse= water_kd * n_dot_l;	

	// compute reflection
	float3 color_reflection= 0; //float3(0.1, 0.1, 0.1) * reflection_coefficient;
	if (TEST_CATEGORY_OPTION(reflection, none))
	{
		color_reflection= float3(0, 0, 0);
	}
	else
		float3 normal_reflect= lerp(normal, float3(0.0f, 0.0f, 1.0f), 1.0f - normal_variation_tweak);	// NOTE: uses inverted normal variation tweak -- if we invert ourselves we can save this op

		float3 reflect_dir= reflect(-INTERPOLATORS.incident_ws.xyz, normal_reflect);
		reflect_dir.y*= -1.0;

		// sample environment map
		float4 environment_sample;
		if (TEST_CATEGORY_OPTION(reflection, static))
		{
			environment_sample= sampleCUBE(environment_map, reflect_dir);
			environment_sample.rgb *= 256;		// static cubemap doesn't have exponential bias
		}
	else if (TEST_CATEGORY_OPTION(reflection, static))
	{
		float3 reflect_dir= reflect(-INTERPOLATORS.incident_ws.xyz, normal);

		// flip z
		reflect_dir.z= abs(reflect_dir.z);
		float4 environment_sample= sampleCUBE(environment_map, reflect_dir);

		// apply HDR from alpha, but dim it in shadow area
		float2 parts;
		parts.x= saturate(environment_sample.a - sunspot_cut);
		parts.y= min(environment_sample.a, sunspot_cut);	
		
		float3 sun_light_rate= saturate(lightmap_intensity - shadow_intensity_mark);
		float sun_scale= dot(sun_light_rate, sun_light_rate);		

		float alpha= parts.x*sun_scale + parts.y;
		color_reflection= environment_sample.rgb * alpha;

		color_reflection*= reflection_coefficient;
	}
	else if (TEST_CATEGORY_OPTION(reflection, dynamic))
	{
		float4 reflection_0= sampleCUBE(dynamic_environment_map_0, reflect_dir);
		color_reflection= sample2D(scene_ldr_texture, float2(texcoord_ss.x, texcoord_ss.y-0.2f));		
		color_reflection*= reflection_coefficient;
	 	float4 reflection_1= texCUBE(dynamic_environment_map_1, reflect_dir);
		environment_sample= reflection_0;//* dynamic_environment_blend.w;				//	reflection_1 * (1.0f-dynamic_environment_blend.w);
		environment_sample.rgb *= environment_sample.rgb * 4;
		environment_sample.a /= 4;
		//dynamnic cubempa has 2 exponent bias. so we need to restore the original value for the original math
		// evualuate HDR color with considering of shadow
		float2 parts;
		parts.x= saturate(environment_sample.a - sunspot_cut);
		parts.y= min(environment_sample.a, sunspot_cut);

		float3 sun_light_rate= saturate(lightmap_intensity - shadow_intensity_mark);
		float sun_scale= dot(sun_light_rate, sun_light_rate);

		const float shadowed_alpha= parts.x*sun_scale + parts.y;
		color_reflection=
			environment_sample.rgb *
			shadowed_alpha *
			reflection_coefficient;
	}

	// only apply lightmap_intensity on diffuse and reflection, watercolor of refrection has already considered
	color_diffuse*= lightmap_intensity;	
	foam_color.rgb*= lightmap_intensity;

	// add dynamic lighting
	[branch]
	if (!no_dynamic_lights)
	{
		float3 simple_light_diffuse_light; //= 0.0f;
		float3 simple_light_specular_light; //= 0.0f;
		
		calc_simple_lights_analytical(
			INTERPOLATORS.position_ws.xyz,
			normal,
			-INTERPOLATORS.incident_ws.xyz,
			20,
			simple_light_diffuse_light,
			simple_light_specular_light);

		color_diffuse+= simple_light_diffuse_light * water_kd;
		color_reflection+= simple_light_specular_light;
	}

	// computer fresnel and output color	
#if defined(pc) && (DX_VERSION == 9)
	float3 fresnel_normal = /*k_is_camera_underwater ? -normal :*/ normal;
#else
	float3 fresnel_normal= normal * 2 * (0.5f - k_is_camera_underwater);
#endif
	float fresnel= compute_fresnel(INTERPOLATORS.incident_ws.xyz, fresnel_normal, fresnel_coefficient);
	//fresnel= saturate(fresnel*ripple_slope_length);		// apply interaction disturbance
	output_color= lerp(color_refraction, color_reflection,  fresnel);
	color_refraction_bed_contribution*= 1.0f - fresnel; // track refraction bed contribution
	
	// add diffuse
	output_color= output_color + color_diffuse; 

	// apply bank alpha
	if ( ! TEST_CATEGORY_OPTION(bankalpha, none) )
	{
		float alpha= 1.0f;
		if ( TEST_CATEGORY_OPTION(bankalpha, paint) )
		{
			alpha= saturate(water_color_from_texture.w);			
		}
		else if (TEST_CATEGORY_OPTION(bankalpha, depth))
		{
#ifndef pc // todo: not enough output registers on PC [01/28/2013 paul.smirnov]
			alpha= saturate(INTERPOLATORS.misc_info.w / bankalpha_infuence_depth);					
#else
			alpha= saturate(INTERPOLATORS.position_ws.w / bankalpha_infuence_depth);					
#endif // pc
		}
		//alpha= saturate(alpha * ripple_slope_length);	//apply interaction disturbance

		output_color= lerp(color_refraction_bed, output_color, alpha);	

		color_refraction_bed_contribution= (1.0f-alpha) + color_refraction_bed_contribution*alpha; // track refraction bed contribution
	}

	// apply foam
	output_color= lerp(output_color, foam_color.xyz, foam_factor);
	color_refraction_bed_contribution*= 1.0f - foam_factor; // track refraction bed contribution		
	if (!TEST_CATEGORY_OPTION(foam, none))
	{
			output_color.rgb= lerp(output_color.rgb, foam_color.rgb, foam_factor);
	}

	// apply fog
	{
		// deduct refrection
		output_color= output_color - color_refraction_bed*color_refraction_bed_contribution; 	

		output_color= output_color*INTERPOLATORS.fog_extinction + INTERPOLATORS.fog_inscatter * BLEND_FOG_INSCATTER_SCALE* (1.0f - color_refraction_bed_contribution); 	
		output_color= output_color * g_exposure.rrr; 

		// recover refrection
		output_color= output_color + color_refraction_bed*color_refraction_bed_contribution;	
	}
	// apply under water fog
#if (! defined(pc)) || (DX_VERSION == 11)
	[branch]
	if ( k_is_camera_underwater )
	{
		float transparence= 0.5f * saturate(1.0f - compute_fog_factor(k_ps_underwater_murkiness, INTERPOLATORS.incident_ws.w));					
		output_color= lerp(k_ps_underwater_fog_color, output_color, transparence);	
	}
#endif // pc
////////////////////////////////////////////////////////////////////////////////////////////////////
/*
#ifdef pc
	float3 to_show = output_color;
	
	float2 screen_space = INTERPOLATORS.position_ss.xy / INTERPOLATORS.position_ss.w;
	to_show = screen_space.y > 0 ?
		(screen_space.x < 0 ? to_show : -to_show) :
		(screen_space.x < 0 ? 0.25 + 0.25 * to_show : 0.25 - 0.25 * to_show);
	return convert_to_render_target(float4(to_show, 1.0f), true, true);
#endif
*/
////////////////////////////////////////////////////////////////////////////////////////////////////
	return convert_to_render_target(float4(output_color, 1.0f), true, true);		
}

#endif //PIXEL_SHADER


/* entry point calls */

#ifdef VERTEX_SHADER
s_water_interpolators water_shading_tessellation_vs( s_vertex_type_water_shading IN )
{
#ifdef pc
	s_water_render_vertex vertex= get_vertex( IN );
	s_water_interpolators water_dense_per_pixel_vs( s_vertex_type_water_shading IN )
{
	s_water_render_vertex vertex= get_tessellated_vertex( IN );
	return transform_vertex( vertex, false );
}
s_water_interpolators water_flat_per_pixel_vs( s_vertex_type_water_shading IN )
{
	s_water_render_vertex vertex= get_vertex( IN, false);
	return transform_vertex( vertex, false );
}

s_water_interpolators water_flat_per_vertex_vs( s_vertex_type_water_shading IN )
{
	s_water_render_vertex vertex= get_vertex( IN, true );
	return transform_vertex( vertex, true );
}

s_water_interpolators water_flat_blend_per_pixel_vs(s_vertex_type_water_shading IN)
{
	s_water_render_vertex vertex= get_vertex( IN, false );
	return transform_vertex( vertex, false );
}

s_water_interpolators water_flat_blend_per_vertex_vs(s_vertex_type_water_shading IN)
{
	s_water_render_vertex vertex= get_vertex( IN, true );
	return transform_vertex( vertex, true );
}

s_water_interpolators lightmap_debug_mode_vs( s_vertex_type_water_shading IN )
{
	s_water_render_vertex vertex= get_vertex( IN, false );
	return transform_vertex( vertex, false );
}
#else
	s_water_render_vertex vertex= get_tessellated_vertex( IN );
s_water_interpolators water_dense_per_pixel_vs( s_vertex_type_water_shading IN )
{
	s_water_render_vertex vertex= get_tessellated_vertex( IN );
	return transform_vertex( vertex, false );
}

s_water_interpolators water_flat_per_pixel_vs( s_vertex_type_water_shading IN )
{
	s_water_render_vertex vertex= get_vertex( IN, false);
	return transform_vertex( vertex, false );
}

s_water_interpolators water_flat_per_vertex_vs( s_vertex_type_water_shading IN )
{
	s_water_render_vertex vertex= get_vertex( IN, true );
	return transform_vertex( vertex, true );
}

s_water_interpolators water_flat_blend_per_pixel_vs(s_vertex_type_water_shading IN)
{
	s_water_render_vertex vertex= get_vertex( IN, false );
	return transform_vertex( vertex, false );
}

s_water_interpolators water_flat_blend_per_vertex_vs(s_vertex_type_water_shading IN)
{
	s_water_render_vertex vertex= get_vertex( IN, true );
	return transform_vertex( vertex, true );
}

s_water_interpolators lightmap_debug_mode_vs( s_vertex_type_water_shading IN )
{
	s_water_render_vertex vertex= get_vertex( IN, false );
	return transform_vertex( vertex, false );
}
#endif
	return transform_vertex( vertex );
}

s_water_interpolators water_shading_non_tessellation_vs( s_vertex_type_water_shading IN )
{
	s_water_render_vertex vertex= get_vertex( IN );
	return transform_vertex( vertex );
}
#endif //VERTEX_SHADER


#ifdef PIXEL_SHADER
accum_pixel water_shading_tessellation_ps(s_water_interpolators INTERPOLATORS)
{
	return water_shading(INTERPOLATORS);
}

accum_pixel water_shading_non_tessellation_ps(s_water_interpolators INTERPOLATORS)
{
	return water_shading(INTERPOLATORS);
}

accum_pixel water_dense_per_pixel_ps(s_water_interpolators INTERPOLATORS)
{
	return water_shading(INTERPOLATORS, false, false);
}

accum_pixel water_flat_per_pixel_ps(s_water_interpolators INTERPOLATORS)
{
	return water_shading(INTERPOLATORS, false, false);
}

accum_pixel water_flat_per_vertex_ps(s_water_interpolators INTERPOLATORS)
{
	return water_shading(INTERPOLATORS, true, false);
}

accum_pixel water_flat_blend_per_pixel_ps(s_water_interpolators INTERPOLATORS)
{
	return water_shading(INTERPOLATORS, false, true);
}

accum_pixel water_flat_blend_per_vertex_ps(s_water_interpolators INTERPOLATORS)
{
	return water_shading(INTERPOLATORS, true, true);
}

accum_pixel lightmap_debug_mode_ps(s_water_interpolators IN)
{
	float4 out_color;

	// setup tangent frame

	float3 ambient_only= 0.0f;
	float3 linear_only= 0.0f;
	float3 quadratic= 0.0f;

	out_color= display_debug_modes(
		IN.lm_tex,
		IN.normal,
		IN.texcoord,
		IN.tangent,
		IN.binormal,
		IN.normal,
		ambient_only,
		linear_only,
		quadratic);

	return convert_to_render_target(out_color, true, false);
}
#endif //PIXEL_SHADER

#ifdef VERTEX_SHADER
float4 water_depth_only_vs( s_vertex_type_water_shading IN ) : SV_Position
{
	s_water_render_vertex vertex = get_vertex( IN );
	s_water_interpolators interpolators = transform_vertex( vertex );
	return interpolators.position;
}
#endif

#ifdef PIXEL_SHADER
float4 water_depth_only_ps( in float4 position : SV_Position ) : SV_Target
{
	return 0;
}
#endif

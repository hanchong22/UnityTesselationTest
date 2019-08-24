Shader "TesselationTest/Ulit"
{
    Properties
    {
        _MainTex ("主纹理", 2D) = "white" {}
		_Color("主颜色", Color)              =(1, 1, 1, 1)   

		_BumpMap("法线纹理", 2D)                 = "bump" {}
        _Mask("遮罩纹理,高光(R)",2D) = "black" {}

		[HDR]_Specular("高光颜色", Color)       = (1, 1, 1, 1)
        _SpecularScale ("高光倍数", Float) =        1.0
        _Gloss("高光范围", Range(0, 512)) =         20
        _BumpScale("凹凸倍数", Range(-5, 5)) = 1.0
        _HeightScale("高度倍数（法线Z方向）",Range(-1,1)) = 0.1
		   
		[HDR]_FresnelColor	 ("菲涅尔颜色", Color) = (1,1,1,1)
		_FresnelScale ("菲涅尔倍数", Range(0, 1)) = 0	
		_FresnelBias("菲涅尔范围", Range(0, 2)) = 0

		_TessEdgeLength( "镶嵌边长", Range( 2,50 ) ) = 5
        _TessPhongStrength( "镶嵌Phong强度", Range( 0,1 ) ) = 0.5
        _TessExtrusionAmount( "镶嵌扩张", Range( -1,1 ) ) = 0.0
    }

	CGINCLUDE
		#include "UnityCG.cginc"
		#include "Lighting.cginc"
		#include "AutoLight.cginc"
		#include "Tessellation.cginc"	

		#pragma multi_compile_fwdbase_fullshadows
		#pragma multi_compile_instancing
		
		#define USING_FOG (defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2))
		#pragma multi_compile_fog			


		
		struct InternalTessInterp_VertexInput
		{
			half4 vertex : INTERNALTESSPOS;			
			half4 uv : TEXCOORD0;	

			half3 normal : NORMAL;
        	half4 tangent : TANGENT;	

			UNITY_VERTEX_OUTPUT_STEREO
        	UNITY_VERTEX_INPUT_INSTANCE_ID
	
		};

		struct VertexInput {
			half4 vertex : POSITION;	
			half3 normal : NORMAL;
        	half4 tangent : TANGENT;

			half4 texcoord0 : TEXCOORD0;

			UNITY_VERTEX_INPUT_INSTANCE_ID
		};

		struct VertexOutput {			
			half4 pos      : SV_POSITION;
			half4 uv       : TEXCOORD0;       
			
			half4 viewDir  : TEXCOORD1;
			half3 lightDir : TEXCOORD2;			

			#if USING_FOG
				fixed fog : TEXCOORD5;
				SHADOW_COORDS(4)
			#else
				SHADOW_COORDS(3)
			#endif

			UNITY_VERTEX_OUTPUT_STEREO
			UNITY_VERTEX_INPUT_INSTANCE_ID
		};


		sampler2D _MainTex;
		float4 _MainTex_ST;
		sampler2D _BumpMap;
		sampler2D _Mask;
		half4 _BumpMap_ST;   
		half4 _Mask_ST;

		half4 _FresnelColor;
		half _FresnelScale;
		half _FresnelBias;
		fixed4 _Specular;
		fixed _Gloss;	
		fixed _BumpScale;	
		fixed _HeightScale;			
		fixed _SpecularScale;

		half _TessPhongStrength;
		half _TessEdgeLength;
		half _TessExtrusionAmount;

		fixed3 MyUnpackNormalmapRGorAG(fixed4 packednormal,fixed xyScale,fixed zScale)
		{  
			fixed3 normal;
			normal.xy = (packednormal.xy * 2 - 1) * xyScale;
			normal.z = sqrt(1 - saturate(dot(normal.xy, normal.xy))) +  packednormal.w * zScale;
			return normal;
		}


		inline fixed3 MyUnpackNormal(fixed4 packednormal, fixed xyScale, fixed zScale)
		{
			return MyUnpackNormalmapRGorAG(packednormal,xyScale,zScale);
		}


		UNITY_INSTANCING_BUFFER_START(MyProperties)  
        	UNITY_DEFINE_INSTANCED_PROP(half4,_Color)        
    	UNITY_INSTANCING_BUFFER_END(MyProperties)

		//顶点着色器，输出数据到镶嵌着色器（Tesselation Shader）
		InternalTessInterp_VertexInput tess_vert(VertexInput v)
		{
			InternalTessInterp_VertexInput o;

			UNITY_SETUP_INSTANCE_ID(v);
			UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
			UNITY_TRANSFER_INSTANCE_ID(v,   o);   

			o.vertex = v.vertex;
			o.uv = v.texcoord0;	
			o.normal = v.normal;
			o.tangent = v.tangent;		
			return o;
		}

		inline VertexInput _ds_VertexInput(UnityTessellationFactors tessFactors, const OutputPatch<InternalTessInterp_VertexInput, 3> vi, float3 bary : SV_DomainLocation)
		{
			VertexInput v;
			v.vertex = vi[0].vertex*bary.x + vi[1].vertex*bary.y + vi[2].vertex*bary.z;		

			half3 pp[3];
			for (int i = 0; i < 3; ++i)
				pp[i] = v.vertex.xyz - vi[i].normal * (dot(v.vertex.xyz, vi[i].normal) - dot(vi[i].vertex.xyz, vi[i].normal));

			v.vertex.xyz = _TessPhongStrength * (pp[0] * bary.x + pp[1] * bary.y + pp[2] * bary.z) + (1.0f - _TessPhongStrength) * v.vertex.xyz;
			v.tangent = vi[0].tangent*bary.x + vi[1].tangent*bary.y + vi[2].tangent*bary.z;
			v.normal = vi[0].normal*bary.x + vi[1].normal*bary.y + vi[2].normal*bary.z;
			v.vertex.xyz += v.normal.xyz * _TessExtrusionAmount;
			v.texcoord0 = vi[0].uv*bary.x + vi[1].uv*bary.y + vi[2].uv*bary.z;
			
			return v;
		}


		// 镶嵌常量外壳着色器（tessellation hull constant shader）
		UnityTessellationFactors hsconst_VertexInput(InputPatch<InternalTessInterp_VertexInput, 3> v)
		{
			half4 tf = UnityEdgeLengthBasedTess(v[0].vertex, v[1].vertex, v[2].vertex, _TessEdgeLength);
			UnityTessellationFactors o;
			o.edge[0] = tf.x;
			o.edge[1] = tf.y;
			o.edge[2] = tf.z;
			o.inside = tf.w;
			return o;
		}

		// 镶嵌外壳着色器（tessellation hull shader）
		[UNITY_domain("tri")]
		[UNITY_partitioning("fractional_odd")]
		[UNITY_outputtopology("triangle_cw")]
		[UNITY_patchconstantfunc("hsconst_VertexInput")]
		[UNITY_outputcontrolpoints(3)]
		InternalTessInterp_VertexInput hs_VertexInput(InputPatch<InternalTessInterp_VertexInput, 3> v, uint id : SV_OutputControlPointID)
		{
			return v[id];
		}

		VertexOutput vert (VertexInput v) {
			VertexOutput o = (VertexOutput)0;			
			o.pos = UnityObjectToClipPos(v.vertex );
		
			o.uv.xy = v.texcoord0.xy * _MainTex_ST.xy + _MainTex_ST.zw;	
			o.uv.zw = v.texcoord0.xy * _Mask_ST.xy + _Mask_ST.zw;	

			TANGENT_SPACE_ROTATION;
        
			half3 cameraDir =  ObjSpaceViewDir(v.vertex);
			o.lightDir=mul(rotation,ObjSpaceLightDir(v.vertex)).xyz;
			o.viewDir.xyz=mul(rotation,cameraDir).xyz;
			o.viewDir.w =  length(cameraDir);

			#if USING_FOG
				half3 eyePos = UnityObjectToViewPos(v.vertex);
				half fogCoord = length(eyePos.xyz);
				UNITY_CALC_FOG_FACTOR_RAW(fogCoord);
				o.fog = saturate(unityFogFactor);
			#endif
				

			return o;
		}

		// 镶嵌域着色器(tessellation domain shader)
		[UNITY_domain("tri")]
		VertexOutput ds_surf(UnityTessellationFactors tessFactors, const OutputPatch<InternalTessInterp_VertexInput, 3> vi, float3 bary : SV_DomainLocation)
		{
			VertexInput v = _ds_VertexInput(tessFactors, vi, bary);
			return vert(v);
		}

		//像素片段
		fixed4 frag(VertexOutput i) : SV_Target
		{
			half4 tex = tex2D(_MainTex, i.uv.xy); 

			half3 tangentLightDir = normalize(i.lightDir);
			half3 tangentViewDir = normalize(i.viewDir.xyz);

			half3 tangentNormal = MyUnpackNormal(tex2D(_BumpMap, i.uv.xy), _BumpScale, _HeightScale);    
			half3 halfDir = normalize(tangentLightDir + tangentViewDir);

			//mask
			half4 maskTex = tex2D(_Mask,i.uv.zw);

			// 遮罩取样，maskTex的r通道作为高光遮罩
			half specularMask = maskTex.r * _SpecularScale;

			//菲涅尔
			fixed fresnel = _FresnelScale + ( _FresnelBias - _FresnelScale)  * pow( _FresnelBias - dot(tangentViewDir, tangentNormal), 5);
			tex.rgb = lerp(tex.rgb , _FresnelColor.rgb, saturate(fresnel) ) ;

			half4 albedo = half4(tex.rgb * UNITY_ACCESS_INSTANCED_PROP(MyProperties,_Color),1.0);			

			half3 specular = _LightColor0.rgb * _Specular.rgb * pow(max(0, dot(tangentNormal, halfDir)), _Gloss) * specularMask  ;
        	half3 ambient = UNITY_LIGHTMODEL_AMBIENT.xyz * albedo.rgb ;

			half halfLambert =   dot(tangentNormal, tangentLightDir) * 0.5 + 0.5;
        	half3 diffuse = _LightColor0.rgb * albedo.rgb * halfLambert;  



			half4 c = half4(ambient +  diffuse + specular    , 1.0);	
        	c.a = tex.a;

			#if USING_FOG
		    	c.rgb = lerp(unity_FogColor.rgb, c.rgb, i.fog);
        	#endif

			return c;
		}

	ENDCG
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
				#pragma target 5.0 
				//顶点着色器
				#pragma vertex tess_vert
				//外壳着色器
				#pragma hull hs_VertexInput
				//域着色器
				#pragma domain ds_surf
				//像素片段着色器
				#pragma fragment frag
           
            ENDCG
        }
    }
}

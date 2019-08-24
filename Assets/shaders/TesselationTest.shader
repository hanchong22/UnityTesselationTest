Shader "TesselationTest/Ulit"
{
    Properties
    {
        _MainTex ("主纹理", 2D) = "white" {}

		_TessEdgeLength( "镶嵌边长", Range( 2,50 ) ) = 5
        _TessPhongStrength( "镶嵌Phong强度", Range( 0,1 ) ) = 0.5
        _TessExtrusionAmount( "镶嵌挤压", Range( -1,1 ) ) = 0.0
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
			

		struct appdata
		{
			float4 vertex : POSITION;
			float4 uv : TEXCOORD0;

			half3 normal : NORMAL;
        	half4 tangent : TANGENT;
		};
		
		struct InternalTessInterp_VertexInput
		{
			float4 vertex : INTERNALTESSPOS;			
			float4 uv : TEXCOORD0;	

			half3 normal : NORMAL;
        	half4 tangent : TANGENT;	

			UNITY_VERTEX_OUTPUT_STEREO
        	UNITY_VERTEX_INPUT_INSTANCE_ID
	
		};

		struct VertexInput {
			float4 vertex : POSITION;	
			half3 normal : NORMAL;
        	half4 tangent : TANGENT;

			float4 texcoord0 : TEXCOORD0;

			UNITY_VERTEX_INPUT_INSTANCE_ID
		};

		struct VertexOutput {			
			float4 pos      : SV_POSITION;
			float4 uv       : TEXCOORD0;       
			
			half4 viewDir  : TEXCOORD1;
			half3 lightDir : TEXCOORD2;
			half3 worldPos : TEXCOORD3;
			half3 modelPos : TEXCOORD4; 

			#if USING_FOG
				fixed fog : TEXCOORD5;
				SHADOW_COORDS(6)
			#else
				SHADOW_COORDS(5)
			#endif

			UNITY_VERTEX_OUTPUT_STEREO
			UNITY_VERTEX_INPUT_INSTANCE_ID
		};


		sampler2D _MainTex;
		float4 _MainTex_ST;

		float _TessPhongStrength;
		float _TessEdgeLength;
		float _TessExtrusionAmount;

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

			float3 pp[3];
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
			float4 tf = UnityEdgeLengthBasedTess(v[0].vertex, v[1].vertex, v[2].vertex, _TessEdgeLength);
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
			o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
			o.modelPos = mul(unity_ObjectToWorld, fixed4(0,0,0,1)).xyz;     //世界矩阵乘以模型空间的0点，即获得模型中心的点世界坐标,顶点齐次坐标为1
			o.uv.xy = v.texcoord0.xy * _MainTex_ST.xy + _MainTex_ST.zw;	

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

		//像素片段，仅做最简单实现
		fixed4 frag(VertexOutput i) : SV_Target
		{
			fixed4 col = tex2D(_MainTex, i.uv.xy);
			#if USING_FOG
		    	col.rgb = lerp(unity_FogColor.rgb, col.rgb, i.fog);
        	#endif
			return col;
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

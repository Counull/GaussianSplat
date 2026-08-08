Shader "GaussianSplat/DebugSoftSphere"
{
    Properties
    {
        _GaussianColor ("DC Color and Center Alpha", Color) = (1, 1, 1, 1)
        _Falloff ("Edge Falloff", Range(0.1, 16.0)) = 4.5
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Transparent"
            "RenderType" = "Transparent"
        }

        Pass
        {
            Name "DebugSoftSphere"
            Tags { "LightMode" = "UniversalForward" }

            Blend One OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _GaussianColor;
                float _Falloff;
        
            CBUFFER_END

            Varyings Vert(Attributes input)
            {
                Varyings output = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs positionInputs =
                    GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInputs =
                    GetVertexNormalInputs(input.normalOS);

                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = normalInputs.normalWS;
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float3 normalWS = normalize(input.normalWS);
                float3 viewDirectionWS =
                    SafeNormalize(GetCameraPositionWS() - input.positionWS);

                // Approximate a screen-space radial Gaussian from a sphere's silhouette.
                half nDotV = saturate(dot(normalWS, viewDirectionWS));
                half radiusSquared = saturate(1.0h - nDotV * nDotV);
                half gaussian = exp(-_Falloff * radiusSquared);
                half alpha = _GaussianColor.a * gaussian;

              
                // Premultiplied-alpha output for Blend One OneMinusSrcAlpha.
                return half4(_GaussianColor.rgb * alpha, alpha);
            }
            ENDHLSL
        }
    }
}

Shader "Custom/GaussianSplatShader"
{
    Properties {}

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct GpuGaussian
            {
                float4 positionOpacity;
                float4 scale;
                float4 rotation;
                float4 dc;
            };

            struct Attributes
            {
                uint vertexID : SV_VertexID;
                uint instanceID : SV_InstanceID;
            };

            struct Varyings
            {
            };


            StructuredBuffer<GpuGaussian> _Gaussians;
            StructuredBuffer<int> _SortedIndices;
            StructuredBuffer<float4> _ShRest;

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 color = half4(0, 0, 0, 0);
                return color;
            }
            ENDHLSL
        }
    }
}
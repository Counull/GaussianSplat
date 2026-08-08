Shader "Custom/GaussianSplatShader"
{
    Properties {}

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline"
        }

        Blend One OneMinusSrcAlpha
        Cull Off
        ZWrite Off
        ZTest LEqual

        Pass
        {
            HLSLPROGRAM
            #pragma target 4.5
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
                float4 positionHCS : SV_POSITION;
                float2 splatOffsetNDC : TEXCOORD0;
                nointerpolation float3 conic : TEXCOORD1;
                nointerpolation float4 colorOpacity : TEXCOORD2;
            };

            static const float2 Corners[6] =
            {
                float2(-1, -1), float2(-1, 1), float2(1, 1),
                float2(-1, -1), float2(1, 1), float2(1, -1),
            };

            StructuredBuffer<GpuGaussian> _Gaussians;
            StructuredBuffer<int> _SortedIndices;
            StructuredBuffer<float4> _ShRest;
            float4x4 _SplatLocalToWorld;

            // The Gaussian is not compact at alpha = 0, so this must stay above zero.
            static const float AlphaCut = 0.01;

            float3x3 QuaternionToRotationMatrix(float4 q)
            {
                q = normalize(q);

                float x = q.x;
                float y = q.y;
                float z = q.z;
                float w = q.w;

                return float3x3(
                    1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - z * w), 2.0 * (x * z + y * w),
                    2.0 * (x * y + z * w), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - x * w),
                    2.0 * (x * z - y * w), 2.0 * (y * z + x * w), 1.0 - 2.0 * (x * x + y * y)
                );
            }

            float3x3 SigmaLocal(float3 scale)
            {
                return float3x3(
                    scale.x * scale.x, 0.0, 0.0,
                    0.0, scale.y * scale.y, 0.0,
                    0.0, 0.0, scale.z * scale.z
                );
            }

            float3x3 TransformCovariance(float3x3 sigma, float3x3 linearTransform)
            {
                return mul(mul(linearTransform, sigma), transpose(linearTransform));
            }

            float3x3 LinearPart(float4x4 transform)
            {
                return float3x3(
                    transform._m00, transform._m01, transform._m02,
                    transform._m10, transform._m11, transform._m12,
                    transform._m20, transform._m21, transform._m22
                );
            }

            // Returns (a, b, c) for Sigma2D = [ a b ; b c ] in NDC units.
            float3 ProjectCovarianceToNdc(float3 centerVS, float3x3 sigmaCamera)
            {
                float depth = max(-centerVS.z, 1e-4);
                float fx = UNITY_MATRIX_P._m00;
                float fy = UNITY_MATRIX_P._m11;

                // The covariance is expressed in Unity View Space (x, y, z),
                // where points in front of the camera have z < 0.
                float3 ju = float3(
                    fx / depth,
                    0.0,
                    fx * centerVS.x / (depth * depth)
                );
                float3 jv = float3(
                    0.0,
                    fy / depth,
                    fy * centerVS.y / (depth * depth)
                );

                float3 sigmaJu = mul(sigmaCamera, ju);
                float3 sigmaJv = mul(sigmaCamera, jv);

                return float3(
                    dot(ju, sigmaJu),
                    dot(ju, sigmaJv),
                    dot(jv, sigmaJv)
                );
            }

            Varyings vert(Attributes IN)
            {
                uint gaussianId = _SortedIndices[IN.instanceID];
                GpuGaussian gaussian = _Gaussians[gaussianId];
                float2 corner = Corners[IN.vertexID];

                float3 centerWS = mul(
                    _SplatLocalToWorld,
                    float4(gaussian.positionOpacity.xyz, 1.0)
                ).xyz;

                float3x3 sigmaRotated = TransformCovariance(
                    SigmaLocal(gaussian.scale.xyz),
                    QuaternionToRotationMatrix(gaussian.rotation)
                );
                float3x3 sigmaWorld = TransformCovariance(
                    sigmaRotated,
                    LinearPart(_SplatLocalToWorld)
                );
                float3x3 sigmaCamera = TransformCovariance(
                    sigmaWorld,
                    LinearPart(UNITY_MATRIX_V)
                );

                float3 centerVS =
                    mul(UNITY_MATRIX_V, float4(centerWS, 1.0)).xyz;
                float3 sigma2D = ProjectCovarianceToNdc(centerVS, sigmaCamera);

                float a = max(sigma2D.x, 1e-12);
                float b = sigma2D.y;
                float c = max(sigma2D.z, 1e-12);
                float determinant = max(a * c - b * b, 1e-20);

                float opacity = saturate(gaussian.positionOpacity.w);
                // K^2 = -2 * log(AlphaCut / opacity).
                float radiusSquared = 2.0 * log(max(opacity, AlphaCut) / AlphaCut);
                float2 radiusNDC = sqrt(radiusSquared * float2(a, c));

                Varyings OUT;
                float4 centerHCS = TransformWorldToHClip(centerWS);
                OUT.splatOffsetNDC = corner * radiusNDC;
                OUT.positionHCS = centerHCS;
                OUT.positionHCS.xy += OUT.splatOffsetNDC * centerHCS.w;
                OUT.conic = float3(c, -b, a) / determinant;
                OUT.colorOpacity = float4(
                    0.5 + 0.2820947918 * gaussian.dc.xyz,
                    opacity
                );
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 d = IN.splatOffsetNDC;
                float r2 = IN.conic.x * d.x * d.x
                    + 2.0 * IN.conic.y * d.x * d.y
                    + IN.conic.z * d.y * d.y;
                float alpha = IN.colorOpacity.a * exp(-0.5 * r2);

                clip(alpha - AlphaCut);
                return float4(IN.colorOpacity.rgb * alpha, alpha);
            }
            ENDHLSL
        }
    }
}

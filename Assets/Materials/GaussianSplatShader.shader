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
            int _ShRestVectorCount;
            int _ShRestFloatCount;
            float4x4 _SplatLocalToWorld;
            float4x4 _SplatWorldToLocal;

  
            static const float AlphaCut = 0.01;

            static const float SH_C0 = 0.28209479177387814;
            static const float SH_C1 = 0.4886025119029199;
            static const float SH_C2[5] =
            {
                1.0925484305920792,
                -1.0925484305920792,
                0.31539156525252005,
                -1.0925484305920792,
                0.5462742152960396
            };
            static const float SH_C3[7] =
            {
                -0.5900435899266435,
                2.890611442640554,
                -0.4570457994644658,
                0.3731763325901154,
                -0.4570457994644658,
                1.445305721320277,
                -0.5900435899266435
            };

            float LoadShRest(uint gaussianId, int restIndex)
            {
                uint packedIndex = gaussianId * (uint)_ShRestVectorCount
                    + (uint)(restIndex / 4);
                float4 packed = _ShRest[packedIndex];
                return packed[restIndex % 4];
            }

            float3 LoadShCoefficient(uint gaussianId, int shCoefficientIndex)
            {
                int coefficientsPerChannel = _ShRestFloatCount / 3;
                int restCoefficientIndex = shCoefficientIndex - 1;

                return float3(
                    LoadShRest(gaussianId, restCoefficientIndex),
                    LoadShRest(gaussianId, coefficientsPerChannel + restCoefficientIndex),
                    LoadShRest(gaussianId, 2 * coefficientsPerChannel + restCoefficientIndex)
                );
            }

            float3 EvaluateShColor(uint gaussianId, float3 dc, float3 direction)
            {
                float x = direction.x;
                float y = direction.y;
                float z = direction.z;
                float3 result = SH_C0 * dc;
                int coefficientsPerChannel = _ShRestFloatCount / 3;

                if (coefficientsPerChannel >= 3)
                {
                    result += -SH_C1 * y * LoadShCoefficient(gaussianId, 1);
                    result += SH_C1 * z * LoadShCoefficient(gaussianId, 2);
                    result += -SH_C1 * x * LoadShCoefficient(gaussianId, 3);
                }

                if (coefficientsPerChannel >= 8)
                {
                    float xx = x * x;
                    float yy = y * y;
                    float zz = z * z;
                    float xy = x * y;
                    float yz = y * z;
                    float xz = x * z;

                    result += SH_C2[0] * xy * LoadShCoefficient(gaussianId, 4);
                    result += SH_C2[1] * yz * LoadShCoefficient(gaussianId, 5);
                    result += SH_C2[2] * (2.0 * zz - xx - yy) * LoadShCoefficient(gaussianId, 6);
                    result += SH_C2[3] * xz * LoadShCoefficient(gaussianId, 7);
                    result += SH_C2[4] * (xx - yy) * LoadShCoefficient(gaussianId, 8);

                    if (coefficientsPerChannel >= 15)
                    {
                        result += SH_C3[0] * y * (3.0 * xx - yy) * LoadShCoefficient(gaussianId, 9);
                        result += SH_C3[1] * xy * z * LoadShCoefficient(gaussianId, 10);
                        result += SH_C3[2] * y * (4.0 * zz - xx - yy) * LoadShCoefficient(gaussianId, 11);
                        result += SH_C3[3] * z * (2.0 * zz - 3.0 * xx - 3.0 * yy)
                            * LoadShCoefficient(gaussianId, 12);
                        result += SH_C3[4] * x * (4.0 * zz - xx - yy) * LoadShCoefficient(gaussianId, 13);
                        result += SH_C3[5] * z * (xx - yy) * LoadShCoefficient(gaussianId, 14);
                        result += SH_C3[6] * x * (xx - 3.0 * yy) * LoadShCoefficient(gaussianId, 15);
                    }
                }

                return max(result + 0.5, 0.0);
            }

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

                float3 cameraLS = mul(
                    _SplatWorldToLocal,
                    float4(GetCameraPositionWS(), 1.0)
                ).xyz;
                float3 shDirectionDelta = gaussian.positionOpacity.xyz - cameraLS;
                float3 shDirection = shDirectionDelta
                    * rsqrt(max(dot(shDirectionDelta, shDirectionDelta), 1e-12));
                float3 shColor = EvaluateShColor(gaussianId, gaussian.dc.xyz, shDirection);

                Varyings OUT;
                float4 centerHCS = TransformWorldToHClip(centerWS);
                OUT.splatOffsetNDC = corner * radiusNDC;
                OUT.positionHCS = centerHCS;
                OUT.positionHCS.xy += OUT.splatOffsetNDC * centerHCS.w;
                OUT.conic = float3(c, -b, a) / determinant;
                OUT.colorOpacity = float4(
                    shColor,
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

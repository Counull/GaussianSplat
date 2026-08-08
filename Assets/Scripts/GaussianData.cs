using System.Runtime.InteropServices;
using Unity.Mathematics;
using UnityEngine;


public struct GaussianData
{
	public Vector3 Pos;
	public Vector3 N;
	public Vector3 Dc;
	public float[] Rest;
	public float Opacity;
	public Vector3 Scale;
	public Quaternion Rotation;

	public Color PointColor => new Color(Dc2RGB(Dc.x), Dc2RGB(Dc.y), Dc2RGB(Dc.z));
	public Color DebugPointColor => new Color(Dc2RGB(Dc.x), Dc2RGB(Dc.y), Dc2RGB(Dc.z), Opacity);

	public int RestVectorCount => (int) math.ceil(Rest.Length / 4f);

	public static float Dc2RGB(float dc)
	{
		return 0.5f + 0.2820947918f * dc;
	}
}

[StructLayout(LayoutKind.Sequential)]
public struct GpuGaussianData
{
	private float4 positionOpacity;
	private float4 scale;
	private float4 rotation;
	private float4 dc;

	public GpuGaussianData(GaussianData gaussianData)
	{
		positionOpacity = new float4(gaussianData.Pos, gaussianData.Opacity);
		scale = new float4(gaussianData.Scale, 0);
		rotation = new float4(gaussianData.Rotation.x, gaussianData.Rotation.y, gaussianData.Rotation.z, gaussianData.Rotation.w);
		dc = new float4(gaussianData.Dc, 0);
	}
}
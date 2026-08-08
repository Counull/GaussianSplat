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

	public static float Dc2RGB(float dc)
	{
		return 0.5f + 0.2820947918f * dc;
	}
}
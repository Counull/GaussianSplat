using System;
using System.IO;
using UnityEngine;
using UnityEngine.Serialization;

/// <summary>
/// https://github.com/graphdeco-inria/gaussian-splatting
/// </summary>
public class PlyRenderer : MonoBehaviour
{
	private static readonly int GaussianColorId = Shader.PropertyToID("_GaussianColor");

	[SerializeField] private string assetName = "";

	[Header("Debug")] [SerializeField] private bool debug = false;
	[SerializeField] private GameObject debugSphere;


	private Importer importer = null;

	private MaterialPropertyBlock debugProperties;

	private void Awake()
	{
		importer = new Importer(Path.Combine(Application.streamingAssetsPath, assetName + ".ply"));
		if (debug) DebugRender();
	}

	private void DebugRender()
	{
		if (debugSphere == null)
		{
			Debug.LogError("Debug Sphere is not assigned.", this);
			return;
		}


		debugProperties ??= new MaterialPropertyBlock();

		foreach (var data in importer.GaussianDatas)
		{
			var point = Instantiate(debugSphere, data.Pos, data.Rotation, gameObject.transform);
			point.transform.localScale = 6f * data.Scale;

			var pointRenderer = point.GetComponent<Renderer>();
			if (pointRenderer == null)
			{
				Debug.LogWarning("Debug Sphere does not contain a Renderer component.", point);
				continue;
			}

			debugProperties.Clear();
			debugProperties.SetColor(GaussianColorId, data.DebugPointColor);
			pointRenderer.SetPropertyBlock(debugProperties);
		}
	}

}

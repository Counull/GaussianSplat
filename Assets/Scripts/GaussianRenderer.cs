using System;
using System.IO;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Serialization;

/// <summary>
/// https://github.com/graphdeco-inria/gaussian-splatting
/// </summary>
public class GaussianRenderer : MonoBehaviour
{
	//我隐约记得这种写法在一些情况下会造成兼容性问题
	private static readonly int GaussianColorId = Shader.PropertyToID("_GaussianColor");
	private static readonly int GaussiansID = Shader.PropertyToID("_Gaussians");
	private static readonly int SortedIndicesID = Shader.PropertyToID("_SortedIndices");
	private static readonly int SplatLocalToWorldID = Shader.PropertyToID("_SplatLocalToWorld");

	[SerializeField] private string assetName = "";
	[SerializeField] private Material material;
	[Header("Debug")] [SerializeField] private bool debug = false;
	[SerializeField] private GameObject debugSphere;


	private Importer importer = null;

	private GraphicsBuffer gaussianBuffer;
	private GraphicsBuffer sortedIndexBuffer;
	private GraphicsBuffer shRestBuffer;

	private MaterialPropertyBlock debugProperties;
	private MaterialPropertyBlock renderProperties;


	private float[] sortKeys;
	private int[] sortedIndices;


	private void Awake()
	{
		importer = new Importer(Path.Combine(Application.streamingAssetsPath, assetName + ".ply"));
		if (debug)
		{
			DebugRender();
		}
		else
		{
			CreateGaussianBuffer();
			CreateShRestBuffer();
			RenderPipelineManager.beginCameraRendering += CameraRender;
		}
	}

	/// <summary>
	/// 用球体近似渲染 Debug专用
	/// </summary>
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

	private void CameraRender(ScriptableRenderContext context, Camera camera)
	{
		if (camera.cameraType != CameraType.Game)
			return;

		SortGaussianIndices(camera);

		renderProperties ??= new MaterialPropertyBlock();
		renderProperties.Clear();
		renderProperties.SetBuffer(GaussiansID, gaussianBuffer);
		renderProperties.SetBuffer(SortedIndicesID, sortedIndexBuffer);
		renderProperties.SetMatrix(SplatLocalToWorldID, transform.localToWorldMatrix);

		var renderParams = new RenderParams(material)
		{
			camera = camera,
			matProps = renderProperties,
			layer = gameObject.layer,
			shadowCastingMode = ShadowCastingMode.Off,
			receiveShadows = false
		};
		Graphics.RenderPrimitives(
			in renderParams,
			MeshTopology.Triangles,
			vertexCount: 6,
			instanceCount: importer.GaussianDatas.Length
		);
	}

	private void CreateGaussianBuffer()
	{
		gaussianBuffer ??= new GraphicsBuffer(GraphicsBuffer.Target.Structured,
			importer.GpuGaussianDatas.Length,
			System.Runtime.InteropServices.Marshal.SizeOf(typeof(GpuGaussianData)));
		gaussianBuffer.SetData(importer.GpuGaussianDatas);
	}

	private void SortGaussianIndices(Camera camera)
	{
		var gaussians = importer.GaussianDatas;
		var localToWorld = transform.localToWorldMatrix;
		var cameraPosition = camera.transform.position;
		var cameraForward = camera.transform.forward;

		sortKeys ??= new float[gaussians.Length];
		sortedIndices ??= new int[gaussians.Length];

		for (var i = 0; i < gaussians.Length; i++)
		{
			Vector3 worldCenter =
				localToWorld.MultiplyPoint3x4(gaussians[i].Pos);

			var depth = Vector3.Dot(
				cameraForward,
				worldCenter - cameraPosition
			);


			sortKeys[i] = -depth;
			sortedIndices[i] = i;
		}

		Array.Sort(sortKeys, sortedIndices);
		
		sortedIndexBuffer ??= new GraphicsBuffer(
			GraphicsBuffer.Target.Structured,
			sortedIndices.Length,
			sizeof(int));
		sortedIndexBuffer.SetData(sortedIndices);
	}

	/// <summary>
	/// https://docs.unity3d.com/6000.0/ScriptReference/GraphicsBuffer.Target.Structured.html
	/// </summary>
	public void CreateShRestBuffer()
	{
		var shRestVectorCount = importer.GaussianDatas[0].RestVectorCount;
		var packedRest = new float4 [importer.GaussianDatas.Length * shRestVectorCount];
		for (int i = 0; i < importer.GaussianDatas.Length; i++)
		{
			for (var restId = 0; restId < importer.GaussianDatas[i].Rest.Length; restId++)
			{
				int vectorId = i * shRestVectorCount + restId / 4;
				int componentId = restId % 4;
				packedRest[vectorId][componentId] = importer.GaussianDatas[i].Rest[restId];
			}
		}

		shRestBuffer = new GraphicsBuffer(
			GraphicsBuffer.Target.Structured,
			packedRest.Length,
			sizeof(float) * 4
		);

		shRestBuffer.SetData(packedRest);
	}
}
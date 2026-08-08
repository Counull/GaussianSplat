using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;
using Newtonsoft.Json;
using Unity.Mathematics;

/// <summary>
/// 依据下述文档实现
/// https://paulbourke.net/dataformats/ply/
/// </summary>
public class Importer
{
	byte[] rawDataCache;
	public const int FLOAT_LEN = 4;
	public GaussianData[] GaussianDatas { get; private set; }
	private int headerOffset;
	private int _vertexCount;
	private int _vertexStride;
	private int _restOffset = -1;
	private int _restFloatCount;
	private Dictionary<string, int> _vertexOffset;

	public Importer(string fullPath)
	{
		LoadByStream(fullPath);
	}

	private void LoadByStream(string fullPath)
	{
		using var file = new FileStream(fullPath, FileMode.Open, FileAccess.Read);
		using var stream = new BufferedStream(file);
		ParseHeader(stream);
		ParseVertex(stream);
	}

	private void ParseHeader(BufferedStream stream)
	{
		var lineBytes = new List<byte>(64);
		for (var i = 0; i < stream.Length; i++)
		{
			var b = stream.ReadByte();
			if (b == -1) throw new Exception("Invalid header");
			if (b == '\r') continue;
			lineBytes.Add((byte) b);
			if (b != '\n') continue;
			var headerLine = Encoding.ASCII.GetString(lineBytes.ToArray()).Trim();
			lineBytes.Clear();

			if (ParseHeaderLine(headerLine))
			{
				headerOffset = (int) stream.Position;
				return;
			}
		}

		throw new Exception("Invalid header");
	}

	private bool ParseHeaderLine(string line)
	{
		if (line.StartsWith("end_header"))
		{
			Debug.Log($"Parse header complete.\n " +
			          $"vertex cout:{_vertexCount}\n" +
			          $"vertex stride:{_vertexStride}\n" +
			          $"vertex offset: {JsonConvert.SerializeObject(_vertexOffset, Formatting.Indented)}\n");
			return true;
		}

		var parts = line.Split(' ');
		if (line.StartsWith("ply")) return false;
		if (line.StartsWith("format")) return false;
		if (line.StartsWith("element vertex"))
		{
			_vertexCount = int.Parse(parts[2]);
			return false;
		}

		if (parts[0] == "property" && parts[1] == "float")
		{
			_vertexOffset ??= new Dictionary<string, int>();
			if (parts[2].StartsWith("f_rest_"))
			{
				if (_restOffset < 0)
				{
					_restOffset = _vertexStride;
				}

				_restFloatCount++;
			}
			else
			{
				_vertexOffset[parts[2]] = _vertexStride;
			}

			_vertexStride += FLOAT_LEN;
		}

		return false;
	}

	private void ParseVertex(BufferedStream stream)
	{
		GaussianDatas ??= new GaussianData[_vertexCount];
		rawDataCache ??= new byte[_vertexStride];

		for (var i = 0; i < _vertexCount; i++)
		{
			var bytesRead = stream.Read(rawDataCache, 0, _vertexStride);
			if (bytesRead != _vertexStride)
				throw new EndOfStreamException();

			GaussianDatas[i].Pos = new Vector3(
				BitConverter.ToSingle(rawDataCache, _vertexOffset["x"]),
				BitConverter.ToSingle(rawDataCache, _vertexOffset["y"]),
				BitConverter.ToSingle(rawDataCache, _vertexOffset["z"])
			);
			GaussianDatas[i].N = new Vector3(
				BitConverter.ToSingle(rawDataCache, _vertexOffset["nx"]),
				BitConverter.ToSingle(rawDataCache, _vertexOffset["ny"]),
				BitConverter.ToSingle(rawDataCache, _vertexOffset["nz"])
			);
			GaussianDatas[i].Dc = new Vector3(
				BitConverter.ToSingle(rawDataCache, _vertexOffset["f_dc_0"]),
				BitConverter.ToSingle(rawDataCache, _vertexOffset["f_dc_1"]),
				BitConverter.ToSingle(rawDataCache, _vertexOffset["f_dc_2"])
			);
			GaussianDatas[i].Rest = new float[_restFloatCount];
			Buffer.BlockCopy(rawDataCache, _restOffset, GaussianDatas[i].Rest, 0, _restFloatCount * FLOAT_LEN);

			GaussianDatas[i].Opacity = BitConverter.ToSingle(rawDataCache, _vertexOffset["opacity"]); //sigmoid
			GaussianDatas[i].Opacity = Sigmoid(GaussianDatas[i].Opacity);

			GaussianDatas[i].Scale = new float3(
				BitConverter.ToSingle(rawDataCache, _vertexOffset["scale_0"]),
				BitConverter.ToSingle(rawDataCache, _vertexOffset["scale_1"]),
				BitConverter.ToSingle(rawDataCache, _vertexOffset["scale_2"])
			);
			GaussianDatas[i].Scale = math.exp(GaussianDatas[i].Scale); //EXP

			GaussianDatas[i].Rotation = new Quaternion(
				BitConverter.ToSingle(rawDataCache, _vertexOffset["rot_1"]),
				BitConverter.ToSingle(rawDataCache, _vertexOffset["rot_2"]),
				BitConverter.ToSingle(rawDataCache, _vertexOffset["rot_3"]),
				BitConverter.ToSingle(rawDataCache, _vertexOffset["rot_0"])
			);
			GaussianDatas[i].Rotation.Normalize(); //归一化四元数
		}

		float Sigmoid(float value)
		{
			return 1f / (1f + math.exp(-value));
		}
	}
}
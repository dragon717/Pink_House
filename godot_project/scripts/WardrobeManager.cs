using Godot;
using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

public partial class WardrobeManager : Node
{
    public class WardrobeItem
    {
        public string Id { get; set; }
        public string Category { get; set; }
        public List<string> Tags { get; set; } = new List<string>();
        public string ImagePath { get; set; }
        public string ImageHash { get; set; }
        public long CreatedAt { get; set; }
    }

    public class Metadata
    {
        public string Version { get; set; } = "1.0";
        public long LastUpdated { get; set; }
        public Dictionary<string, WardrobeItem> Items { get; set; } = new Dictionary<string, WardrobeItem>();
    }

    private string _metadataPath = "user://metadata.json";
    private Metadata _currentMetadata;

    public override void _Ready()
    {
        EnsureDirectories();
        LoadMetadata();
    }

    private void EnsureDirectories()
    {
        var dir = DirAccess.Open("user://");
        if (!dir.DirExists("images"))
        {
            dir.MakeDir("images");
        }
    }

    public void LoadMetadata()
    {
        if (FileAccess.FileExists(_metadataPath))
        {
            using var file = FileAccess.Open(_metadataPath, FileAccess.ModeFlags.Read);
            string jsonString = file.GetAsText();
            try
            {
                _currentMetadata = JsonSerializer.Deserialize<Metadata>(jsonString);
            }
            catch (Exception e)
            {
                GD.PrintErr($"Failed to parse metadata: {e.Message}");
                _currentMetadata = new Metadata();
            }
        }
        else
        {
            _currentMetadata = new Metadata();
        }
    }

    public void SaveMetadata()
    {
        _currentMetadata.LastUpdated = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        string jsonString = JsonSerializer.Serialize(_currentMetadata, new JsonSerializerOptions { WriteIndented = true });
        using var file = FileAccess.Open(_metadataPath, FileAccess.ModeFlags.Write);
        file.StoreString(jsonString);
    }

    public void AddOrUpdateItem(string id, string category, Image image)
    {
        // 1. Process Image
        // Resize logic could go here, for now assuming image is ready or we just compress
        if (image.GetWidth() > 1024 || image.GetHeight() > 1024)
        {
             // Simple resize logic if needed, keeping aspect ratio
             float aspect = (float)image.GetWidth() / image.GetHeight();
             int newW = 1024;
             int newH = (int)(1024 / aspect);
             if (image.GetWidth() < image.GetHeight())
             {
                 newH = 1024;
                 newW = (int)(1024 * aspect);
             }
             image.Resize(newW, newH, Image.Interpolation.Cubic);
        }

        // 2. Compute Hash
        byte[] imageData = image.GetData();
        string newHash = ComputeHash(imageData);

        // 3. Check if update needed
        bool needsWrite = true;
        if (_currentMetadata.Items.ContainsKey(id))
        {
            if (_currentMetadata.Items[id].ImageHash == newHash)
            {
                needsWrite = false;
                GD.Print($"Image for {id} has not changed. Skipping write.");
            }
        }

        string relativePath = $"images/{id}.webp";
        
        if (needsWrite)
        {
            // Save as WebP (Lossy, 0.8 quality)
            string fullPath = "user://" + relativePath;
            Error err = image.SaveWebp(fullPath, true, 0.8f);
            if (err != Error.Ok)
            {
                GD.PrintErr($"Failed to save WebP: {err}");
                return;
            }
            GD.Print($"Saved image to {fullPath}");
        }

        // 4. Update Metadata
        var item = new WardrobeItem
        {
            Id = id,
            Category = category,
            ImagePath = relativePath,
            ImageHash = newHash,
            CreatedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
        };

        _currentMetadata.Items[id] = item;
        SaveMetadata();
    }

    public void DeleteItem(string id)
    {
        if (_currentMetadata.Items.ContainsKey(id))
        {
            string path = "user://" + _currentMetadata.Items[id].ImagePath;
            var dir = DirAccess.Open("user://");
            if (dir.FileExists(path))
            {
                dir.Remove(path);
            }
            _currentMetadata.Items.Remove(id);
            SaveMetadata();
            GD.Print($"Deleted item {id}");
        }
    }

    public Image LoadItemImage(string id)
    {
        if (_currentMetadata.Items.ContainsKey(id))
        {
            string path = "user://" + _currentMetadata.Items[id].ImagePath;
            if (FileAccess.FileExists(path))
            {
                var img = Image.LoadFromFile(path);
                return img;
            }
        }
        return null;
    }

    private string ComputeHash(byte[] data)
    {
        using (SHA256 sha256 = SHA256.Create())
        {
            byte[] hashBytes = sha256.ComputeHash(data);
            return BitConverter.ToString(hashBytes).Replace("-", "").ToLower();
        }
    }
}

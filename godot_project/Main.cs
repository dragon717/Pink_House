using Godot;
using System;
using System.Linq;

public partial class Main : Node2D
{
    private WardrobeManager _wardrobeManager;
    private GestureController _gestureController;
    private Sprite2D _itemSprite;
    private Label _statusLabel;
    private string _lastItemId;

    public override void _Ready()
    {
        // Setup Nodes
        _wardrobeManager = new WardrobeManager();
        AddChild(_wardrobeManager);

        _gestureController = new GestureController();
        AddChild(_gestureController);

        _itemSprite = GetNode<Sprite2D>("ItemContainer/ItemSprite");
        _statusLabel = GetNode<Label>("CanvasLayer/VBoxContainer/StatusLabel");

        // Connect Signals
        _gestureController.Connect(GestureController.SignalName.OnPan, Callable.From<Vector2, Vector2>(OnPan));
        _gestureController.Connect(GestureController.SignalName.OnPinch, Callable.From<float, Vector2>(OnPinch));

        GetNode<Button>("CanvasLayer/VBoxContainer/AddButton").Pressed += OnAddButtonPressed;
        GetNode<Button>("CanvasLayer/VBoxContainer/DeleteButton").Pressed += OnDeleteButtonPressed;

        Log("Ready. Wardrobe Manager Initialized.");
    }

    private void OnAddButtonPressed()
    {
        // Generate a random noise image to simulate a photo
        var img = Image.Create(500, 500, false, Image.Format.Rgba8);
        var noise = new FastNoiseLite();
        noise.Seed = (int)DateTime.Now.Ticks;
        
        for (int x = 0; x < 500; x++)
        {
            for (int y = 0; y < 500; y++)
            {
                float val = noise.GetNoise2D(x, y);
                img.SetPixel(x, y, new Color(val, val, val, 1));
            }
        }

        string id = "item_" + DateTime.Now.Ticks;
        _wardrobeManager.AddOrUpdateItem(id, "top", img);
        _lastItemId = id;

        // Display it
        DisplayItem(id);
        Log($"Added item {id}. Saved as WebP.");
    }

    private void OnDeleteButtonPressed()
    {
        if (!string.IsNullOrEmpty(_lastItemId))
        {
            _wardrobeManager.DeleteItem(_lastItemId);
            _itemSprite.Texture = null;
            Log($"Deleted item {_lastItemId}");
            _lastItemId = null;
        }
        else
        {
            Log("No item to delete.");
        }
    }

    private void DisplayItem(string id)
    {
        var img = _wardrobeManager.LoadItemImage(id);
        if (img != null)
        {
            var tex = ImageTexture.CreateFromImage(img);
            _itemSprite.Texture = tex;
            // Reset Transform
            _itemSprite.Position = new Vector2(375, 667); // Center of 750x1334
            _itemSprite.Scale = Vector2.One;
        }
    }

    private void OnPan(Vector2 delta, Vector2 pos)
    {
        if (_itemSprite.Texture != null)
        {
            _itemSprite.Position += delta;
        }
    }

    private void OnPinch(float scaleFactor, Vector2 center)
    {
        if (_itemSprite.Texture != null)
        {
            _itemSprite.Scale *= scaleFactor;
        }
    }

    private void Log(string msg)
    {
        _statusLabel.Text = msg;
        GD.Print(msg);
    }
}

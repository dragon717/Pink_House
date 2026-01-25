using Godot;
using System;
using System.Collections.Generic;
using System.Linq;

public partial class GestureController : Node
{
    [Signal] public delegate void OnTapEventHandler(Vector2 position);
    [Signal] public delegate void OnPanEventHandler(Vector2 delta, Vector2 position);
    [Signal] public delegate void OnPinchEventHandler(float scaleFactor, Vector2 center);

    private Dictionary<int, Vector2> _touches = new Dictionary<int, Vector2>();
    private float _initialPinchDistance = 0f;
    private bool _isPinching = false;

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event is InputEventScreenTouch touch)
        {
            if (touch.Pressed)
            {
                _touches[touch.Index] = touch.Position;
                if (_touches.Count == 2)
                {
                    _isPinching = true;
                    _initialPinchDistance = _touches.Values.ElementAt(0).DistanceTo(_touches.Values.ElementAt(1));
                }
            }
            else
            {
                if (_touches.ContainsKey(touch.Index))
                {
                    _touches.Remove(touch.Index);
                }
                
                if (_touches.Count < 2)
                {
                    _isPinching = false;
                }

                // Detect Tap (Simple implementation: if pressed and released quickly without much movement - handled roughly here)
                // For robust tap, we should track time and distance. 
                // Here we just emit Tap if it was a single finger release and we weren't pinching.
                if (!_isPinching && touch.Index == 0) 
                {
                    EmitSignal(SignalName.OnTap, touch.Position);
                }
            }
        }
        else if (@event is InputEventScreenDrag drag)
        {
            if (_touches.ContainsKey(drag.Index))
            {
                _touches[drag.Index] = drag.Position;
            }

            if (_touches.Count == 1)
            {
                // Pan
                EmitSignal(SignalName.OnPan, drag.Relative, drag.Position);
            }
            else if (_touches.Count == 2)
            {
                // Pinch
                var pos1 = _touches.Values.ElementAt(0);
                var pos2 = _touches.Values.ElementAt(1);
                float currentDist = pos1.DistanceTo(pos2);
                Vector2 center = (pos1 + pos2) / 2;

                if (_initialPinchDistance > 0.1f) // Avoid div by zero
                {
                    float scaleFactor = currentDist / _initialPinchDistance;
                    EmitSignal(SignalName.OnPinch, scaleFactor, center);
                    
                    // Reset initial distance for relative scaling in next frame if we want continuous delta,
                    // OR keep it for absolute scaling from start of pinch.
                    // Usually for continuous updates (delta), we reset:
                    _initialPinchDistance = currentDist;
                }
            }
        }
    }
}

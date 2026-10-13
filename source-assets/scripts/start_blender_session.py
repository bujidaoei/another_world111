"""Start only the project's dedicated Blender MCP bridge.

Run with Blender --factory-startup --python, never inside a user's existing file.
Asset creation is sent through the live MCP after this process has started.
"""
import bpy
import addon_utils

addon_utils.enable("blender_mcp", default_set=False, persistent=False)
prefs = bpy.context.preferences.addons.get("blender_mcp")
if prefs:
    prefs.preferences.telemetry_consent = False
bpy.context.scene.name = "AnotherWorld_AssetProduction"
bpy.context.scene["another_world_dedicated_session"] = True
print("AnotherWorld dedicated Blender session initialized", flush=True)
